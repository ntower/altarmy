-- Bootstrap for busted. Run as: lua scripts/busted_bootstrap.lua [spec path...]
-- Prepend vendored busted (cwd = project root) so busted and deps are found.
-- With no args, .busted sets ROOT = { "spec" } (top-level spec/, outside addon zip).
package.path = "busted-2.1.1/?.lua;busted-2.1.1/?/init.lua;" .. package.path

-- Allow require("ModuleName") for Data layer modules in domain subfolders.
local dataRoots = {
  "AltArmy_TBC/Data",
  "AltArmy_TBC/Data/DataStore",
  "AltArmy_TBC/Data/Characters",
  "AltArmy_TBC/Data/Gear",
  "AltArmy_TBC/Data/Search",
  "AltArmy_TBC/Data/Guild",
  "AltArmy_TBC/Data/Cooldowns",
  "AltArmy_TBC/Data/Integrations",
  "AltArmy_TBC/Data/Recipes",
  "AltArmy_TBC/Data/Auctions",
  "AltArmy_TBC/Data/Economy",
  "AltArmy_TBC/Data/Inventory",
  "AltArmy_TBC/Data/Link",
}
for _, root in ipairs(dataRoots) do
  package.path = package.path .. ";" .. root .. "/?.lua"
end

require("busted.runner")()
