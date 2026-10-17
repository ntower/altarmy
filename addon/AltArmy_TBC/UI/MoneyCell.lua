-- AltArmy TBC — Money table cells: gold, silver and copper with their coin icons lined up down a column.
-- Right-justified: copper takes a fixed-width slot at the right edge and silver the one left of it, so "86c"
-- and "1c" take the same room and each coin sits over the one above. The leading part (gold, else silver,
-- else copper) fills what is left; when gold won't fit there, copper is dropped and the rest shift right,
-- then silver.

AltArmy = AltArmy or {}
AltArmy.MoneyCell = AltArmy.MoneyCell or {}

local M = AltArmy.MoneyCell

-- As SummaryData.GetMoneyString's: the game's coin icons at the small font's size.
M.ICON_SIZE = 12
M.ICONS = {
    gold = "|TInterface\\MoneyFrame\\UI-GoldIcon:" .. M.ICON_SIZE .. ":" .. M.ICON_SIZE .. "|t",
    silver = "|TInterface\\MoneyFrame\\UI-SilverIcon:" .. M.ICON_SIZE .. ":" .. M.ICON_SIZE .. "|t",
    copper = "|TInterface\\MoneyFrame\\UI-CopperIcon:" .. M.ICON_SIZE .. ":" .. M.ICON_SIZE .. "|t",
}
M.GAP = 4 -- room left of a slot's widest number, between it and the coin before

--- The parts of an amount of copper, highest first ({ amount, coin }): copper alone under a silver, silver and
--- copper under a gold, else all three (zeros shown once a higher part is).
function M.Parts(copper)
    copper = math.floor(tonumber(copper) or 0)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local parts = {}
    if gold > 0 then parts[#parts + 1] = { amount = gold, coin = "gold" } end
    if gold > 0 or silver > 0 then parts[#parts + 1] = { amount = silver, coin = "silver" } end
    parts[#parts + 1] = { amount = copper % 100, coin = "copper" }
    return parts
end

--- How many parts to show: all, unless the leading one (leadW wide) is wider than the room the slots right of
--- it leave, then one fewer (copper dropped), then two (silver too). At least one stays.
function M.Fit(count, totalW, slotW, leadW)
    local n = count
    while n > 1 and leadW > totalW - (n - 1) * slotW do
        n = n - 1
    end
    return n
end

-- Slot width per font: two of the widest digit, the icon and the gap.
local slotWidths = {}

local function SlotWidth(fs, font)
    local w = slotWidths[font]
    if w then return w end
    local widest = 0
    for d = 0, 9 do
        fs:SetText(d .. d)
        widest = math.max(widest, fs:GetStringWidth() or 0)
    end
    fs:SetText("")
    w = math.ceil(widest) + M.ICON_SIZE + M.GAP
    slotWidths[font] = w
    return w
end

local function TextWidth(fs)
    if fs.GetUnboundedStringWidth then return fs:GetUnboundedStringWidth() end
    return fs:GetStringWidth()
end

--- A cell (a Frame the caller anchors) of the given width with :SetMoney(copper, mark), :SetText(text) for
--- anything else (a dash), and :SetTextColor(r, g, b, a).
function M.Create(parent, font, width, height)
    local cell = CreateFrame("Frame", nil, parent)
    cell:SetSize(width, height or 20)
    cell.font = font
    cell.texts = {}
    for i = 1, 3 do
        local fs = cell:CreateFontString(nil, "OVERLAY", font)
        fs:SetJustifyH("RIGHT")
        fs:SetWordWrap(false)
        cell.texts[i] = fs
    end

    -- Show strings[1..n], strings[1] leading: each later one in a slot, right to left from the edge.
    local function Place(n, slotW)
        local w = cell:GetWidth()
        for i = 1, 3 do
            local fs = cell.texts[i]
            fs:ClearAllPoints()
            fs:SetShown(i <= n)
        end
        local right = 0
        for i = n, 2, -1 do
            local fs = cell.texts[i]
            fs:SetPoint("RIGHT", cell, "RIGHT", -right, 0)
            fs:SetWidth(slotW)
            right = right + slotW
        end
        local lead = cell.texts[1]
        lead:SetPoint("RIGHT", cell, "RIGHT", -right, 0)
        lead:SetWidth(math.max(1, w - right))
    end

    function cell.SetText(self, text)
        Place(1, 0)
        self.texts[1]:SetText(text or "")
    end

    --- copper nil shows a dash; a negative amount a minus. mark goes before the amount (as "~" for an estimate).
    function cell.SetMoney(self, copper, mark)
        if copper == nil then
            self:SetText("—")
            return
        end
        local prefix = mark or ""
        if copper < 0 then
            prefix = "-" .. prefix
            copper = -copper
        end
        local parts = M.Parts(copper)
        local lead = self.texts[1]
        local slotW = SlotWidth(lead, self.font)
        local leadText = prefix .. parts[1].amount .. M.ICONS[parts[1].coin]
        lead:SetText(leadText)
        local n = M.Fit(#parts, self:GetWidth(), slotW, TextWidth(lead))
        Place(n, slotW)
        lead:SetText(leadText)
        for i = 2, n do
            self.texts[i]:SetText(parts[i].amount .. M.ICONS[parts[i].coin])
        end
    end

    function cell.SetTextColor(self, r, g, b, a)
        for i = 1, 3 do
            self.texts[i]:SetTextColor(r, g, b, a)
        end
    end

    cell:SetText("")
    return cell
end
