--[[
  Every module asks AltArmy.CurrentRealm() for the player's realm, never GetRealmName() directly: on WoW Forever
  1.60.1+ GetRealmName returns "" and the realm is the region and ruleset (ForeverRealm).
  Run from project root: npm test
]]

describe("realm call sites", function()
  -- Files that may read GetRealmName itself: the one place that decides (DataStore, ForeverRealm), and lookups
  -- into other addons' data, which those addons key by GetRealmName.
  local ALLOWED = {
    ["Data\\DataStore\\DataStore.lua"] = true,
    ["Data\\DataStore\\ForeverRealm.lua"] = true,
    ["Data\\DataStore\\DataStoreLevelHistory.lua"] = true,
    ["Data\\Integrations\\RestedXpIntegration.lua"] = true,
  }

  local function tocFiles()
    local files = {}
    for line in io.lines("AltArmy_TBC/AltArmy_TBC.toc") do
      line = line:gsub("\r$", "")
      if line:match("%.lua$") and not line:match("^#") then files[#files + 1] = line end
    end
    return files
  end

  it("loads ForeverRealm right after DataStore", function()
    local files = tocFiles()
    local at
    for i, f in ipairs(files) do
      if f == "Data\\DataStore\\DataStore.lua" then at = i end
    end
    assert.is_not_nil(at)
    assert.are.equal("Data\\DataStore\\ForeverRealm.lua", files[at + 1])
  end)

  it("goes through AltArmy.CurrentRealm everywhere else", function()
    local offenders = {}
    for _, f in ipairs(tocFiles()) do
      if not ALLOWED[f] and not f:match("RecipeData") then
        local path = "AltArmy_TBC/" .. f:gsub("\\", "/")
        local n = 0
        for line in io.lines(path) do
          n = n + 1
          local code = line:gsub("%-%-.*$", "")
          if code:find("GetRealmName()", 1, true) and not code:find("AltArmy.CurrentRealm", 1, true) then
            offenders[#offenders + 1] = f .. ":" .. n
          end
        end
      end
    end
    assert.are.same({}, offenders)
  end)
end)
