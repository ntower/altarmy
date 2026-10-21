-- AltArmy TBC — Onboarding dialog queue: at most one onboarding dialog a session, the first (by priority)
-- whose provider wants to prompt.
-- luacheck: globals C_Timer CreateFrame

if not AltArmy then return end

AltArmy.OnboardingDialogQueue = AltArmy.OnboardingDialogQueue or {}
local ODQ = AltArmy.OnboardingDialogQueue

local providers = {}
local showing = false
local processScheduled = false
local suppressedForSession = false

local function sortProviders()
    table.sort(providers, function(a, b)
        local pa = a.priority or 100
        local pb = b.priority or 100
        if pa ~= pb then return pa < pb end
        return (a.id or "") < (b.id or "")
    end)
end

function ODQ.Register(provider)
    if not provider or not provider.id then return end
    for i = 1, #providers do
        if providers[i].id == provider.id then
            providers[i] = provider
            sortProviders()
            return
        end
    end
    providers[#providers + 1] = provider
    sortProviders()
end

--- Block all further onboarding dialogs for the rest of this session (until relog).
--- Used by providers whose message should preempt everything else this login.
function ODQ.SuppressForSession()
    suppressedForSession = true
end

function ODQ.Process()
    if showing or suppressedForSession then return end
    sortProviders()
    for i = 1, #providers do
        local provider = providers[i]
        local should = provider.shouldPrompt and provider.shouldPrompt() or false
        if should and provider.show then
            showing = true
            suppressedForSession = true -- one onboarding dialog a session: the others wait for the next login
            provider.show(function()
                showing = false
            end)
            return
        end
    end
end

function ODQ.RequestProcess()
    if processScheduled then return end
    processScheduled = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            processScheduled = false
            ODQ.Process()
        end)
    else
        processScheduled = false
        ODQ.Process()
    end
end

function ODQ._ResetForTests()
    providers = {}
    showing = false
    processScheduled = false
    suppressedForSession = false
end

local enterFrame = CreateFrame and CreateFrame("Frame")
if enterFrame then
    enterFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    enterFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            ODQ.RequestProcess()
        end
    end)
end
