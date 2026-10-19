-- AltArmy TBC — The Summary, Gear, Reputation and Currency settings panels' controls, stacked under
-- `opts.anchorTo`: Realm filter, (Summary only) Group characters, Level filter (a slider with a low and a high
-- handle) and Class filter, each editing
-- the tab's own `settings.filter` (Data/Characters/CharacterFilter.lua); then Pin individual characters
-- (Current character, i.e. `settings.showSelfFirst`, and each character) and Hide individual characters,
-- over the tab's per-character pin / hide settings.

if not AltArmy then return end

local Theme = AltArmy.Theme
local CF = AltArmy.CharacterFilter

local CHARACTER_ROWS_SHOWN = 12 -- the pin and hide dropdowns scroll past this many rows
local SELF_KEY = "self"
local SELF_LABEL = "Current character"

--- @param parent Frame the settings panel's content frame
--- @param opts table anchorTo (Frame to stack under), dropdownParent (the settings panel: popups draw above
---   what is under them), getSettings() -> the tab's settings table, onChange(kind, key, checked)
---   ("scope" | "levels" | "classes" | "group" | "pin" | "hide"; key and checked nil for "levels"),
---   groupCheckbox = { get(), set(on) } for the
---   Summary's grouping, getCharSetting(name, realm, "pin" | "hide"), setCharSetting(name, realm, pin, hide),
---   skipBankAlts (bank alts are always hidden on the tab, so not listed)
--- @return table { bottom = Frame to anchor the next row under, refresh(), Close() }
function AltArmy.CreateCharacterFilterControls(parent, opts)
    opts = opts or {}
    local onChange = opts.onChange or function() end
    local function filter()
        return CF.Ensure(opts.getSettings())
    end

    local dropdowns = {}
    local function dropdown(config)
        config.parent = parent
        config.dropdownParent = opts.dropdownParent or parent
        config.relativePoint = "BOTTOMLEFT"
        config.y = -8
        local api = Theme.CreateMultiSelectCheckboxDropdown(config)
        dropdowns[#dropdowns + 1] = api
        return api
    end
    local function hasLinks()
        local LS = AltArmy.LinkStore
        return LS and LS.HasLinks and LS.HasLinks() or false
    end
    local realm = dropdown({
        relativeTo = opts.anchorTo,
        title = "Realm filter",
        getKeys = function() return CF.ScopeKeys(hasLinks()) end, -- linked accounts once there are any
        labels = CF.SCOPE_LABELS,
        lockedKeys = CF.LOCKED_SCOPE_KEYS,
        getFilter = function() return CF.ScopeFilterMap(filter()) end,
        setEnabled = function(key, on) CF.SetScope(filter(), key, on) end,
        formatSummary = function() return CF.FormatScopeSummary(filter(), hasLinks()) end,
        onChange = function(key, on)
            for _, d in ipairs(dropdowns) do
                d.refresh() -- the pin and hide lists follow the realm filter
            end
            onChange("scope", key, on)
        end,
    })
    local below = realm.button

    local groupRow
    if opts.groupCheckbox then
        groupRow = Theme.CreateLabeledCheckbox(parent, {
            point = "TOPLEFT",
            relativeTo = below,
            relativePoint = "BOTTOMLEFT",
            x = 0,
            y = -8,
            text = "Group characters",
            fullWidthHover = true,
            onClick = function(checked)
                opts.groupCheckbox.set(checked and true or false)
                onChange("group", nil, checked)
            end,
        })
        Theme.AttachSettingsHelpIcon(groupRow, {
            title = "Group characters",
            lines = {
                "Lists each realm and faction's characters under its own heading, this realm's first.",
                "Click a heading to fold its characters away.",
            },
        })
        below = groupRow
    end

    local maxLevel = CF.MaxLevel()
    local level = Theme.CreateRangeSlider(parent, {
        relativeTo = below,
        relativePoint = "BOTTOMLEFT",
        y = -8,
        text = "Level filter",
        labelFont = Theme.FONTS.heading,
        min = 1,
        max = maxLevel,
        low = filter().levelMin,
        high = filter().levelMax,
        format = function(lo, hi) return CF.FormatLevelRange(lo, hi, maxLevel) end,
        onChange = function(lo, hi)
            CF.SetLevelRange(filter(), lo, hi, maxLevel)
            onChange("levels", nil, nil)
        end,
    })

    local classLabels = {}
    for _, classFile in ipairs(CF.CLASS_ORDER) do
        classLabels[classFile] = CF.ClassLabel(classFile)
    end
    local class = dropdown({
        relativeTo = level,
        title = "Class filter",
        keys = CF.CLASS_ORDER,
        labels = classLabels,
        getRowLabel = CF.ClassRowLabel,
        getFilter = function() return filter().classes end,
        setEnabled = function(key, on) CF.SetClass(filter(), key, on) end,
        formatSummary = function(_, _, map) return CF.FormatClassSummary(map) end,
        onChange = function(key, on) onChange("classes", key, on) end,
    })

    -- Pin / hide: the characters the tab's realm filter shows (never its level or class filter, so one those
    -- leave out can still be pinned or hidden).
    local choices = { keys = {}, labels = {}, byKey = {} }
    local function loadChoices()
        -- not before the panel shows: the character list would be built (and kept) before saved data loads
        local host = opts.dropdownParent
        if host and host.IsVisible and not host:IsVisible() then
            return
        end
        local all = AltArmy.Characters and AltArmy.Characters.GetList and AltArmy.Characters:GetList() or {}
        local ctx = CF.Context()
        local list = CF.FilterList(all, filter(), ctx, { scopeOnly = true })
        local BA = AltArmy.BankAlt
        local keys, labels, byKey = CF.CharacterChoices(list, {
            currentRealm = ctx.currentRealm,
            currentFaction = ctx.currentFaction,
            skip = opts.skipBankAlts and function(e)
                return BA and BA.Is and BA.Is(e.name, e.realm) or false
            end or nil,
        })
        choices.keys, choices.labels, choices.byKey = keys, labels, byKey
    end
    local function characterRowLabel(key)
        local e = choices.byKey[key]
        if not e then
            return choices.labels[key] or key
        end
        local RF = AltArmy.RealmFilter
        local withRealm = choices.labels[key] ~= (e.name or "")
        return RF.formatColoredCharacterNameRealm(e.name or "?", e.realm, withRealm, e.classFile, false)
    end
    local function charSetting(key, which)
        local e = choices.byKey[key]
        return e and opts.getCharSetting and opts.getCharSetting(e.name, e.realm, which) or false
    end
    local function chosenMap(which, withSelf)
        local map = {}
        if withSelf then
            map[SELF_KEY] = opts.getSettings().showSelfFirst == true
        end
        for _, key in ipairs(choices.keys) do
            map[key] = charSetting(key, which) and true or false
        end
        return map
    end
    local function setCharacter(key, pin, hide)
        local e = choices.byKey[key]
        if e and opts.setCharSetting then
            opts.setCharSetting(e.name, e.realm, pin, hide)
        end
    end
    -- the pin and hide summaries name the chosen characters as their rows do, in class colour
    local function chosenSummary(keys, map)
        local labels = {}
        for _, key in ipairs(keys) do
            labels[key] = key == SELF_KEY and SELF_LABEL or characterRowLabel(key)
        end
        return CF.FormatChosenSummary(keys, labels, map)
    end

    local hide
    local pin = dropdown({
        relativeTo = class.button,
        title = "Pin individual characters",
        maxVisibleRows = CHARACTER_ROWS_SHOWN,
        isDivider = CF.IsDividerKey,
        getKeys = function()
            loadChoices()
            -- Current character first, in no group; then each realm and faction's characters, each group
            -- under a divider naming it
            local keys = { SELF_KEY }
            for _, key in ipairs(choices.keys) do keys[#keys + 1] = key end
            return keys
        end,
        getLabels = function()
            local labels = { [SELF_KEY] = SELF_LABEL }
            for key, label in pairs(choices.labels) do labels[key] = label end
            return labels
        end,
        getRowLabel = function(key)
            if key == SELF_KEY then return SELF_LABEL end
            return characterRowLabel(key)
        end,
        getFilter = function() return chosenMap("pin", true) end,
        setEnabled = function(key, on)
            if key == SELF_KEY then
                opts.getSettings().showSelfFirst = on and true or false
            else
                setCharacter(key, on, false) -- pinning one unhides it
            end
        end,
        formatSummary = function(keys, _, map) return chosenSummary(keys, map) end,
        onChange = function(key, on)
            if hide then hide.refresh() end
            onChange("pin", key, on)
        end,
    })
    hide = dropdown({
        relativeTo = pin.button,
        title = "Hide individual characters",
        maxVisibleRows = CHARACTER_ROWS_SHOWN,
        isDivider = CF.IsDividerKey,
        getKeys = function()
            loadChoices()
            return choices.keys
        end,
        getLabels = function() return choices.labels end,
        getRowLabel = characterRowLabel,
        getFilter = function() return chosenMap("hide", false) end,
        setEnabled = function(key, on) setCharacter(key, false, on) end, -- hiding one unpins it
        formatSummary = function(keys, _, map) return chosenSummary(keys, map) end,
        onChange = function(key, on)
            pin.refresh()
            onChange("hide", key, on)
        end,
    })

    local api = { bottom = hide.button }

    function api.refresh()
        for _, d in ipairs(dropdowns) do
            d.refresh()
        end
        local f = filter()
        level.SetValues(f.levelMin, f.levelMax)
        if groupRow then
            groupRow.check:SetChecked(opts.groupCheckbox.get() and true or false)
        end
    end

    function api.Close()
        for _, d in ipairs(dropdowns) do
            d:Close()
        end
    end

    api.refresh()
    return api
end
