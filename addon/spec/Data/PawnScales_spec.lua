--[[
  Unit tests for PawnScales.lua (raw scales and level overrides).
  Run from project root: npm test
]]

describe("PawnScales", function()
    local PS

    setup(function()
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        _G.AltArmy = _G.AltArmy or {}
        package.loaded["PawnScales"] = nil
        require("PawnScales")
        PS = AltArmy.PawnScales
    end)

    it("GetRawScale without level returns the default scale", function()
        local frost = PS.GetRawScale("MAGE", "frost")
        assert.is_truthy(frost)
        assert.are.equal(1, frost.SpellDamage)
        assert.are.equal(0, frost.RangedDps)
        assert.are.equal(0, frost.MeleeDps)
        assert.are.equal(frost, PS.RAW.MAGE.frost)
    end)

    it("GetRawScale at level 70 returns default wand weights", function()
        local frost = PS.GetRawScale("MAGE", "frost", 70)
        assert.are.equal(0, frost.RangedDps)
        assert.are.equal(0, frost.MeleeDps)
        assert.are.equal(1, frost.SpellDamage)
    end)

    it("GetRawScale merges leveling overrides for wand specs", function()
        assert.are.equal(3.5, PS.GetRawScale("MAGE", "frost", 30).RangedDps)
        assert.are.equal(0.25, PS.GetRawScale("MAGE", "frost", 30).MeleeDps)
        assert.are.equal(3.5, PS.GetRawScale("MAGE", "fire", 1).RangedDps)
        assert.are.equal(3.5, PS.GetRawScale("MAGE", "arcane", 69).RangedDps)

        assert.are.equal(5, PS.GetRawScale("WARLOCK", "affliction", 40).RangedDps)
        assert.are.equal(0.25, PS.GetRawScale("WARLOCK", "demonology", 40).MeleeDps)
        assert.are.equal(5, PS.GetRawScale("WARLOCK", "destruction", 40).RangedDps)

        assert.are.equal(6, PS.GetRawScale("PRIEST", "shadow", 25).RangedDps)
        assert.are.equal(6, PS.GetRawScale("PRIEST", "holy", 25).RangedDps)
        assert.are.equal(6, PS.GetRawScale("PRIEST", "discipline", 25).RangedDps)
        assert.are.equal(0.25, PS.GetRawScale("PRIEST", "holy", 25).MeleeDps)
    end)

    it("tank specs weigh resistance like other specs below max level (small, not zero), and fully at max level", function()
        for _, classFile in ipairs({ "WARRIOR", "PALADIN" }) do
            local leveling = PS.GetRawScale(classFile, "protection", 40)
            assert.are.equal(0.2, leveling.AllResist)
            assert.are.equal(0.04, leveling.FireResist)
            assert.are.equal(0.04, leveling.NatureResist)
            assert.are.equal(1, leveling.Stamina)
            local capped = PS.GetRawScale(classFile, "protection", 70)
            assert.are.equal(1, capped.AllResist)
            assert.are.equal(0.2, capped.FireResist)
        end
    end)

    it("GetRawScale leaves non-overridden keys intact", function()
        local leveled = PS.GetRawScale("MAGE", "frost", 30)
        local default = PS.GetRawScale("MAGE", "frost")
        assert.are.equal(default.SpellDamage, leveled.SpellDamage)
        assert.are.equal(default.Intellect, leveled.Intellect)
        assert.are.equal(default.SpellHitRating, leveled.SpellHitRating)
    end)

    it("overlapping level ranges merge in order (later wins)", function()
        local saved = PS.LEVEL_OVERRIDES.HUNTER
        PS.LEVEL_OVERRIDES.HUNTER = {
            beast = {
                { minLevel = 1, maxLevel = 40, RangedDps = 1 },
                { minLevel = 20, maxLevel = 50, RangedDps = 9 },
            },
        }
        local mid = PS.GetRawScale("HUNTER", "beast", 30)
        assert.are.equal(9, mid.RangedDps)
        local early = PS.GetRawScale("HUNTER", "beast", 10)
        assert.are.equal(1, early.RangedDps)
        local late = PS.GetRawScale("HUNTER", "beast", 45)
        assert.are.equal(9, late.RangedDps)
        PS.LEVEL_OVERRIDES.HUNTER = saved
    end)

    it("does not override non-wand casters", function()
        assert.are.equal(0, PS.GetRawScale("DRUID", "balance", 30).RangedDps)
        assert.are.equal(0, PS.GetRawScale("SHAMAN", "elemental", 30).RangedDps)
        assert.are.equal(0, PS.GetRawScale("PALADIN", "holy", 30).RangedDps)
    end)

    describe("wand-leveling cutoff under a different level cap", function()
        local savedDataStore

        setup(function()
            savedDataStore = _G.AltArmy.DataStore
        end)

        teardown(function()
            -- Restore the default (TBC 70) cap so any later spec file sharing
            -- this Lua process sees AltArmy.PawnScales built for a 70 cap again.
            _G.AltArmy.DataStore = savedDataStore
            package.loaded["PawnScales"] = nil
            require("PawnScales")
            PS = AltArmy.PawnScales
        end)

        it("clears one level before the cap when MAX_LEVEL is 60", function()
            _G.AltArmy.DataStore = { MAX_LEVEL = 60 }
            package.loaded["PawnScales"] = nil
            require("PawnScales")
            local capped = AltArmy.PawnScales

            assert.are.equal(3.5, capped.GetRawScale("MAGE", "frost", 59).RangedDps)
            assert.are.equal(0, capped.GetRawScale("MAGE", "frost", 60).RangedDps)
        end)
    end)
end)
