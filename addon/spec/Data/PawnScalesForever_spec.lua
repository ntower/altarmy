--[[
  Unit tests for PawnScalesForever.lua (merged hit/crit weights, independence
  from PawnScales.lua, and level overrides).
  Run from project root: npm test
]]

describe("PawnScalesForever", function()
    local PSF
    local PS

    setup(function()
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        _G.AltArmy = _G.AltArmy or {}
        package.loaded["PawnScales"] = nil
        require("PawnScales")
        PS = AltArmy.PawnScales
        package.loaded["PawnScalesForever"] = nil
        require("PawnScalesForever")
        PSF = AltArmy.PawnScalesForever
    end)

    describe("hit/crit merge", function()
        it("Mage Fire: merges spell-only hit/crit into both keys", function()
            local fire = PSF.GetRawScale("MAGE", "fire")
            assert.are.equal(0.93, fire.HitRating)
            assert.are.equal(0.93, fire.SpellHitRating)
            assert.are.equal(0.77, fire.CritRating)
            assert.are.equal(0.77, fire.SpellCritRating)
        end)

        it("Warrior Arms: merges physical-only hit/crit into both keys", function()
            local arms = PSF.GetRawScale("WARRIOR", "arms")
            assert.are.equal(1, arms.HitRating)
            assert.are.equal(1, arms.SpellHitRating)
            assert.are.equal(0.85, arms.CritRating)
            assert.are.equal(0.85, arms.SpellCritRating)
        end)

        it("Enhancement Shaman: keeps the higher of physical/spell for hit and crit", function()
            local enh = PSF.GetRawScale("SHAMAN", "enhancement")
            -- TBC source: HitRating=0.67, SpellHitRating=0.223 -> max is physical's 0.67
            assert.are.equal(0.67, enh.HitRating)
            assert.are.equal(0.67, enh.SpellHitRating)
            -- TBC source: CritRating=0.98, SpellCritRating=0.326 -> max is physical's 0.98
            assert.are.equal(0.98, enh.CritRating)
            assert.are.equal(0.98, enh.SpellCritRating)
        end)

        it("Paladin Protection: keeps the higher of physical/spell when spell is larger", function()
            local prot = PSF.GetRawScale("PALADIN", "protection")
            -- TBC source: HitRating=0.16, SpellHitRating=0.78 -> max is spell's 0.78
            assert.are.equal(0.78, prot.HitRating)
            assert.are.equal(0.78, prot.SpellHitRating)
            -- TBC source: CritRating=0.15, SpellCritRating=0.6 -> max is spell's 0.6
            assert.are.equal(0.6, prot.CritRating)
            assert.are.equal(0.6, prot.SpellCritRating)
        end)

        it("non-hit/crit stats are unchanged from PawnScales.lua's TBC values", function()
            local tbcFire = PS.GetRawScale("MAGE", "fire")
            local foreverFire = PSF.GetRawScale("MAGE", "fire")
            assert.are.equal(tbcFire.SpellDamage, foreverFire.SpellDamage)
            assert.are.equal(tbcFire.FireSpellDamage, foreverFire.FireSpellDamage)
            assert.are.equal(tbcFire.Intellect, foreverFire.Intellect)
            assert.are.equal(tbcFire.Spirit, foreverFire.Spirit)
        end)
    end)

    describe("wand-leveling overrides", function()
        it("copies TBC's wand-leveling values verbatim (not yet re-tuned)", function()
            assert.are.equal(3.5, PSF.GetRawScale("MAGE", "frost", 30).RangedDps)
            assert.are.equal(0.25, PSF.GetRawScale("MAGE", "frost", 30).MeleeDps)
            assert.are.equal(5, PSF.GetRawScale("WARLOCK", "affliction", 40).RangedDps)
            assert.are.equal(6, PSF.GetRawScale("PRIEST", "holy", 25).RangedDps)
        end)

        it("clears at max level, same as TBC", function()
            assert.are.equal(0, PSF.GetRawScale("MAGE", "frost", 70).RangedDps)
        end)
    end)

    describe("tank resistance overrides", function()
        it("tank specs weigh resistance like other specs below max level (small, not zero), and fully at max level", function()
            for _, classFile in ipairs({ "WARRIOR", "PALADIN" }) do
                local leveling = PSF.GetRawScale(classFile, "protection", 40)
                assert.are.equal(0.2, leveling.AllResist)
                assert.are.equal(0.04, leveling.ShadowResist)
                assert.are.equal(1, leveling.Stamina)
                local capped = PSF.GetRawScale(classFile, "protection", 70)
                assert.are.equal(1, capped.AllResist)
                assert.are.equal(0.2, capped.ShadowResist)
            end
        end)
    end)

    describe("independence from PawnScales.lua", function()
        it("RAW is a distinct table object per class", function()
            assert.is_not.equal(PS.RAW, PSF.RAW)
            assert.is_not.equal(PS.RAW.MAGE, PSF.RAW.MAGE)
            assert.is_not.equal(PS.RAW.MAGE.fire, PSF.RAW.MAGE.fire)
        end)

        it("mutating PawnScalesForever.RAW does not affect PawnScales.RAW", function()
            local tbcHit = PS.RAW.MAGE.fire.HitRating
            local foreverHitOriginal = PSF.RAW.MAGE.fire.HitRating
            PSF.RAW.MAGE.fire.HitRating = 999
            assert.are.equal(tbcHit, PS.RAW.MAGE.fire.HitRating)
            PSF.RAW.MAGE.fire.HitRating = foreverHitOriginal
        end)

        it("mutating PawnScales.RAW does not affect PawnScalesForever.RAW", function()
            local foreverHit = PSF.RAW.MAGE.fire.HitRating
            local tbcHitOriginal = PS.RAW.MAGE.fire.HitRating
            PS.RAW.MAGE.fire.HitRating = 999
            assert.are.equal(foreverHit, PSF.RAW.MAGE.fire.HitRating)
            PS.RAW.MAGE.fire.HitRating = tbcHitOriginal
        end)
    end)
end)
