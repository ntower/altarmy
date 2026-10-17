-- AltArmy TBC — Characters list/view for Summary tab (Altoholic-style).
-- Builds a list from SummaryData.GetCharacterList(); optional view and sort.
-- Exposes InvalidateView(), GetView(), and Sort() for the UI layer.

AltArmy.Characters = AltArmy.Characters or {}

local ns = AltArmy.Characters

local characterList
local view
local isViewValid

local MAX_LOGOUT_SENTINEL = 5000000000

--- Minutes-since-online sort value: 0 for a logged-in character (here, or on a linked account), elapsed
--- seconds otherwise.
local function GetLastOnlineSortValue(entry)
    if entry and entry.isOnline then
        return 0
    end
    local DS = AltArmy.DataStore
    if entry and DS and DS.IsCurrentCharacter
        and DS:IsCurrentCharacter(entry.name, entry.realm) then
        return 0
    end
    local lo = entry and entry.lastOnline
    if lo == nil or lo >= MAX_LOGOUT_SENTINEL then
        return math.huge
    end
    local now = time and time() or 0
    return now - lo
end

local function BuildList()
    characterList = characterList or {}
    wipe(characterList)
    local raw = AltArmy.SummaryData and AltArmy.SummaryData.GetCharacterList and AltArmy.SummaryData.GetCharacterList()
    if raw then
        for _, entry in ipairs(raw) do
            table.insert(characterList, entry)
        end
    end
end

local function BuildView()
    view = view or {}
    wipe(view)
    if not characterList then return view end
    for i = 1, #characterList do
        table.insert(view, i)
    end
    isViewValid = true
    return view
end

function ns:InvalidateView(_self)
    isViewValid = nil
end

--- Returns the current view (indices into the character list). Rebuilds list and view if invalidated.
--- @return number[] view Array of indices into the character list.
function ns:GetView(_self)
    if not isViewValid then
        BuildList()
        BuildView()
    end
    return view or {}
end

--- Returns the character list (same order as view indices). Rebuilds if invalidated.
--- @return table[] list Array of entries { name = string, realm = string }.
function ns:GetList(_self)
    if not isViewValid then
        BuildList()
        BuildView()
    end
    return characterList or {}
end

--- Sort the character list in place. Call InvalidateView() before if data changed.
--- @param ascending boolean
--- @param sortKey string "name", "realm", "level", "restXp", "money", "played", or "lastOnline"
function ns:Sort(ascending, sortKey)
    local list = self:GetList()
    if #list == 0 then return end
    sortKey = sortKey or "name"
    local numericKeys = {
        level = true, restXp = true, money = true, played = true,
        lastOnline = true, bagSlots = true, bagFree = true, equipmentCount = true,
    }
    if numericKeys[sortKey] then
        table.sort(list, function(a, b)
            if sortKey == "restXp" then
                local aMax = a.isMaxLevel == true
                local bMax = b.isMaxLevel == true
                if aMax ~= bMax then
                    return not aMax
                end
                if aMax and bMax then
                    local ka = (a.realm or "") .. "\0" .. (a.name or "")
                    local kb = (b.realm or "") .. "\0" .. (b.name or "")
                    return ka < kb
                end
                local va = tonumber(a.restXp) or 0
                local vb = tonumber(b.restXp) or 0
                if ascending then
                    if va ~= vb then
                        return va < vb
                    end
                else
                    if va ~= vb then
                        return va > vb
                    end
                end
                local ka = (a.realm or "") .. "\0" .. (a.name or "")
                local kb = (b.realm or "") .. "\0" .. (b.name or "")
                return ka < kb
            end
            local va, vb
            if sortKey == "lastOnline" then
                va = GetLastOnlineSortValue(a)
                vb = GetLastOnlineSortValue(b)
            else
                va = tonumber(a[sortKey]) or 0
                vb = tonumber(b[sortKey]) or 0
            end
            if ascending then
                return va < vb
            else
                return va > vb
            end
        end)
    else
        table.sort(list, function(a, b)
            local va = a[sortKey] or ""
            local vb = b[sortKey] or ""
            if ascending then
                return va < vb
            else
                return va > vb
            end
        end)
    end
end
