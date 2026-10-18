--[[
  Unit tests for EmptySlotArt.lua (the game's empty-slot art for the Gear grid).
  Run from project root: npm test
]]

describe("EmptySlotArt", function()
  local ESA

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/Data/Gear/?.lua"
    require("EmptySlotArt")
    ESA = AltArmy.EmptySlotArt
  end)

  before_each(function()
    _G.GetInventorySlotInfo = nil
    ESA.ResetCache()
  end)

  it("asks the game for the slot's empty-slot texture", function()
    local asked
    _G.GetInventorySlotInfo = function(slotName)
      asked = slotName
      return 1, "Interface\\Paperdoll\\UI-PaperDoll-Slot-Head-FromGame"
    end
    assert.are.equal("Interface\\Paperdoll\\UI-PaperDoll-Slot-Head-FromGame", ESA.TextureFor(1))
    assert.are.equal("HeadSlot", asked)
  end)

  it("falls back to the known paperdoll art without the API", function()
    assert.are.equal("Interface\\Paperdoll\\UI-PaperDoll-Slot-Head", ESA.TextureFor(1))
    assert.are.equal("Interface\\Paperdoll\\UI-PaperDoll-Slot-Chest", ESA.TextureFor(15))
    assert.are.equal("Interface\\Paperdoll\\UI-PaperDoll-Slot-SecondaryHand", ESA.TextureFor(17))
    assert.are.equal("Interface\\Paperdoll\\UI-PaperDoll-Slot-Ranged", ESA.TextureFor(18))
  end)

  it("falls back when the API gives no texture", function()
    _G.GetInventorySlotInfo = function() return 2 end
    assert.are.equal("Interface\\Paperdoll\\UI-PaperDoll-Slot-Neck", ESA.TextureFor(2))
  end)

  it("covers every equipment slot the grid shows", function()
    for slot = 1, 19 do
      assert.is_string(ESA.TextureFor(slot), "slot " .. slot)
    end
  end)

  it("knows nothing for slots outside the grid", function()
    assert.is_nil(ESA.TextureFor(0))
    assert.is_nil(ESA.TextureFor(20))
    assert.is_nil(ESA.TextureFor(nil))
  end)

  it("asks the game once per slot", function()
    local calls = 0
    _G.GetInventorySlotInfo = function() calls = calls + 1; return 5, "tex" end
    ESA.TextureFor(5)
    ESA.TextureFor(5)
    assert.are.equal(1, calls)
  end)
end)
