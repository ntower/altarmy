-- AltArmy TBC — The game's empty-slot art (what the character pane shows in an empty slot),
-- by inventory slot id, for the Gear grid's empty cells.
-- luacheck: globals GetInventorySlotInfo

AltArmy = AltArmy or {}
AltArmy.EmptySlotArt = AltArmy.EmptySlotArt or {}

local ESA = AltArmy.EmptySlotArt

-- Inventory slot id -> the global slot name GetInventorySlotInfo takes.
local SLOT_NAMES = {
    [1] = "HeadSlot",
    [2] = "NeckSlot",
    [3] = "ShoulderSlot",
    [4] = "ShirtSlot",
    [5] = "ChestSlot",
    [6] = "WaistSlot",
    [7] = "LegsSlot",
    [8] = "FeetSlot",
    [9] = "WristSlot",
    [10] = "HandsSlot",
    [11] = "Finger0Slot",
    [12] = "Finger1Slot",
    [13] = "Trinket0Slot",
    [14] = "Trinket1Slot",
    [15] = "BackSlot",
    [16] = "MainHandSlot",
    [17] = "SecondaryHandSlot",
    [18] = "RangedSlot",
    [19] = "TabardSlot",
}

-- What the client's paperdoll uses, should GetInventorySlotInfo be missing or give no texture.
local PAPERDOLL = "Interface\\Paperdoll\\UI-PaperDoll-Slot-"
local FALLBACK = {
    [1] = PAPERDOLL .. "Head",
    [2] = PAPERDOLL .. "Neck",
    [3] = PAPERDOLL .. "Shoulder",
    [4] = PAPERDOLL .. "Shirt",
    [5] = PAPERDOLL .. "Chest",
    [6] = PAPERDOLL .. "Waist",
    [7] = PAPERDOLL .. "Legs",
    [8] = PAPERDOLL .. "Feet",
    [9] = PAPERDOLL .. "Wrists",
    [10] = PAPERDOLL .. "Hands",
    [11] = PAPERDOLL .. "Finger",
    [12] = PAPERDOLL .. "Finger",
    [13] = PAPERDOLL .. "Trinket",
    [14] = PAPERDOLL .. "Trinket",
    [15] = PAPERDOLL .. "Chest",
    [16] = PAPERDOLL .. "MainHand",
    [17] = PAPERDOLL .. "SecondaryHand",
    [18] = PAPERDOLL .. "Ranged",
    [19] = PAPERDOLL .. "Tabard",
}

local cache = {}

function ESA.ResetCache()
    cache = {}
end

--- The empty-slot texture path for an inventory slot id (1-19), nil for any other.
function ESA.TextureFor(invSlot)
    local name = invSlot and SLOT_NAMES[invSlot]
    if not name then return nil end
    local hit = cache[invSlot]
    if hit then return hit end
    local tex
    if GetInventorySlotInfo then
        local ok, _, apiTex = pcall(GetInventorySlotInfo, name)
        if ok and type(apiTex) == "string" and apiTex ~= "" then
            tex = apiTex
        end
    end
    tex = tex or FALLBACK[invSlot]
    cache[invSlot] = tex
    return tex
end
