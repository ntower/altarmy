--[[
  Unit tests for PawnScale.lua (Pawn key translation).
  Run from project root: npm test
]]

describe("PawnScale", function()
    local GU

    setup(function()
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        _G.AltArmy = _G.AltArmy or {}
        package.loaded["PawnScale"] = nil
        require("PawnScale")
        GU = AltArmy.GearUpgrade
    end)

    it("PawnScaleToWeights maps primary stats", function()
        local w = GU.PawnScaleToWeights({ Strength = 1, Agility = 0.5, Stamina = 0.5 })
        assert.are.equal(1, w.str)
        assert.are.equal(0.5, w.agi)
        assert.are.equal(0.5, w.sta)
    end)

    it("PawnScaleToWeights splits spell and physical ratings", function()
        local w = GU.PawnScaleToWeights({
            HitRating = 1,
            SpellHitRating = 0.9,
            CritRating = 0.8,
            SpellCritRating = 1.05,
        })
        assert.are.equal(1, w.hit)
        assert.are.equal(0.9, w.spell_hit)
        assert.are.equal(0.8, w.crit)
        assert.are.equal(1.05, w.spell_crit)
    end)

    it("PawnScaleToWeights maps per-school spell damage and SpellDamage to sp", function()
        local w = GU.PawnScaleToWeights({
            SpellDamage = 1,
            FireSpellDamage = 0.94,
            ShadowSpellDamage = 1,
        })
        assert.are.equal(1, w.sp)
        assert.are.equal(0.94, w.fire_sp)
        assert.are.equal(1, w.shadow_sp)
    end)

    it("PawnScaleToWeights keeps AllResist as its own weight, not added to each school", function()
        -- AllResist (0.2) is the worth of +1 to all resistances, the five schools' 0.04 summed;
        -- a single school is worth only its own weight.
        local w = GU.PawnScaleToWeights({ AllResist = 1, FireResist = 0.2 })
        assert.are.equal(1, w.all_res)
        assert.are.equal(0.2, w.fire_res)
        assert.is_nil(w.frost_res)
        assert.is_nil(w.arcane_res)
    end)

    it("PawnScaleToWeights maps weapon DPS keys and ignores sockets", function()
        local w = GU.PawnScaleToWeights({
            MeleeDps = 5.22,
            RangedDps = 2.4,
            RedSocket = 10,
            MetaSocket = 16,
        })
        assert.are.equal(5.22, w.melee_dps)
        assert.are.equal(2.4, w.ranged_dps)
        assert.is_nil(w.RedSocket)
    end)

    it("PawnScaleToWeights skips zero and negative weights", function()
        local w = GU.PawnScaleToWeights({ Strength = 0, Agility = -1, Stamina = 0.5 })
        assert.is_nil(w.str)
        assert.is_nil(w.agi)
        assert.are.equal(0.5, w.sta)
    end)
end)
