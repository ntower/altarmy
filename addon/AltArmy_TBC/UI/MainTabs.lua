-- AltArmy TBC — Main window tab registry: order, labels, portrait/side-tab icons, settings routing.
-- Pure data; Core.lua builds the side tabs, title, portrait and toolbar settings button from it.

AltArmy = AltArmy or {}
AltArmy.MainTabs = AltArmy.MainTabs or {}

local MainTabs = AltArmy.MainTabs

local ADDON_TITLE = "Alt Army"
local ICON_PREFIX = "Interface\\Icons\\"

-- "Guild" stays last so hiding it (no guilded characters) never leaves a gap in the stack.
MainTabs.ORDER = { "Summary", "Economy", "Gear", "Inventory", "Reputation", "Cooldowns", "Graph", "Guild" }

-- settings.toggle / settings.isShown: method names on AltArmy.TabFrames[name].
-- settings.isAvailable: optional method name; when it returns false the tab shows no settings button.
-- headerSearch: show the toolbar item/recipe search on this tab (always shown in search mode).
-- slash: the tab's word in `/alta <slash> [view]` (UI/Options.lua); views: its sub-view tabs' names -> their
-- words, setView: the tab frame's function that switches to one (called with the view name).
local DEFS = {
    Summary = {
        label = "Summary",
        slash = "summary",
        icon = "INV_Misc_Book_09",
        headerSearch = true, -- toolbar item/recipe search; other tabs hide it
        settings = { toggle = "ToggleSummarySettings", isShown = "IsSummarySettingsShown" },
    },
    Gear = {
        label = "Gear",
        slash = "gear",
        views = { grid = "grid", upgrade = "upgrade" },
        setView = "SetGearView",
        icon = "INV_Chest_Plate01",
        settings = { toggle = "ToggleGearSettings", isShown = "IsGearSettingsShown" },
    },
    Inventory = {
        label = "Inventory",
        slash = "inventory",
        views = { bags = "bags", bank = "bank", mail = "mail" },
        setView = "SetInventoryView",
        icon = "INV_Misc_Bag_10", -- one character's bags, bank and mail, drawn like the stock windows
    },
    Economy = {
        label = "Economy",
        slash = "economy",
        views = { currency = "currency", waylaid = "crates", writs = "writs", supply = "supply" },
        setView = "SetEconomyView",
        icon = "INV_Misc_Coin_02", -- WoW Forever only: Tabs/TabEconomy.lua hides it elsewhere
        -- Only the Currency view has settings; the button hides on the other views.
        settings = {
            toggle = "ToggleEconomySettings",
            isShown = "IsEconomySettingsShown",
            isAvailable = "IsEconomySettingsAvailable",
        },
    },
    Reputation = {
        label = "Reputation",
        slash = "reputation",
        nativeIcon = "INV_SideTab_Reputation2_c60", -- Forever CharacterFrame Reputation tab
        settings = { toggle = "ToggleReputationSettings", isShown = "IsReputationSettingsShown" },
    },
    Cooldowns = {
        label = "Cooldowns",
        slash = "cooldowns",
        views = { crafting = "crafting", raids = "dungeons" },
        setView = "SetCooldownsView",
        icon = "INV_Misc_PocketWatch_01",
        settings = { toggle = "ToggleCooldownSettings", isShown = "IsCooldownSettingsShown" },
    },
    Graph = {
        label = "Graphs",
        slash = "graphs",
        nativeIcon = "INV_SideTab_Stats_c60", -- Forever CharacterFrame Statistics tab
        settings = { toggle = "ToggleGraphSettings", isShown = "IsGraphSettingsShown" }, -- starts shown
    },
    Guild = {
        label = "Guild",
        slash = "guild", -- its profession tabs change with the guildmate picked: no commands
        icon = "INV_Shirt_GuildTabard_01", -- shown when the player has no guild crest
        guildCrest = true,
    },
    -- Header search results; no side tab.
    Search = {
        label = "Search",
        icon = "INV_Misc_Spyglass_02",
        settings = { toggle = "ToggleSearchSettings", isShown = "IsSearchSettingsShown" },
    },
}

-- nativeIcon: Forever's CharacterFrame side-tab icons (*_c60). They exist only in Forever's
-- game data, so TBC Anniversary uses byte-identical copies bundled under Textures/Icons
-- (extracted from Forever's CASC storage; see docs/UI_DESIGN.md). Forever keeps the game file
-- so its reskin applies.
local BUNDLED_ICON_PREFIX = "Interface\\AddOns\\AltArmy_TBC\\Textures\\Icons\\"
local isMainline = _G.WOW_PROJECT_ID ~= nil and _G.WOW_PROJECT_ID == (_G.WOW_PROJECT_MAINLINE or 1)

for name, def in pairs(DEFS) do
    def.name = name
    if def.nativeIcon then
        def.icon = (isMainline and ICON_PREFIX or BUNDLED_ICON_PREFIX) .. def.nativeIcon
    else
        def.icon = ICON_PREFIX .. def.icon
    end
    def.nativeIcon = nil
end

function MainTabs.Get(name)
    if name == nil then return nil end
    return DEFS[name]
end

--- Side-tab definitions in display order (excludes Search).
function MainTabs.List()
    local list = {}
    for i, name in ipairs(MainTabs.ORDER) do
        list[i] = DEFS[name]
    end
    return list
end

--- Window title for a tab, e.g. "Alt Army - Reputation".
function MainTabs.Title(name)
    local def = DEFS[name]
    if not def then return ADDON_TITLE end
    return ADDON_TITLE .. " - " .. def.label
end

MainTabs.SLASH = "/alta"

--- The slash command that opens a tab, or one of its sub-views: "/alta economy crates". nil for a tab or
--- view without one (Search, the Guild tab's professions).
function MainTabs.SlashCommand(tabName, viewName)
    local def = DEFS[tabName]
    if not (def and def.slash) then return nil end
    if viewName == nil then
        return MainTabs.SLASH .. " " .. def.slash
    end
    local word = def.views and def.views[viewName]
    return word and (MainTabs.SLASH .. " " .. def.slash .. " " .. word) or nil
end

-- A word stands for a keyword written as it is or without its plural "s" (graph, crate).
local function wordMatches(word, keyword)
    return word == keyword or word .. "s" == keyword
end

--- What `/alta <msg>` asks for when its first word names a tab: tabName, viewName (nil: the tab as it
--- opens) and whether the rest is valid (false: an unknown view or extra words, which do nothing).
--- nil when the first word names no tab, so other commands keep their words.
function MainTabs.ParseSlash(msg)
    local words = {}
    for word in tostring(msg or ""):lower():gmatch("%S+") do
        words[#words + 1] = word
    end
    if #words == 0 then return nil end
    for _, name in ipairs(MainTabs.ORDER) do
        local def = DEFS[name]
        if wordMatches(words[1], def.slash) then
            if #words == 1 then return name, nil, true end
            if #words == 2 and def.views then
                for viewName, keyword in pairs(def.views) do
                    if wordMatches(words[2], keyword) then return name, viewName, true end
                end
            end
            return name, nil, false
        end
    end
    return nil
end

for _, name in ipairs(MainTabs.ORDER) do
    DEFS[name].command = MainTabs.SlashCommand(name)
end
