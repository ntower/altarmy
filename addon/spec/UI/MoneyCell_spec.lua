--[[
  Unit tests for MoneyCell.lua (which coin parts a money cell shows, and which it drops to fit).
  Run from project root: npm test
]]

describe("MoneyCell", function()
  local M

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/UI/?.lua"
    require("MoneyCell")
    M = AltArmy.MoneyCell
  end)

  local function shown(copper)
    local out = {}
    for _, p in ipairs(M.Parts(copper)) do
      out[#out + 1] = p.amount .. p.coin:sub(1, 1)
    end
    return table.concat(out, " ")
  end

  it("shows a negative cost as a gain of its size, in green", function()
    local amount, prefix, color = M.CostStyle(-1250)
    assert.are.equal(1250, amount)
    assert.are.equal("gain ", prefix)
    assert.are.same(M.GAIN_COLOR, color)
  end)

  it("shows a cost as it is, in white, and none as a grey dash", function()
    local amount, prefix, color = M.CostStyle(300)
    assert.are.equal(300, amount)
    assert.are.equal("", prefix)
    assert.are.same(M.COST_COLOR, color)
    amount, prefix, color = M.CostStyle(nil)
    assert.is_nil(amount)
    assert.is_nil(prefix)
    assert.are.same(M.NONE_COLOR, color)
  end)

  it("shows copper alone under a silver", function()
    assert.are.equal("0c", shown(0))
    assert.are.equal("86c", shown(86))
  end)

  it("shows silver and copper under a gold", function()
    assert.are.equal("1s 0c", shown(100))
    assert.are.equal("99s 99c", shown(9999))
  end)

  it("shows all three from a gold, zeros included", function()
    assert.are.equal("1g 0s 0c", shown(10000))
    assert.are.equal("12g 3s 4c", shown(120304))
  end)

  it("keeps every part while the leading one fits", function()
    assert.are.equal(3, M.Fit(3, 100, 30, 40))
  end)

  it("drops copper, then silver, as the leading part outgrows its room", function()
    assert.are.equal(2, M.Fit(3, 100, 30, 41))
    assert.are.equal(2, M.Fit(3, 100, 30, 70))
    assert.are.equal(1, M.Fit(3, 100, 30, 71))
    assert.are.equal(1, M.Fit(3, 100, 30, 500))
  end)
end)
