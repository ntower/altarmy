--[[ Unit tests for LinkAccountsOnboarding.lua (when to offer linking) — run: npm test ]]

describe("LinkAccountsOnboarding", function()
    local LAO, view, requested, enabled, processed

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/UI/?.lua"
        local savedTheme = AltArmy.Theme
        AltArmy.Theme = nil -- the logic only: the dialog needs the client
        package.loaded["LinkAccountsOnboarding"] = nil
        require("LinkAccountsOnboarding")
        AltArmy.Theme = savedTheme
        LAO = AltArmy.LinkAccountsOnboarding
        assert.truthy(LAO)
    end)

    before_each(function()
        _G.AltArmyTBC_Options = {}
        view, requested, enabled, processed = {}, {}, true, 0
        AltArmy.LinkTransport = {
            IsEnabled = function() return enabled end,
            View = function() return view end,
            RequestLink = function(g)
                requested[#requested + 1] = g
                return true
            end,
        }
        AltArmy.OnboardingDialogQueue = {
            RequestProcess = function() processed = processed + 1 end,
        }
    end)

    local function unlinked(fields)
        local e = { acct = "abc", g = 2, linked = false, online = true, label = "Stheno" }
        for k, v in pairs(fields or {}) do e[k] = v end
        return e
    end

    it("offers an online account that isn't linked", function()
        view = { { acct = "lnk", g = 3, linked = true, online = true }, unlinked() }
        assert.are.equal("abc", LAO.Candidate(view).acct)
        assert.is_true(LAO.ShouldPrompt())
    end)

    it("doesn't offer linked, offline or busy accounts", function()
        assert.is_nil(LAO.Candidate({ { acct = "a", g = 1, linked = true, online = true } }))
        assert.is_nil(LAO.Candidate({ unlinked({ online = false, g = nil }) }))
        assert.is_nil(LAO.Candidate({ unlinked({ incoming = true }) }))
        assert.is_nil(LAO.Candidate({ unlinked({ waitingCode = "1234" }) }))
        assert.is_nil(LAO.Candidate({ unlinked({ declined = true }) }))
    end)

    it("prompts only once ever", function()
        view = { unlinked() }
        LAO.Dismiss()
        assert.is_true(AltArmyTBC_Options.linkAccountsOnboardingShown)
        assert.is_false(LAO.ShouldPrompt())
    end)

    it("doesn't prompt with linked accounts off", function()
        view = { unlinked() }
        enabled = false
        assert.is_false(LAO.ShouldPrompt())
    end)

    it("asks the queue to show it only when it should", function()
        LAO.Check()
        assert.are.equal(0, processed)
        view = { unlinked() }
        LAO.Check()
        assert.are.equal(1, processed)
    end)

    it("requests the link by the account's game account id now", function()
        view = { unlinked({ g = 5 }) }
        assert.is_true(LAO.RequestLink("abc"))
        assert.are.same({ 5 }, requested)
    end)

    it("doesn't request when the other account asked us meanwhile", function()
        view = { unlinked({ incoming = true }) }
        assert.is_false(LAO.RequestLink("abc"))
        assert.are.same({}, requested)
    end)
end)
