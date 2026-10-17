--[[
  Unit tests for GuildTabData.lua (pure grouping / sorting / filtering / formatting for
  the Guild tab). No frames; the TabGuild UI wiring is exercised in-game.
  Run from project root: npm test
]]

describe("GuildTabData", function()
  local GTD

  -- Class-color-free formatter so format tests don't depend on RAID_CLASS_COLORS.
  local function plainFormatName(name)
    return name or "?"
  end

  local function profMap(list)
    local out = {}
    for _, p in ipairs(list or {}) do
      out[p.key] = { key = p.key, name = p.name or p.key, rank = p.rank or 0, spec = p.spec }
    end
    return out
  end

  local EM_DASH = "\226\128\148"

  local function member(opts)
    return {
      name = opts.name,
      realm = opts.realm or "R",
      classFile = opts.classFile,
      level = opts.level or 0,
      main = opts.main,
      displayName = opts.displayName,
      isMain = opts.isMain or false,
      mainDeclared = opts.mainDeclared,
      source = opts.source,
      receivedAt = opts.receivedAt,
      origin = opts.origin,
      noteText = opts.noteText,
      Professions = profMap(opts.profs),
    }
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("GuildTabData")
    GTD = AltArmy.GuildTabData
    assert.truthy(GTD)
  end)

  describe("GetPrimaryProfessions", function()
    it("returns crafting then gathering professions with rank, highest skill first within each group", function()
      local m = member({ name = "A", profs = {
        { key = "tailoring", name = "Tailoring", rank = 375 },
        { key = "alchemy", name = "Alchemy", rank = 300 },
        { key = "cooking", name = "Cooking", rank = 300 },
        { key = "firstAid", name = "First Aid", rank = 300 },
        { key = "mining", name = "Mining", rank = 300 },
      } })
      assert.are.same(
        {
          { key = "tailoring", name = "Tailoring", rank = 375 },
          { key = "alchemy", name = "Alchemy", rank = 300 },
          { key = "mining", name = "Mining", rank = 300 },
        },
        GTD.GetPrimaryProfessions(m))
    end)

    it("sorts gathering professions to the right of crafting even when gathering rank is higher", function()
      local m = member({ name = "A", profs = {
        { key = "mining", name = "Mining", rank = 375 },
        { key = "alchemy", name = "Alchemy", rank = 1 },
        { key = "herbalism", name = "Herbalism", rank = 300 },
      } })
      assert.are.same({
        { key = "alchemy", name = "Alchemy", rank = 1 },
        { key = "mining", name = "Mining", rank = 375 },
        { key = "herbalism", name = "Herbalism", rank = 300 },
      }, GTD.GetPrimaryProfessions(m))
    end)

    it("includes skinning and recognizes gathering keys stored as display names", function()
      local m = member({ name = "A", profs = {
        { key = "Skinning", name = "Skinning", rank = 300 },
        { key = "Herbalism", name = "Herbalism", rank = 150 },
      } })
      assert.are.same({
        { key = "skinning", name = "Skinning", rank = 300 },
        { key = "herbalism", name = "Herbalism", rank = 150 },
      }, GTD.GetPrimaryProfessions(m))
    end)

    it("breaks skill-rank ties alphabetically by name", function()
      local m = member({ name = "A", profs = {
        { key = "tailoring", name = "Tailoring", rank = 300 },
        { key = "alchemy", name = "Alchemy", rank = 300 },
        { key = "engineering", name = "Engineering", rank = 375 },
      } })
      assert.are.same({
        { key = "engineering", name = "Engineering", rank = 375 },
        { key = "alchemy", name = "Alchemy", rank = 300 },
        { key = "tailoring", name = "Tailoring", rank = 300 },
      }, GTD.GetPrimaryProfessions(m))
    end)

    it("excludes professions with zero rank", function()
      local m = member({ name = "A", profs = {
        { key = "tailoring", name = "Tailoring", rank = 0 },
        { key = "alchemy", name = "Alchemy", rank = 1 },
        { key = "mining", name = "Mining", rank = 0 },
      } })
      assert.are.same({ { key = "alchemy", name = "Alchemy", rank = 1 } }, GTD.GetPrimaryProfessions(m))
    end)

    it("excludes poisons and lockpicking", function()
      local m = member({ name = "A", profs = {
        { key = "poisons", name = "Poisons", rank = 300 },
        { key = "lockpicking", name = "Lockpicking", rank = 300 },
        { key = "Lockpicking", name = "Lockpicking", rank = 300 },
        { key = "alchemy", name = "Alchemy", rank = 300 },
        { key = "mining", name = "Mining", rank = 300 },
      } })
      assert.are.same({
        { key = "alchemy", name = "Alchemy", rank = 300 },
        { key = "mining", name = "Mining", rank = 300 },
      }, GTD.GetPrimaryProfessions(m))
    end)

    it("includes the specialization label when present", function()
      local m = member({ name = "A", profs = {
        { key = "alchemy", name = "Alchemy", rank = 375, spec = "Transmute" },
      } })
      assert.are.same({ { key = "alchemy", name = "Alchemy", rank = 375, spec = "Transmute" } },
        GTD.GetPrimaryProfessions(m))
    end)

    it("returns empty when there are no professions", function()
      assert.are.same({}, GTD.GetPrimaryProfessions(member({ name = "A" })))
    end)
  end)

  describe("GetCraftingProfessions", function()
    it("returns only crafting professions (no gathering)", function()
      local m = member({ name = "A", profs = {
        { key = "tailoring", name = "Tailoring", rank = 375 },
        { key = "mining", name = "Mining", rank = 375 },
        { key = "herbalism", name = "Herbalism", rank = 300 },
        { key = "cooking", name = "Cooking", rank = 300 },
      } })
      assert.are.same(
        { { key = "tailoring", name = "Tailoring", rank = 375 } },
        GTD.GetCraftingProfessions(m))
    end)

    it("keeps skinning in the gathering bucket when AltArmy.DataStore isn't loaded (TBC default)", function()
      local m = member({ name = "A", profs = {
        { key = "skinning", name = "Skinning", rank = 300 },
        { key = "tailoring", name = "Tailoring", rank = 300 },
      } })
      assert.is_nil(_G.AltArmy.DataStore)
      assert.are.same(
        { { key = "tailoring", name = "Tailoring", rank = 300 } },
        GTD.GetCraftingProfessions(m))
    end)

    it("promotes skinning to the crafting bucket when DS.ProfessionHasNoRecipeWindow says it has recipes (WoW Forever)", function()
      _G.AltArmy.DataStore = {
        ProfessionHasNoRecipeWindow = function(key)
          return key ~= "skinning"
        end,
      }
      local m = member({ name = "A", profs = {
        { key = "skinning", name = "Skinning", rank = 300 },
        { key = "tailoring", name = "Tailoring", rank = 300 },
      } })
      assert.are.same(
        { { key = "skinning", name = "Skinning", rank = 300 }, { key = "tailoring", name = "Tailoring", rank = 300 } },
        GTD.GetCraftingProfessions(m))
      _G.AltArmy.DataStore = nil
    end)
  end)

  describe("FormatProfessions", function()
    it("lists each profession with its skill level in gray parentheses", function()
      local m = member({ name = "A", profs = {
        { key = "tailoring", name = "Tailoring", rank = 375 },
        { key = "alchemy", name = "Alchemy", rank = 300 },
      } })
      assert.are.equal(
        "Tailoring |cff808080(375)|r, Alchemy |cff808080(300)|r",
        GTD.FormatProfessions(m))
    end)

    it("lists gathering professions after crafting professions", function()
      local m = member({ name = "A", profs = {
        { key = "mining", name = "Mining", rank = 375 },
        { key = "alchemy", name = "Alchemy", rank = 300 },
      } })
      assert.are.equal(
        "Alchemy |cff808080(300)|r, Mining |cff808080(375)|r",
        GTD.FormatProfessions(m))
    end)

    it("returns an empty string when there are no primary professions", function()
      assert.are.equal("", GTD.FormatProfessions(member({ name = "A" })))
    end)

    it("shows the specialization after an em dash (white) before the gray skill level", function()
      local m = member({ name = "A", profs = {
        { key = "tailoring", name = "Tailoring", rank = 375, spec = "Spellfire" },
        { key = "alchemy", name = "Alchemy", rank = 300 },
      } })
      assert.are.equal(
        "Tailoring " .. EM_DASH .. " Spellfire |cff808080(375)|r, Alchemy |cff808080(300)|r",
        GTD.FormatProfessions(m))
    end)

    it("highlights matching substrings in profession names and specializations", function()
      local m = member({ name = "A", profs = {
        { key = "alchemy", name = "Alchemy", rank = 375, spec = "Transmute" },
      } })
      assert.are.equal(
        "|cff00ff00Alch|r" .. "emy " .. EM_DASH .. " Transmute |cff808080(375)|r",
        GTD.FormatProfessions(m, "alch"))
    end)
  end)

  describe("GroupMembersByMain", function()
    it("groups alts under their main with preferred name and character count", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Mainman", main = "Mainman", isMain = true, displayName = "Bossman",
          classFile = "MAGE", level = 70 }),
        member({ name = "Altchar", main = "Mainman", level = 40, classFile = "WARRIOR" }),
      })
      assert.are.equal(1, #groups)
      assert.are.equal("Bossman", groups[1].preferredName)
      assert.are.equal("Mainman", groups[1].main)
      assert.are.equal(2, groups[1].characterCount)
      assert.are.equal("MAGE", groups[1].classFile)
    end)

    it("falls back to the main character name when no display name is set", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Solo", main = "Solo", isMain = true }),
      })
      assert.are.equal("Solo", groups[1].preferredName)
    end)

    it("uses the character's own name as the group key when no main is set", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Loner", level = 12 }),
      })
      assert.are.equal(1, #groups)
      assert.are.equal("Loner", groups[1].preferredName)
    end)

    it("sorts groups alphabetically by preferred name, case-insensitively", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "zed", main = "zed", isMain = true, displayName = "zed" }),
        member({ name = "Alice", main = "Alice", isMain = true, displayName = "alice" }),
        member({ name = "Bob", main = "Bob", isMain = true, displayName = "Bob" }),
      })
      assert.are.equal("alice", groups[1].preferredName)
      assert.are.equal("Bob", groups[2].preferredName)
      assert.are.equal("zed", groups[3].preferredName)
    end)

    it("sorts members within a group by level descending, then name ascending", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Mid", main = "Main", level = 40 }),
        member({ name = "Main", main = "Main", isMain = true, level = 70 }),
        member({ name = "Aaa", main = "Main", level = 40 }),
        member({ name = "Low", main = "Main", level = 10 }),
      })
      local names = {}
      for _, m in ipairs(groups[1].members) do names[#names + 1] = m.name end
      assert.are.same({ "Main", "Aaa", "Mid", "Low" }, names)
    end)
  end)

  describe("old received data", function()
    local DAY = 60 * 60 * 24
    local NOW = 1700000000

    it("exposes a 30-day UI warning age", function()
      assert.are.equal(30 * DAY, GTD.OLD_DATA_AGE_SEC)
    end)

    it("IsMemberDataOld is false for local account members", function()
      local m = member({ name = "Me", source = "local", receivedAt = NOW - 30 * DAY })
      assert.is_false(GTD.IsMemberDataOld(m, NOW))
    end)

    it("IsMemberDataOld is false when receivedAt is missing", function()
      local m = member({ name = "Peer", source = "Peer" })
      assert.is_false(GTD.IsMemberDataOld(m, NOW))
    end)

    it("IsMemberDataOld is false when data is fresher than the warning age", function()
      local m = member({
        name = "Peer", source = "Peer", receivedAt = NOW - (GTD.OLD_DATA_AGE_SEC - DAY),
      })
      assert.is_false(GTD.IsMemberDataOld(m, NOW))
    end)

    it("IsMemberDataOld is true when data is at or past the warning age", function()
      local m = member({
        name = "Peer", source = "Peer", receivedAt = NOW - GTD.OLD_DATA_AGE_SEC,
      })
      assert.is_true(GTD.IsMemberDataOld(m, NOW))
      assert.is_true(GTD.IsMemberDataOld(
        member({ name = "Peer", source = "Peer", receivedAt = NOW - (40 * DAY) }),
        NOW))
    end)

    it("GroupHasOldData is true when any received member is old", function()
      local groups = GTD.GroupMembersByMain({
        member({
          name = "Main", main = "Main", isMain = true, source = "Main",
          receivedAt = NOW - (40 * DAY),
        }),
        member({
          name = "Alt", main = "Main", source = "Main",
          receivedAt = NOW - (40 * DAY),
        }),
      })
      assert.is_true(GTD.GroupHasOldData(groups[1], NOW))
    end)

    it("GroupHasOldData is false for fresh received groups and local-only groups", function()
      local fresh = GTD.GroupMembersByMain({
        member({
          name = "Fresh", main = "Fresh", isMain = true, source = "Fresh",
          receivedAt = NOW - DAY,
        }),
      })
      assert.is_false(GTD.GroupHasOldData(fresh[1], NOW))

      local localOnly = GTD.GroupMembersByMain({
        member({ name = "Me", main = "Me", isMain = true, source = "local" }),
      })
      assert.is_false(GTD.GroupHasOldData(localOnly[1], NOW))
    end)

    it("GetOldDataTooltipText includes the data age in days", function()
      local text = GTD.GetOldDataTooltipText(42)
      assert.are.equal(
        "This data is 42 days old. The guildmate has not shared an update with you recently.",
        text)
    end)

    it("GetGroupOldestReceivedAt uses the oldest non-local receivedAt", function()
      local groups = GTD.GroupMembersByMain({
        member({
          name = "Main", main = "Main", isMain = true, source = "Main",
          receivedAt = NOW - (40 * DAY),
        }),
        member({
          name = "Alt", main = "Main", source = "Main",
          receivedAt = NOW - (90 * DAY),
        }),
        member({
          name = "Me", main = "Main", source = "local",
          receivedAt = NOW - (200 * DAY),
        }),
      })
      assert.are.equal(NOW - (90 * DAY), GTD.GetGroupOldestReceivedAt(groups[1]))
    end)

    it("GetDataAgeDays floors elapsed whole days", function()
      assert.are.equal(40, GTD.GetDataAgeDays(NOW - (40 * DAY), NOW))
      assert.are.equal(40, GTD.GetDataAgeDays(NOW - (40 * DAY) - 3600, NOW))
    end)

    it("GetDaysUntilAutoDelete ceils remaining days until the prune age", function()
      local maxAge = 180 * DAY
      assert.are.equal(140, GTD.GetDaysUntilAutoDelete(NOW - (40 * DAY), NOW, maxAge))
      assert.are.equal(1, GTD.GetDaysUntilAutoDelete(NOW - maxAge + 1, NOW, maxAge))
      assert.are.equal(0, GTD.GetDaysUntilAutoDelete(NOW - maxAge, NOW, maxAge))
    end)

    it("GetOldDataAutoDeleteTooltipText includes remaining days", function()
      assert.are.equal(
        "This data will be deleted in 140 days, unless new data is received by then.",
        GTD.GetOldDataAutoDeleteTooltipText(140))
    end)
  end)

  describe("manual grouping indicators", function()
    it("IsManualMember is true only for source=manual", function()
      assert.is_true(GTD.IsManualMember(member({ name = "A", source = "manual" })))
      assert.is_false(GTD.IsManualMember(member({ name = "A", source = "local" })))
      assert.is_false(GTD.IsManualMember(member({ name = "A", source = "Peer" })))
      assert.is_false(GTD.IsManualMember(nil))
    end)

    it("GroupHasManualData is true when any member is manual", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Bob", main = "Bob", isMain = true, source = "manual" }),
        member({ name = "Bobsalt", main = "Bob", source = "manual" }),
      })
      assert.is_true(GTD.GroupHasManualData(groups[1]))
    end)

    it("GroupHasManualData is false for received or local-only groups", function()
      local received = GTD.GroupMembersByMain({
        member({ name = "Peer", main = "Peer", isMain = true, source = "Peer" }),
      })
      assert.is_false(GTD.GroupHasManualData(received[1]))
      local localOnly = GTD.GroupMembersByMain({
        member({ name = "Me", main = "Me", isMain = true, source = "local" }),
      })
      assert.is_false(GTD.GroupHasManualData(localOnly[1]))
    end)

    it("GroupIsEntirelyManual is true only when every member is manual", function()
      local allManual = GTD.GroupMembersByMain({
        member({ name = "Bob", main = "Bob", isMain = true, source = "manual" }),
        member({ name = "Bobsalt", main = "Bob", source = "manual" }),
      })
      assert.is_true(GTD.GroupIsEntirelyManual(allManual[1]))
    end)

    it("GroupIsEntirelyManual is false when any member has shared data", function()
      local mixed = GTD.GroupMembersByMain({
        member({ name = "Alice", main = "Alice", isMain = true, source = "Peer" }),
        member({ name = "NoteAlt", main = "Alice", source = "manual" }),
      })
      assert.is_true(GTD.GroupHasManualData(mixed[1]))
      assert.is_false(GTD.GroupIsEntirelyManual(mixed[1]))
    end)

    it("GroupIsEntirelyManual is false for empty or nil groups", function()
      assert.is_false(GTD.GroupIsEntirelyManual(nil))
      assert.is_false(GTD.GroupIsEntirelyManual({ members = {} }))
    end)

    it("GetManualDataTooltipText warns that grouping may be inaccurate", function()
      local text = GTD.GetManualDataTooltipText(member({ name = "A", source = "manual" }))
      assert.truthy(text:find("does not use Alt Army", 1, true))
      assert.truthy(text:find("manually", 1, true) or text:find("manual", 1, true))
      assert.truthy(text:find("inaccurate", 1, true) or text:find("unreliable", 1, true)
        or text:find("may be", 1, true))
    end)

    it("GetManualDataTooltipText does not include note provenance", function()
      local text = GTD.GetManualDataTooltipText(member({
        name = "A", source = "manual", origin = "note", noteText = "bob alt",
      }))
      assert.is_nil(text:find("bob alt", 1, true))
      assert.is_nil(text:find("From guild note", 1, true))
    end)

    it("GetManualCharacterTooltipText warns the character may be inaccurate", function()
      assert.are.equal(
        "This character was entered manually and may be inaccurate",
        GTD.GetManualCharacterTooltipText(member({ name = "A", source = "manual" })))
    end)

    it("GetManualGroupCreateDescription explains main/alt grouping for non-addon guildmates", function()
      local text = GTD.GetManualGroupCreateDescription()
      assert.truthy(text:find("main", 1, true) or text:find("alt", 1, true))
      assert.truthy(text:find("Alt Army", 1, true) or text:find("addon", 1, true))
      assert.is_nil(text:find("never shared", 1, true))
      assert.is_nil(text:find("this computer", 1, true))
    end)

    it("FormatCharacterName does not embed M for manual members", function()
      local text = GTD.FormatCharacterName(
        member({ name = "Bobsalt", classFile = "MAGE", level = 60, source = "manual" }),
        plainFormatName)
      assert.are.equal("Bobsalt |cff808080(level 60)|r", text)
      assert.is_nil(text:find("(manual)", 1, true))
    end)

    it("FormatCharacterNamePart is name-only for list layout with a separate M icon", function()
      local m = member({ name = "Bobsalt", classFile = "MAGE", level = 60, source = "manual" })
      assert.are.equal("Bobsalt", GTD.FormatCharacterNamePart(m, plainFormatName))
      assert.are.equal("Mind|cff00ff00frell|r",
        GTD.FormatCharacterNamePart(
          member({ name = "Mindfrell", classFile = "MAGE", level = 70 }),
          plainFormatName, "frell"))
    end)

    it("FormatProfessions returns blank for manual members", function()
      assert.are.equal("", GTD.FormatProfessions(member({ name = "A", source = "manual" })))
    end)
  end)

  describe("manual group editing helpers", function()
    it("CollectOccupiedNames returns a lowercase set of member names", function()
      local set = GTD.CollectOccupiedNames({
        member({ name = "Alice" }),
        member({ name = "Bob-Realm" }),
      })
      assert.is_true(set.alice)
      assert.is_true(set.bob)
      assert.is_nil(set.carol)
    end)

    it("FilterRosterNamesForAdd matches query and sorts occupied names to the bottom", function()
      local occupied = { bob = "already in a group", carol = true }
      local matches = GTD.FilterRosterNamesForAdd(
        { "Alice", "Bob", "Bobby", "Carol", "Dave" },
        "bo",
        occupied)
      assert.are.same({ "Bobby", "Bob" }, matches)
    end)

    it("FilterRosterNamesForAdd also matches guild notes when rosterInfo is provided", function()
      local rosterInfo = {
        alice = { name = "Alice", note = "main bank char" },
        bob = { name = "Bob", note = "Alice alt" },
        carol = { name = "Carol", note = "" },
      }
      local matches = GTD.FilterRosterNamesForAdd(
        { "Alice", "Bob", "Carol", "Dave" },
        "bank",
        {},
        { rosterInfo = rosterInfo })
      assert.are.same({ "Alice" }, matches)
    end)

    it("FilterRosterNamesForAdd matches name or note and keeps name-only alphabetical order", function()
      local rosterInfo = {
        alice = { name = "Alice", note = "bank mule" },
        banky = { name = "Banky", note = "storage" },
        carol = { name = "Carol", note = "nope" },
      }
      local matches = GTD.FilterRosterNamesForAdd(
        { "Carol", "Alice", "Banky" },
        "bank",
        {},
        { rosterInfo = rosterInfo })
      assert.are.same({ "Alice", "Banky" }, matches)
    end)

    it("FilterRosterNamesForAdd returns selectable first then occupied when query is empty", function()
      local matches = GTD.FilterRosterNamesForAdd(
        { "Carol", "Alice", "Bob", "Zed" },
        "",
        { bob = "already in a group", zed = true })
      assert.are.same({ "Alice", "Carol", "Bob", "Zed" }, matches)
    end)

    it("FilterRosterNamesForAdd respects maxResults across selectable and occupied", function()
      local names = {}
      for i = 1, 20 do names[i] = "Name" .. i end
      local matches = GTD.FilterRosterNamesForAdd(names, "name", {}, { maxResults = 5 })
      assert.are.equal(5, #matches)
    end)

    it("RosterAddDisabledReason returns the occupied entry (string or table)", function()
      assert.are.equal(
        "already in a group",
        GTD.RosterAddDisabledReason({ bob = "already in a group" }, "Bob"))
      assert.is_true(GTD.RosterAddDisabledReason({ bob = true }, "Bob"))
      assert.are.equal(
        "your character",
        GTD.RosterAddDisabledReason({ bob = "your character" }, "Bob"))
      local info = { groupName = "Alice", classFile = "MAGE" }
      assert.are.equal(info, GTD.RosterAddDisabledReason({ bob = info }, "Bob"))
      assert.is_nil(GTD.RosterAddDisabledReason({ bob = true }, "Alice"))
      assert.is_nil(GTD.RosterAddDisabledReason(nil, "Bob"))
    end)

    it("BuildOccupiedGroupReasons maps members to group display name and main class", function()
      local occupied = GTD.BuildOccupiedGroupReasons({
        member({ name = "Alice", main = "Alice", isMain = true, displayName = "AliceMain",
          classFile = "MAGE" }),
        member({ name = "Alicia", main = "Alice", classFile = "WARRIOR" }),
        member({ name = "Bob", main = "Bob", isMain = true, displayName = "Bob",
          classFile = "WARRIOR" }),
      })
      assert.are.equal("AliceMain", occupied.alice.groupName)
      assert.are.equal("MAGE", occupied.alice.classFile)
      assert.are.equal("AliceMain", occupied.alicia.groupName)
      assert.are.equal("MAGE", occupied.alicia.classFile)
      assert.are.equal("Bob", occupied.bob.groupName)
      assert.are.equal("WARRIOR", occupied.bob.classFile)
    end)

    it("BuildOccupiedGroupReasons prefers override names via getOverride", function()
      local occupied = GTD.BuildOccupiedGroupReasons({
        member({ name = "Alice", main = "Alice", isMain = true, displayName = "Alice",
          classFile = "MAGE" }),
      }, function(group)
        if group.main == "Alice" then return "Bank Crew" end
      end)
      assert.are.equal("Bank Crew", occupied.alice.groupName)
    end)

    it("FormatRosterAddDisabledReason colors Already in group gray with class-colored name", function()
      local text = GTD.FormatRosterAddDisabledReason({
        groupName = "Alice",
        classFile = "MAGE",
      }, function(name, classFile)
        return "[" .. classFile .. "]" .. name
      end)
      assert.are.equal("|cff808080Already in group |r[MAGE]Alice", text)
    end)

    it("FormatRosterAddDisabledReason colors plain string reasons in gray and capitalizes Your character", function()
      assert.are.equal(
        "|cff808080Your character|r",
        GTD.FormatRosterAddDisabledReason("Your character"))
      assert.are.equal(
        "|cff808080Your character|r",
        GTD.FormatRosterAddDisabledReason("your character"))
      assert.are.equal(
        "|cff808080Already in a group|r",
        GTD.FormatRosterAddDisabledReason(true))
    end)

    it("GetManualAlts returns manual members that are not the main", function()
      local group = {
        main = "Bob",
        members = {
          member({ name = "Bob", main = "Bob", isMain = true, source = "manual" }),
          member({ name = "Bobsalt", main = "Bob", source = "manual" }),
          member({ name = "AddonAlt", main = "Bob", source = "Peer" }),
        },
      }
      local alts = GTD.GetManualAlts(group)
      assert.are.equal(1, #alts)
      assert.are.equal("Bobsalt", alts[1].name)
    end)

    it("RosterDisplayNames extracts sorted display names from a roster info map", function()
      local names = GTD.RosterDisplayNames({
        alice = { name = "Alice", classFile = "MAGE", level = 70 },
        bob = { name = "Bob", classFile = "WARRIOR", level = 60 },
      })
      assert.are.same({ "Alice", "Bob" }, names)
    end)

    it("ResolveRosterName returns the roster display name for an exact match", function()
      local rosterInfo = {
        alice = { name = "Alice", classFile = "MAGE", level = 70 },
        bob = { name = "Bob", classFile = "WARRIOR", level = 60 },
      }
      assert.are.equal("Alice", GTD.ResolveRosterName("Alice", rosterInfo))
      assert.are.equal("Bob", GTD.ResolveRosterName("Bob", rosterInfo))
    end)

    it("ResolveRosterName matches case-insensitively", function()
      local rosterInfo = {
        bobsalt = { name = "Bobsalt", classFile = "WARRIOR", level = 60 },
      }
      assert.are.equal("Bobsalt", GTD.ResolveRosterName("bobsalt", rosterInfo))
      assert.are.equal("Bobsalt", GTD.ResolveRosterName("BOBSALT", rosterInfo))
    end)

    it("ResolveRosterName returns nil for unknown or empty names", function()
      local rosterInfo = {
        alice = { name = "Alice" },
      }
      assert.is_nil(GTD.ResolveRosterName("Nobody", rosterInfo))
      assert.is_nil(GTD.ResolveRosterName("", rosterInfo))
      assert.is_nil(GTD.ResolveRosterName(nil, rosterInfo))
      assert.is_nil(GTD.ResolveRosterName("Alice", nil))
      assert.is_nil(GTD.ResolveRosterName("Alice", {}))
    end)

    it("ResolveRosterName strips realm suffix before lookup", function()
      local rosterInfo = {
        alice = { name = "Alice" },
      }
      assert.are.equal("Alice", GTD.ResolveRosterName("Alice-EmeraldDream", rosterInfo))
    end)
  end)

  describe("manual vs addon disagreements", function()
    it("FindManualAddonDisagreements lists shadowed mappings that disagree", function()
      local GMG = {
        GetMapping = function(name, realm)
          if name == "Alt" and realm == "R" then
            return { main = "ManualMain", origin = "user" }
          end
          return nil
        end,
      }
      local group = {
        main = "AddonMain",
        members = {
          member({
            name = "Alt", realm = "R", main = "AddonMain", source = "Peer",
          }),
          member({
            name = "AddonMain", realm = "R", main = "AddonMain", isMain = true, source = "Peer",
          }),
        },
      }
      local conflicts = GTD.FindManualAddonDisagreements(group, GMG)
      assert.are.equal(1, #conflicts)
      assert.are.equal("Alt", conflicts[1].name)
      assert.are.equal("ManualMain", conflicts[1].manualMain)
      assert.are.equal("AddonMain", conflicts[1].addonMain)
      assert.are.equal("user", conflicts[1].origin)
    end)

    it("FindManualAddonDisagreements ignores agreeing or unmapped members", function()
      local GMG = {
        GetMapping = function(name)
          if name == "Alt" then return { main = "AddonMain" } end
          return nil
        end,
      }
      local group = {
        main = "AddonMain",
        members = {
          member({ name = "Alt", realm = "R", main = "AddonMain", source = "Peer" }),
        },
      }
      assert.are.equal(0, #GTD.FindManualAddonDisagreements(group, GMG))
    end)

    it("FormatManualDisagreementText explains the conflict", function()
      local text = GTD.FormatManualDisagreementText({
        name = "Alt", manualMain = "Alice", addonMain = "Bob",
      })
      assert.truthy(text:find("Alt", 1, true))
      assert.truthy(text:find("Alice", 1, true))
      assert.truthy(text:find("Bob", 1, true))
    end)
  end)

  describe("BuildGroupEditProposal / DiffGroupEditProposal", function()
    local function gmgStub(mappings)
      return {
        GetMapping = function(name, realm)
          for _, m in ipairs(mappings or {}) do
            if m.name == name and (not realm or m.realm == realm or not m.realm) then
              return m.entry
            end
          end
          return nil
        end,
      }
    end

    it("BuildGroupEditProposal returns nil for a nil group", function()
      assert.is_nil(GTD.BuildGroupEditProposal(nil))
    end)

    it("BuildGroupEditProposal stages main, members, pin, and override", function()
      local group = {
        main = "Bob",
        pinned = true,
        overrideName = "Boss",
        members = {
          member({ name = "Bob", main = "Bob", isMain = true, source = "Peer" }),
          member({ name = "Bobsalt", main = "Bob", source = "manual", origin = "user" }),
          member({ name = "AddonAlt", main = "Bob", source = "Peer" }),
        },
      }
      local proposal = GTD.BuildGroupEditProposal(group, gmgStub({
        { name = "Bobsalt", realm = "R", entry = { main = "Bob", origin = "user" } },
      }))
      assert.truthy(proposal)
      assert.is_true(proposal.edit)
      assert.are.equal("Bob", proposal.main)
      assert.is_true(proposal.pinned)
      assert.are.equal("Boss", proposal.overrideName)
      assert.are.same({ "Bob", "Bobsalt", "AddonAlt" }, proposal.order)
      assert.are.equal(2, #proposal.members)
      local byName = {}
      for _, m in ipairs(proposal.members) do byName[m.name] = m end
      assert.is_true(byName.Bobsalt.removable)
      assert.are.equal("manual", byName.Bobsalt.reasonKind)
      assert.is_false(byName.AddonAlt.removable)
      assert.are.equal("shared", byName.AddonAlt.reasonKind)
    end)

    it("BuildGroupEditProposal marks note-origin manual members as note reason", function()
      local group = {
        main = "Bob",
        members = {
          member({ name = "Bob", main = "Bob", isMain = true, source = "manual" }),
          member({ name = "NoteAlt", main = "Bob", source = "manual" }),
        },
      }
      local proposal = GTD.BuildGroupEditProposal(group, gmgStub({
        { name = "NoteAlt", realm = "R", entry = { main = "Bob", origin = "note" } },
      }))
      local byName = {}
      for _, m in ipairs(proposal.members) do byName[m.name] = m end
      assert.are.equal("note", byName.NoteAlt.reasonKind)
      assert.is_true(byName.NoteAlt.removable)
    end)

    it("BuildGroupEditProposal marks conflicting shadowed mappings as conflict and removable", function()
      local group = {
        main = "AddonMain",
        members = {
          member({
            name = "AddonMain", realm = "R", main = "AddonMain", isMain = true, source = "Peer",
          }),
          member({
            name = "Alt", realm = "R", main = "AddonMain", source = "Peer",
          }),
        },
      }
      local proposal = GTD.BuildGroupEditProposal(group, gmgStub({
        { name = "Alt", realm = "R", entry = { main = "ManualMain", origin = "user" } },
      }))
      local byName = {}
      for _, m in ipairs(proposal.members) do byName[m.name] = m end
      assert.are.equal("conflict", byName.Alt.reasonKind)
      assert.is_true(byName.Alt.removable)
      assert.are.equal("ManualMain", byName.Alt.conflictManualMain)
    end)

    it("BuildGroupEditProposal marks the main row as non-removable shared/main", function()
      local group = {
        main = "Bob",
        members = {
          member({ name = "Bob", main = "Bob", isMain = true, source = "Peer" }),
        },
      }
      local proposal = GTD.BuildGroupEditProposal(group)
      assert.are.equal(0, #proposal.members)
      assert.are.same({ "Bob" }, proposal.order)
      assert.are.equal("shared", proposal.mainReasonKind)
      assert.is_false(proposal.mainDeclared)
    end)

    it("BuildGroupEditProposal classifies a fully manual main as manually added, not shared", function()
      local group = {
        main = "Bob",
        members = {
          member({ name = "Bob", main = "Bob", isMain = true, source = "manual", origin = "user" }),
          member({ name = "Bobsalt", main = "Bob", source = "manual", origin = "user" }),
        },
      }
      local proposal = GTD.BuildGroupEditProposal(group)
      assert.are.equal("manual", proposal.mainReasonKind)
      assert.is_false(proposal.mainDeclared)
    end)

    it("BuildGroupEditProposal classifies a note-origin grouping main as referred, not shared", function()
      local group = {
        main = "Bob",
        members = {
          member({ name = "Bob", main = "Bob", isMain = true, source = "manual", origin = "note" }),
          member({ name = "NoteAlt", main = "Bob", source = "manual", origin = "note" }),
        },
      }
      local proposal = GTD.BuildGroupEditProposal(group)
      assert.are.equal("main", proposal.mainReasonKind)
      assert.is_false(proposal.mainDeclared)
    end)

    it("BuildGroupEditProposal sets mainDeclared only for an explicit Alt Army main", function()
      local group = {
        main = "Alice",
        members = {
          member({
            name = "Alice", main = "Alice", isMain = true, source = "Peer", mainDeclared = true,
          }),
          member({ name = "Alicesalt", main = "Alice", source = "Peer" }),
        },
      }
      local proposal = GTD.BuildGroupEditProposal(group)
      assert.are.equal("shared", proposal.mainReasonKind)
      assert.is_true(proposal.mainDeclared)
    end)

    it("BuildGroupEditProposal resolves a missing main origin from the manual mapping", function()
      local group = {
        main = "Bob",
        members = {
          member({ name = "Bob", main = "Bob", isMain = true, source = "manual" }),
          member({ name = "Bobsalt", main = "Bob", source = "manual" }),
        },
      }
      local proposal = GTD.BuildGroupEditProposal(group, gmgStub({
        { name = "Bob", realm = "R", entry = { main = "Bob", origin = "note" } },
      }))
      assert.are.equal("main", proposal.mainReasonKind)
      assert.is_false(proposal.mainDeclared)
    end)

    it("DiffGroupEditProposal reports no changes when staged equals original", function()
      local group = {
        main = "Bob",
        pinned = false,
        overrideName = nil,
        members = {
          member({ name = "Bob", main = "Bob", isMain = true, source = "manual" }),
          member({ name = "Bobsalt", main = "Bob", source = "manual" }),
        },
      }
      local proposal = GTD.BuildGroupEditProposal(group)
      local diff = GTD.DiffGroupEditProposal(proposal, group)
      assert.are.same({}, diff.adds)
      assert.are.same({}, diff.removes)
      assert.is_nil(diff.pinned)
      assert.is_nil(diff.overrideName)
    end)

    it("DiffGroupEditProposal reports added and removed manual members", function()
      local group = {
        main = "Bob",
        members = {
          member({ name = "Bob", main = "Bob", isMain = true, source = "manual" }),
          member({ name = "OldAlt", main = "Bob", source = "manual" }),
        },
      }
      local proposal = GTD.BuildGroupEditProposal(group)
      -- Remove OldAlt, add NewAlt.
      proposal.members = { { name = "NewAlt", removable = true, reasonKind = "manual" } }
      proposal.order = { "Bob", "NewAlt" }
      local diff = GTD.DiffGroupEditProposal(proposal, group)
      assert.are.same({ "NewAlt" }, diff.adds)
      assert.are.same({ "OldAlt" }, diff.removes)
    end)

    it("DiffGroupEditProposal reports pin and override changes", function()
      local group = {
        main = "Bob",
        pinned = false,
        overrideName = nil,
        members = {
          member({ name = "Bob", main = "Bob", isMain = true, source = "Peer" }),
        },
      }
      local proposal = GTD.BuildGroupEditProposal(group)
      proposal.pinned = true
      proposal.overrideName = "Boss"
      local diff = GTD.DiffGroupEditProposal(proposal, group)
      assert.is_true(diff.pinned)
      assert.are.equal("Boss", diff.overrideName)
    end)

    it("DiffGroupEditProposal reports clearing an override name", function()
      local group = {
        main = "Bob",
        overrideName = "Boss",
        members = {
          member({ name = "Bob", main = "Bob", isMain = true, source = "Peer" }),
        },
      }
      local proposal = GTD.BuildGroupEditProposal(group)
      proposal.overrideName = nil
      local diff = GTD.DiffGroupEditProposal(proposal, group)
      assert.are.equal("", diff.overrideName)
    end)

    it("NotesWizardInclusionReasonLabel returns Conflict for conflict kind", function()
      assert.are.equal("Conflicts with addon", GTD.NotesWizardInclusionReasonLabel("conflict"))
    end)

    it("GroupEditProposalHasChanges is false when staged equals original", function()
      local group = {
        main = "Bob",
        pinned = true,
        overrideName = "Boss",
        members = {
          member({ name = "Bob", main = "Bob", isMain = true, source = "manual" }),
          member({ name = "Bobsalt", main = "Bob", source = "manual" }),
        },
      }
      local proposal = GTD.BuildGroupEditProposal(group)
      assert.is_false(GTD.GroupEditProposalHasChanges(proposal, group))
    end)

    it("GroupEditProposalHasChanges is true for pin, override, or member edits", function()
      local group = {
        main = "Bob",
        pinned = false,
        members = {
          member({ name = "Bob", main = "Bob", isMain = true, source = "manual" }),
          member({ name = "OldAlt", main = "Bob", source = "manual" }),
        },
      }
      local proposal = GTD.BuildGroupEditProposal(group)
      proposal.pinned = true
      assert.is_true(GTD.GroupEditProposalHasChanges(proposal, group))
      proposal = GTD.BuildGroupEditProposal(group)
      proposal.overrideName = "Boss"
      assert.is_true(GTD.GroupEditProposalHasChanges(proposal, group))
      proposal = GTD.BuildGroupEditProposal(group)
      proposal.members = {}
      proposal.order = { "Bob" }
      assert.is_true(GTD.GroupEditProposalHasChanges(proposal, group))
    end)
  end)

  describe("ListedGroups", function()
    local function linked(opts)
      local m = member(opts)
      m.linkOnly = true
      m.autoGroup = opts.autoGroup
      return m
    end

    it("leaves out groups made only of characters read by link that nothing groups", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Bossman", main = "Bossman", isMain = true }),
        member({ name = "Sidekick", main = "Bossman" }),
        linked({ name = "Linked", main = "Linked", isMain = true, autoGroup = true }),
        linked({ name = "Noted", main = "Bossman" }),
      })
      local out = GTD.ListedGroups(groups)
      assert.are.equal(1, #out)
      assert.are.equal("Bossman", out[1].main)
      assert.are.equal(3, #out[1].members)
    end)

    it("keeps a group with any member that isn't an auto group", function()
      local groups = GTD.GroupMembersByMain({
        linked({ name = "Linked", main = "Linked", isMain = true, autoGroup = true }),
        member({ name = "Alt", main = "Linked" }),
      })
      assert.are.equal(1, #GTD.ListedGroups(groups))
    end)
  end)

  describe("FilterGroups", function()
    local groups

    before_each(function()
      groups = GTD.GroupMembersByMain({
        member({ name = "Bossman", main = "Bossman", isMain = true, displayName = "TopDog" }),
        member({ name = "Sidekick", main = "Bossman" }),
        member({ name = "Loner", main = "Loner", isMain = true, displayName = "Loner" }),
      })
    end)

    it("returns all groups when the query is empty", function()
      assert.are.equal(2, #GTD.FilterGroups(groups, ""))
      assert.are.equal(2, #GTD.FilterGroups(groups, nil))
      assert.are.equal(2, #GTD.FilterGroups(groups, "  "))
    end)

    it("matches on the preferred name and includes all characters in the group", function()
      local out = GTD.FilterGroups(groups, "topdog")
      assert.are.equal(1, #out)
      assert.are.equal("TopDog", out[1].preferredName)
      assert.are.equal(2, #out[1].members)
      assert.are.equal(2, out[1].characterCount)
    end)

    it("matches on overrideName and includes all characters in the group", function()
      local target
      for _, g in ipairs(groups) do
        if g.main == "Bossman" then
          target = g
          break
        end
      end
      assert.truthy(target)
      target.overrideName = "Nickname"
      local out = GTD.FilterGroups(groups, "nick")
      assert.are.equal(1, #out)
      assert.are.equal("Bossman", out[1].main)
      assert.are.equal(2, #out[1].members)
      assert.are.equal("Nickname", out[1].overrideName)
    end)

    it("matches on the main character name and includes all characters in the group", function()
      local out = GTD.FilterGroups(groups, "bossman")
      assert.are.equal(1, #out)
      assert.are.equal("TopDog", out[1].preferredName)
      assert.are.equal(2, #out[1].members)
      assert.are.equal(2, out[1].characterCount)
    end)

    it("matches on an alt character name and omits non-matching characters", function()
      local out = GTD.FilterGroups(groups, "sidekick")
      assert.are.equal(1, #out)
      assert.are.equal("TopDog", out[1].preferredName)
      assert.are.equal(1, #out[1].members)
      assert.are.equal("Sidekick", out[1].members[1].name)
    end)

    it("returns nothing when no group matches", function()
      assert.are.equal(0, #GTD.FilterGroups(groups, "nobody"))
    end)

    it("updates characterCount to the number of visible members", function()
      local out = GTD.FilterGroups(groups, "sidekick")
      assert.are.equal(1, out[1].characterCount)
    end)

    it("matches on a character profession name and omits non-matching characters", function()
      local profGroups = GTD.GroupMembersByMain({
        member({ name = "Bossman", main = "Bossman", isMain = true, displayName = "TopDog", profs = {
          { key = "alchemy", name = "Alchemy", rank = 375, spec = "Transmute" },
        } }),
        member({ name = "Sidekick", main = "Bossman" }),
      })
      local out = GTD.FilterGroups(profGroups, "alch")
      assert.are.equal(1, #out)
      assert.are.equal(1, #out[1].members)
      assert.are.equal("Bossman", out[1].members[1].name)
    end)

    it("matches on a profession specialization", function()
      local profGroups = GTD.GroupMembersByMain({
        member({ name = "Crafter", main = "Crafter", isMain = true, profs = {
          { key = "alchemy", name = "Alchemy", rank = 375, spec = "Transmute" },
        } }),
      })
      local out = GTD.FilterGroups(profGroups, "trans")
      assert.are.equal(1, #out)
      assert.are.equal("Crafter", out[1].members[1].name)
    end)
  end)

  describe("FormatTextWithSearchHighlight", function()
    local GREEN = "|cff00ff00"

    it("returns plain text when the query is empty", function()
      assert.are.equal("Mindfrell", GTD.FormatTextWithSearchHighlight("Mindfrell", "MAGE", ""))
    end)

    it("highlights the matching substring in bright green with class-colored prefix", function()
      local function fakeFormat(text)
        return "<MAGE>" .. text
      end
      local out = GTD.FormatTextWithSearchHighlight("Mindfrell", "MAGE", "frell", fakeFormat)
      assert.are.equal("<MAGE>Mind" .. GREEN .. "frell|r", out)
    end)

    it("is case-insensitive while preserving original casing", function()
      local out = GTD.FormatTextWithSearchHighlight("Mindfrell", nil, "FRELL")
      assert.are.equal("Mind" .. GREEN .. "frell|r", out)
    end)

    it("highlights every non-overlapping match", function()
      local out = GTD.FormatTextWithSearchHighlight("banana", nil, "an")
      assert.are.equal("b" .. GREEN .. "an|r" .. GREEN .. "an|r" .. "a", out)
    end)
  end)

  describe("FormatTruncatedTextWithSearchHighlight", function()
    local GREEN = "|cff00ff00"
    local FULL = "Durotar Supply and Logistics"

    it("highlights the visible part of a match that continues past the ellipsis", function()
      local out = GTD.FormatTruncatedTextWithSearchHighlight(FULL, "Durotar Supply and...", "and logistics")
      assert.are.equal("Durotar Supply " .. GREEN .. "and|r...", out)
    end)

    it("highlights fully visible matches normally", function()
      local out = GTD.FormatTruncatedTextWithSearchHighlight(FULL, "Durotar Supply and...", "supply")
      assert.are.equal("Durotar " .. GREEN .. "Supply|r and...", out)
    end)

    it("leaves text plain when the only match is hidden", function()
      local out = GTD.FormatTruncatedTextWithSearchHighlight(FULL, "Durotar Supply and...", "logistics")
      assert.are.equal("Durotar Supply and...", out)
    end)

    it("behaves like FormatTextWithSearchHighlight when not truncated", function()
      local out = GTD.FormatTruncatedTextWithSearchHighlight("Sha'tar", "Sha'tar", "tar")
      assert.are.equal("Sha'" .. GREEN .. "tar|r", out)
    end)

    it("returns shown text unchanged for an empty query", function()
      assert.are.equal("Durotar Supply and...",
        GTD.FormatTruncatedTextWithSearchHighlight(FULL, "Durotar Supply and...", ""))
    end)
  end)

  describe("FormatMainRowName", function()
    it("returns the preferred name", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Main", main = "Main", isMain = true, displayName = "Chief" }),
      })
      assert.are.equal("Chief", GTD.FormatMainRowName(groups[1]))
    end)

    it("highlights the matching portion of the preferred name", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Main", main = "Main", isMain = true, displayName = "Mindfrell", classFile = "MAGE" }),
      })
      assert.are.equal(
        "Mind|cff00ff00frell|r",
        GTD.FormatMainRowName(groups[1], plainFormatName, "frell"))
    end)

    it("prefers overrideName over preferredName", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Main", main = "Main", isMain = true, displayName = "Chief" }),
      })
      groups[1].overrideName = "Buddy"
      assert.are.equal("Buddy", GTD.FormatMainRowName(groups[1]))
    end)

    it("appends gray (you) when the group is the player's own", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Main", main = "Main", isMain = true, displayName = "Chief", classFile = "MAGE" }),
      })
      assert.are.equal(
        "Chief |cff808080(you)|r",
        GTD.FormatMainRowName(groups[1], plainFormatName, nil, true))
      assert.are.equal("Chief", GTD.FormatMainRowName(groups[1], plainFormatName, nil, false))
    end)
  end)

  describe("ResolveGroupDisplayName", function()
    it("prefers override, then preferredName, then main", function()
      assert.are.equal("Buddy", GTD.ResolveGroupDisplayName({
        main = "Main", preferredName = "Chief", overrideName = "Buddy",
      }))
      assert.are.equal("Chief", GTD.ResolveGroupDisplayName({
        main = "Main", preferredName = "Chief",
      }))
      assert.are.equal("Main", GTD.ResolveGroupDisplayName({ main = "Main" }))
      assert.are.equal("?", GTD.ResolveGroupDisplayName({}))
    end)

    it("accepts an optional getOverride callback", function()
      local name = GTD.ResolveGroupDisplayName(
        { main = "Main", preferredName = "Chief" },
        function(group) return group.main == "Main" and "FromCb" or nil end)
      assert.are.equal("FromCb", name)
    end)
  end)

  describe("IsOwnGroup", function()
    it("is true when group main matches the player's main", function()
      assert.is_true(GTD.IsOwnGroup({ main = "Me" }, "Me"))
      assert.is_false(GTD.IsOwnGroup({ main = "Me" }, "Other"))
      assert.is_false(GTD.IsOwnGroup({ main = "Me" }, nil))
    end)
  end)

  describe("FormatMainRowCount", function()
    it("pluralizes the character count", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Main", main = "Main", isMain = true, displayName = "Chief" }),
        member({ name = "Alt", main = "Main" }),
      })
      assert.are.equal("2 characters", GTD.FormatMainRowCount(groups[1]))
    end)

    it("uses the singular form for a single character", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Solo", main = "Solo", isMain = true, displayName = "Solo" }),
      })
      assert.are.equal("1 character", GTD.FormatMainRowCount(groups[1]))
    end)
  end)

  describe("FormatMainRowLabel", function()
    it("shows the preferred name and pluralized character count", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Main", main = "Main", isMain = true, displayName = "Chief" }),
        member({ name = "Alt", main = "Main" }),
      })
      assert.are.equal("Chief 2 characters", GTD.FormatMainRowLabel(groups[1]))
    end)

    it("uses the singular form for a single character", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Solo", main = "Solo", isMain = true, displayName = "Solo" }),
      })
      assert.are.equal("Solo 1 character", GTD.FormatMainRowLabel(groups[1]))
    end)

    it("colors the preferred name via formatName while leaving the count plain", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Main", main = "Main", isMain = true, displayName = "Chief", classFile = "MAGE" }),
        member({ name = "Alt", main = "Main" }),
      })
      local seen = {}
      local function fakeFormat(name, classFile)
        seen.name, seen.classFile = name, classFile
        return "<" .. classFile .. ">" .. name
      end
      assert.are.equal("<MAGE>Chief 2 characters",
        GTD.FormatMainRowLabel(groups[1], fakeFormat))
      assert.are.equal("Chief", seen.name)
      assert.are.equal("MAGE", seen.classFile)
    end)

    it("highlights the matching portion of the preferred name", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Main", main = "Main", isMain = true, displayName = "Mindfrell", classFile = "MAGE" }),
      })
      assert.are.equal(
        "Mind|cff00ff00frell|r 1 character",
        GTD.FormatMainRowLabel(groups[1], plainFormatName, "frell"))
    end)
  end)

  describe("roster last online", function()
    describe("NormalizeRosterName", function()
      it("strips a realm suffix and lowercases", function()
        assert.are.equal("alice", GTD.NormalizeRosterName("Alice-EmeraldDream"))
      end)

      it("returns the short name lowercased", function()
        assert.are.equal("bob", GTD.NormalizeRosterName("Bob"))
      end)

      it("returns nil for non-strings", function()
        assert.is_nil(GTD.NormalizeRosterName(nil))
        assert.is_nil(GTD.NormalizeRosterName(12))
      end)
    end)

    describe("RosterOfflineHours", function()
      it("returns 0 for online or missing status", function()
        assert.are.equal(0, GTD.RosterOfflineHours({ online = true }))
        assert.are.equal(0, GTD.RosterOfflineHours(nil))
      end)

      it("converts years/months/days/hours into comparable hours", function()
        local hours = GTD.RosterOfflineHours({
          online = false, years = 0, months = 1, days = 2, hours = 3,
        })
        assert.are.equal(((1 * 30.5) + 2) * 24 + 3, hours)
      end)
    end)

    describe("FormatRosterLastOnline", function()
      it("returns empty string when status is missing", function()
        assert.are.equal("", GTD.FormatRosterLastOnline(nil))
      end)

      it("returns gray Unknown when status is missing and showUnknownWhenMissing", function()
        assert.are.equal("|cff808080Unknown|r", GTD.FormatRosterLastOnline(nil, {
          showUnknownWhenMissing = true,
        }))
      end)

      it("returns Online when the character is online", function()
        assert.are.equal("Online", GTD.FormatRosterLastOnline({ online = true }))
      end)

      it("formats the largest non-zero unit", function()
        assert.are.equal("2y ago", GTD.FormatRosterLastOnline({
          online = false, years = 2, months = 3, days = 4, hours = 5,
        }))
        assert.are.equal("3mo ago", GTD.FormatRosterLastOnline({
          online = false, years = 0, months = 3, days = 4, hours = 5,
        }))
        assert.are.equal("4d ago", GTD.FormatRosterLastOnline({
          online = false, years = 0, months = 0, days = 4, hours = 5,
        }))
        assert.are.equal("5h ago", GTD.FormatRosterLastOnline({
          online = false, years = 0, months = 0, days = 0, hours = 5,
        }))
      end)

      it("returns < 1h ago when offline duration is under an hour", function()
        assert.are.equal("< 1h ago", GTD.FormatRosterLastOnline({
          online = false, years = 0, months = 0, days = 0, hours = 0,
        }))
      end)
    end)

    describe("PickMostRecentRosterStatus", function()
      it("returns Online when any status is online", function()
        local status = GTD.PickMostRecentRosterStatus({
          { online = false, years = 0, months = 0, days = 5, hours = 0 },
          { online = true },
          { online = false, years = 0, months = 0, days = 1, hours = 0 },
        })
        assert.are.same({ online = true }, status)
      end)

      it("picks the shortest offline duration", function()
        local status = GTD.PickMostRecentRosterStatus({
          { online = false, years = 0, months = 0, days = 5, hours = 0 },
          { online = false, years = 0, months = 0, days = 1, hours = 2 },
          { online = false, years = 0, months = 0, days = 3, hours = 0 },
        })
        assert.are.same({
          online = false, years = 0, months = 0, days = 1, hours = 2,
        }, status)
      end)

      it("ignores nil statuses and returns nil when none remain", function()
        assert.is_nil(GTD.PickMostRecentRosterStatus({ nil, nil }))
        assert.is_nil(GTD.PickMostRecentRosterStatus(nil))
      end)
    end)

    describe("GetGroupLastOnlineStatus", function()
      it("aggregates the most recent status across group members", function()
        local groups = GTD.GroupMembersByMain({
          member({ name = "Main", main = "Main", isMain = true, displayName = "Chief" }),
          member({ name = "Alt", main = "Main" }),
        })
        local roster = {
          main = { online = false, years = 0, months = 0, days = 4, hours = 0 },
          alt = { online = false, years = 0, months = 0, days = 1, hours = 0 },
        }
        assert.are.same(roster.alt, GTD.GetGroupLastOnlineStatus(groups[1], roster))
      end)

      it("matches roster names that include a realm suffix", function()
        local groups = GTD.GroupMembersByMain({
          member({ name = "Alice", main = "Alice", isMain = true, displayName = "Alice" }),
        })
        local roster = {
          alice = { online = true },
        }
        assert.are.same({ online = true }, GTD.GetGroupLastOnlineStatus(groups[1], roster))
      end)

      it("returns nil when no group members appear in the roster", function()
        local groups = GTD.GroupMembersByMain({
          member({ name = "Ghost", main = "Ghost", isMain = true, displayName = "Ghost" }),
        })
        assert.is_nil(GTD.GetGroupLastOnlineStatus(groups[1], {}))
      end)
    end)

    describe("GetGroupMostRecentOnlineDetail", function()
      it("returns which member is the most recent and their status", function()
        local groups = GTD.GroupMembersByMain({
          member({ name = "Main", main = "Main", isMain = true, displayName = "Chief" }),
          member({ name = "Alt", main = "Main" }),
        })
        local roster = {
          main = { online = false, years = 0, months = 0, days = 4, hours = 0 },
          alt = { online = true },
        }
        local detail = GTD.GetGroupMostRecentOnlineDetail(groups[1], roster)
        assert.are.equal("Alt", detail.memberName)
        assert.is_true(detail.status.online)
      end)

      it("returns nil when nothing is in the roster", function()
        local groups = GTD.GroupMembersByMain({
          member({ name = "Ghost", main = "Ghost", isMain = true, displayName = "Ghost" }),
        })
        assert.is_nil(GTD.GetGroupMostRecentOnlineDetail(groups[1], {}))
      end)
    end)

    describe("FormatGroupPresenceTooltipLine", function()
      it("returns nil when detail is missing", function()
        assert.is_nil(GTD.FormatGroupPresenceTooltipLine("Bob", nil))
      end)

      it("returns white Online when the hovered character is online", function()
        assert.are.equal(
          "|cffffffffOnline|r",
          GTD.FormatGroupPresenceTooltipLine("Bob", {
            memberName = "Bob",
            status = { online = true },
          })
        )
      end)

      it("notes when another character is the online presence", function()
        assert.are.equal(
          "|cffffffffOnline (as |rAlice|cffffffff)|r",
          GTD.FormatGroupPresenceTooltipLine("Bob", {
            memberName = "Alice",
            classFile = "WARRIOR",
            status = { online = true },
          }, plainFormatName)
        )
      end)

      it("class-colors the other character name in the as-clause", function()
        assert.are.equal(
          "|cffffffffOnline (as |r[Alice]|cffffffff)|r",
          GTD.FormatGroupPresenceTooltipLine("Bob", {
            memberName = "Alice",
            classFile = "WARRIOR",
            status = { online = true },
          }, function(name) return "[" .. name .. "]" end)
        )
      end)

      it("formats last seen in gray and notes a different character when applicable", function()
        assert.are.equal(
          "|cff808080Last seen 5h ago|r",
          GTD.FormatGroupPresenceTooltipLine("Bob", {
            memberName = "Bob",
            status = { online = false, years = 0, months = 0, days = 0, hours = 5 },
          }, plainFormatName)
        )
        assert.are.equal(
          "|cff808080Last seen 2d ago (as |rAlice|cff808080)|r",
          GTD.FormatGroupPresenceTooltipLine("Bob", {
            memberName = "Alice",
            status = { online = false, years = 0, months = 0, days = 2, hours = 0 },
          }, plainFormatName)
        )
      end)
    end)

    describe("BuildGuildCharacterHoverTooltipLines", function()
      it("builds title and level lines with class-colored name and main", function()
        local lines = GTD.BuildGuildCharacterHoverTooltipLines({
          name = "Bob",
          preferredName = "Chief",
          preferredClassFile = "WARRIOR",
          classFile = "MAGE",
          level = 70,
          formatName = function(name) return "[" .. name .. "]" end,
          classDisplayName = "Mage",
        })
        assert.are.equal("[Bob] |cffffffff(|r[Chief]|cffffffff)|r", lines[1])
        assert.are.equal("Level 70 Mage", lines[2])
        assert.is_nil(lines[3])
      end)

      it("omits preferred name when it matches the character name", function()
        local lines = GTD.BuildGuildCharacterHoverTooltipLines({
          name = "Bob",
          preferredName = "bob",
          classFile = "MAGE",
          level = 70,
          formatName = plainFormatName,
          classDisplayName = "Mage",
        })
        assert.are.equal("Bob", lines[1])
        assert.are.equal("Level 70 Mage", lines[2])
      end)

      it("appends a presence line when roster detail is available", function()
        local lines = GTD.BuildGuildCharacterHoverTooltipLines({
          name = "Bob",
          preferredName = "Chief",
          preferredClassFile = "WARRIOR",
          classFile = "MAGE",
          level = 70,
          formatName = plainFormatName,
          classDisplayName = "Mage",
          presenceDetail = {
            memberName = "Alice",
            status = { online = true },
          },
        })
        assert.are.equal("Bob |cffffffff(|rChief|cffffffff)|r", lines[1])
        assert.are.equal("Level 70 Mage", lines[2])
        assert.are.equal("|cffffffffOnline (as |rAlice|cffffffff)|r", lines[3])
        assert.is_true(lines.presenceOnline)
      end)

      it("inserts a green specialization line under the name when provided", function()
        local lines = GTD.BuildGuildCharacterHoverTooltipLines({
          name = "Bob",
          preferredName = "Bob",
          classFile = "MAGE",
          level = 70,
          formatName = plainFormatName,
          classDisplayName = "Mage",
          specializationLabel = "Potion",
          presenceDetail = {
            memberName = "Bob",
            status = { online = true },
          },
        })
        assert.are.equal("Bob", lines[1])
        assert.are.equal("|cff00ff00Potion specialization|r", lines[2])
        assert.are.equal("Level 70 Mage", lines[3])
        assert.are.equal("|cffffffffOnline|r", lines[4])
      end)

      it("marks presenceOnline false when last seen", function()
        local lines = GTD.BuildGuildCharacterHoverTooltipLines({
          name = "Bob",
          preferredName = "Bob",
          classFile = "MAGE",
          level = 70,
          formatName = plainFormatName,
          classDisplayName = "Mage",
          presenceDetail = {
            memberName = "Bob",
            status = { online = false, years = 0, months = 0, days = 0, hours = 5 },
          },
        })
        assert.are.equal("|cff808080Last seen 5h ago|r", lines[3])
        assert.is_false(lines.presenceOnline)
      end)
    end)

    describe("SortGuildSearchCharsByLastOnline", function()
      it("sorts online first A-Z, then shortest offline, unknown last A-Z", function()
        local chars = {
          { characterName = "Zebra" },
          { characterName = "Alice" },
          { characterName = "Bob" },
          { characterName = "Carol" },
          { characterName = "Amy" },
          { characterName = "Dave" },
        }
        GTD.SortGuildSearchCharsByLastOnline(chars, {
          zebra = { online = true },
          alice = { online = false, years = 0, months = 0, days = 1, hours = 0 },
          bob = { online = true },
          carol = { online = false, years = 0, months = 0, days = 0, hours = 5 },
          amy = { online = true },
        })
        assert.are.equal("Amy", chars[1].characterName)
        assert.are.equal("Bob", chars[2].characterName)
        assert.are.equal("Zebra", chars[3].characterName)
        assert.are.equal("Carol", chars[4].characterName)
        assert.are.equal("Alice", chars[5].characterName)
        assert.are.equal("Dave", chars[6].characterName)
      end)

      it("falls back to A-Z when roster is empty", function()
        local chars = {
          { characterName = "Zebra" },
          { characterName = "Alice" },
          { characterName = "Bob" },
        }
        GTD.SortGuildSearchCharsByLastOnline(chars, {})
        assert.are.equal("Alice", chars[1].characterName)
        assert.are.equal("Bob", chars[2].characterName)
        assert.are.equal("Zebra", chars[3].characterName)
      end)

      it("prefers opts.getStatus over individual roster lookup", function()
        local chars = {
          { characterName = "Bob" },
          { characterName = "Alice" },
        }
        GTD.SortGuildSearchCharsByLastOnline(chars, {
          bob = { online = false, years = 0, months = 0, days = 2, hours = 0 },
          alice = { online = true },
        }, {
          getStatus = function(entry)
            if entry.characterName == "Bob" then
              return { online = true }
            end
            return { online = false, years = 0, months = 0, days = 1, hours = 0 }
          end,
        })
        assert.are.equal("Bob", chars[1].characterName)
        assert.are.equal("Alice", chars[2].characterName)
      end)
    end)

    describe("BuildCollapsedGuildRecipeTooltipLines", function()
      local function formatName(name)
        return "[" .. (name or "?") .. "]"
      end

      it("sorts online first alphabetically, then shortest offline, unknown last", function()
        local lines = GTD.BuildCollapsedGuildRecipeTooltipLines({
          { name = "Zebra", classFile = "MAGE", mainName = "Zebra", mainClassFile = "MAGE" },
          { name = "Alice", classFile = "WARRIOR", mainName = "Alice", mainClassFile = "WARRIOR" },
          { name = "Bob", classFile = "PRIEST", mainName = "Bob", mainClassFile = "PRIEST" },
          { name = "Carol", classFile = "HUNTER", mainName = "Carol", mainClassFile = "HUNTER" },
          { name = "Amy", classFile = "WARLOCK", mainName = "Amy", mainClassFile = "WARLOCK" },
          { name = "Dave", classFile = "ROGUE", mainName = "Dave", mainClassFile = "ROGUE" },
        }, {
          zebra = { online = true },
          alice = { online = false, years = 0, months = 0, days = 1, hours = 0 },
          bob = { online = true },
          carol = { online = false, years = 0, months = 0, days = 0, hours = 5 },
          amy = { online = true },
          -- Dave missing from roster
        }, { formatName = formatName })
        assert.are.equal(7, #lines)
        -- Online A–Z: Amy, Bob, Zebra; then Carol (5h), Alice (1d), Dave (Unknown); hint
        assert.are.equal("[Amy]", lines[1].left)
        assert.are.equal("|cffffffffOnline|r", lines[1].right)
        assert.are.equal("[Bob]", lines[2].left)
        assert.are.equal("|cffffffffOnline|r", lines[2].right)
        assert.are.equal("[Zebra]", lines[3].left)
        assert.are.equal("|cffffffffOnline|r", lines[3].right)
        assert.are.equal("[Carol]", lines[4].left)
        assert.are.equal("|cff8080805h ago|r", lines[4].right)
        assert.are.equal("[Alice]", lines[5].left)
        assert.are.equal("|cff8080801d ago|r", lines[5].right)
        assert.are.equal("[Dave]", lines[6].left)
        assert.are.equal("|cff808080Unknown|r", lines[6].right)
        assert.are.equal("|cff808080Click to expand|r", lines[7])
      end)

      it("prefers per-char status over individual roster lookup (player presence)", function()
        -- Bob's recipe alt is offline on the roster, but caller marks the player online.
        local lines = GTD.BuildCollapsedGuildRecipeTooltipLines({
          { name = "Zebra", classFile = "MAGE", mainName = "Zebra", mainClassFile = "MAGE" },
          {
            name = "Bob",
            classFile = "PRIEST",
            mainName = "Chief",
            mainClassFile = "WARRIOR",
            status = { online = true },
          },
        }, {
          zebra = { online = false, years = 0, months = 0, days = 2, hours = 0 },
          bob = { online = false, years = 0, months = 0, days = 5, hours = 0 },
        }, { formatName = formatName })
        assert.is_truthy(lines[1].left:find("[Bob]", 1, true))
        assert.are.equal("|cffffffffOnline|r", lines[1].right)
        assert.are.equal("[Zebra]", lines[2].left)
        assert.are.equal("|cff8080802d ago|r", lines[2].right)
      end)

      it("omits main name when identical to character name", function()
        local lines = GTD.BuildCollapsedGuildRecipeTooltipLines({
          { name = "Bob", classFile = "MAGE", mainName = "bob", mainClassFile = "WARRIOR" },
        }, {
          bob = { online = true },
        }, { formatName = formatName })
        assert.are.equal(2, #lines)
        assert.are.same({ left = "[Bob]", right = "|cffffffffOnline|r" }, lines[1])
        assert.are.equal("|cff808080Click to expand|r", lines[2])
      end)

      it("includes class-colored main name when different", function()
        local lines = GTD.BuildCollapsedGuildRecipeTooltipLines({
          { name = "Bob", classFile = "MAGE", mainName = "Chief", mainClassFile = "WARRIOR" },
        }, {
          bob = { online = true },
        }, { formatName = formatName })
        assert.are.equal(2, #lines)
        assert.are.equal("[Bob] |cffffffff(|r[Chief]|cffffffff)|r", lines[1].left)
        assert.are.equal("|cffffffffOnline|r", lines[1].right)
        assert.are.equal("|cff808080Click to expand|r", lines[2])
      end)

      it("prefixes the name with namePrefix when provided", function()
        local lines = GTD.BuildCollapsedGuildRecipeTooltipLines({
          {
            name = "Bob",
            classFile = "MAGE",
            mainName = "Chief",
            mainClassFile = "WARRIOR",
            namePrefix = "|cff33ff33+|r ",
          },
          { name = "Alice", classFile = "WARRIOR", mainName = "Alice" },
        }, {
          bob = { online = true },
          alice = { online = true },
        }, { formatName = formatName })
        assert.are.equal("[Alice]", lines[1].left)
        assert.are.equal("|cff33ff33+|r [Bob] |cffffffff(|r[Chief]|cffffffff)|r", lines[2].left)
      end)

      it("uses gray Unknown when roster status is missing", function()
        local lines = GTD.BuildCollapsedGuildRecipeTooltipLines({
          { name = "Bob", classFile = "MAGE", mainName = "Bob", mainClassFile = "MAGE" },
        }, {}, { formatName = formatName })
        assert.are.equal(2, #lines)
        assert.are.same({ left = "[Bob]", right = "|cff808080Unknown|r" }, lines[1])
        assert.are.equal("|cff808080Click to expand|r", lines[2])
      end)

      it("shows all characters when fewer than 10, plus expand hint", function()
        local chars = {}
        local roster = {}
        for i = 1, 9 do
          local name = "Char" .. i
          chars[i] = { name = name, classFile = "MAGE", mainName = name, mainClassFile = "MAGE" }
          roster[name:lower()] = { online = true }
        end
        local lines = GTD.BuildCollapsedGuildRecipeTooltipLines(chars, roster, { formatName = formatName })
        assert.are.equal(10, #lines)
        assert.are.equal("[Char9]", lines[9].left)
        assert.are.equal("|cff808080Click to expand|r", lines[10])
      end)

      it("truncates to 8 lines plus white others and gray expand hint when 10 or more", function()
        local chars = {}
        local roster = {}
        for i = 1, 12 do
          local name = "Char" .. i
          chars[i] = { name = name, classFile = "MAGE", mainName = name, mainClassFile = "MAGE" }
          roster[name:lower()] = {
            online = false, years = 0, months = 0, days = 0, hours = i,
          }
        end
        local lines = GTD.BuildCollapsedGuildRecipeTooltipLines(chars, roster, { formatName = formatName })
        assert.are.equal(10, #lines)
        assert.are.equal("[Char1]", lines[1].left)
        assert.are.equal("[Char8]", lines[8].left)
        assert.are.equal("|cffffffff...and 4 others|r", lines[9])
        assert.are.equal("|cff808080Click to expand|r", lines[10])
      end)

      it("says Click to collapse when opts.isExpanded", function()
        local lines = GTD.BuildCollapsedGuildRecipeTooltipLines({
          { name = "Bob", classFile = "MAGE", mainName = "Bob", mainClassFile = "MAGE" },
        }, {
          bob = { online = true },
        }, { formatName = formatName, isExpanded = true })
        assert.are.equal("|cff808080Click to collapse|r", lines[#lines])
      end)

      it("returns empty table for nil or empty chars", function()
        assert.are.same({}, GTD.BuildCollapsedGuildRecipeTooltipLines(nil, {}))
        assert.are.same({}, GTD.BuildCollapsedGuildRecipeTooltipLines({}, {}))
      end)
    end)

    describe("BuildOwnCharacterHoverTooltipLines", function()
      it("builds class-colored name and level/class lines only", function()
        local lines = GTD.BuildOwnCharacterHoverTooltipLines({
          name = "MyAlt",
          classFile = "MAGE",
          level = 68,
          formatName = function(name) return "[" .. name .. "]" end,
          classDisplayName = "Mage",
        })
        assert.are.equal("[MyAlt]", lines[1])
        assert.are.equal("Level 68 Mage", lines[2])
        assert.is_nil(lines[3])
      end)

      it("inserts a green specialization line under the name when provided", function()
        local lines = GTD.BuildOwnCharacterHoverTooltipLines({
          name = "MyAlt",
          classFile = "MAGE",
          level = 68,
          formatName = plainFormatName,
          classDisplayName = "Mage",
          specializationLabel = "Potion",
        })
        assert.are.equal("MyAlt", lines[1])
        assert.are.equal("|cff00ff00Potion specialization|r", lines[2])
        assert.are.equal("Level 68 Mage", lines[3])
        assert.is_nil(lines[4])
      end)

      it("does not include preferred name or presence", function()
        local lines = GTD.BuildOwnCharacterHoverTooltipLines({
          name = "MyAlt",
          preferredName = "Chief",
          classFile = "WARRIOR",
          level = 70,
          formatName = plainFormatName,
          classDisplayName = "Warrior",
          presenceDetail = {
            memberName = "MyAlt",
            status = { online = true },
          },
        })
        assert.are.equal("MyAlt", lines[1])
        assert.are.equal("Level 70 Warrior", lines[2])
        assert.is_nil(lines[3])
      end)
    end)

    describe("ResolveOnlineWhisperTarget", function()
      it("returns nil when nobody in the group is online", function()
        local entry = member({ name = "Bob", main = "Main", displayName = "Chief" })
        local members = {
          member({ name = "Main", main = "Main", isMain = true, displayName = "Chief" }),
          entry,
        }
        local roster = {
          bob = { online = false, years = 0, months = 0, days = 0, hours = 5 },
          main = { online = false, years = 0, months = 0, days = 1, hours = 0 },
        }
        assert.is_nil(GTD.ResolveOnlineWhisperTarget(entry, roster, members))
      end)

      it("returns the online character even when viewing a different alt", function()
        local entry = member({ name = "Bob", main = "Main", displayName = "Chief" })
        local members = {
          member({ name = "Alice", main = "Main", isMain = true, displayName = "Chief" }),
          entry,
        }
        local roster = {
          bob = { online = false, years = 0, months = 0, days = 0, hours = 5 },
          alice = { online = true },
        }
        assert.are.equal("Alice", GTD.ResolveOnlineWhisperTarget(entry, roster, members))
      end)

      it("returns the viewed character when they are the online one", function()
        local entry = member({ name = "Bob", main = "Main", displayName = "Chief" })
        local members = {
          member({ name = "Alice", main = "Main", isMain = true, displayName = "Chief" }),
          entry,
        }
        local roster = {
          bob = { online = true },
          alice = { online = false, years = 0, months = 0, days = 1, hours = 0 },
        }
        assert.are.equal("Bob", GTD.ResolveOnlineWhisperTarget(entry, roster, members))
      end)

      it("returns nil for the player's own (local) characters", function()
        local entry = member({ name = "MyAlt", main = "MyMain", source = "local" })
        local members = {
          member({ name = "MyMain", main = "MyMain", isMain = true, source = "local" }),
          entry,
        }
        local roster = {
          myalt = { online = true },
          mymain = { online = true },
        }
        assert.is_nil(GTD.ResolveOnlineWhisperTarget(entry, roster, members))
      end)
    end)

    describe("character recipe title level suffix", function()
      it("formats full and short level suffixes", function()
        assert.are.equal(" (level 70)", GTD.FormatCharacterLevelSuffix(70, "full"))
        assert.are.equal(" (70)", GTD.FormatCharacterLevelSuffix(70, "short"))
        assert.are.equal(
          " |cff808080(level 70)|r",
          GTD.FormatCharacterLevelSuffix(70, "full", "|cff808080")
        )
      end)

      it("chooses full, short, or ellipsis mode from fit flags", function()
        assert.are.equal("full", GTD.ChooseCharacterTitleLevelMode(true, true))
        assert.are.equal("short", GTD.ChooseCharacterTitleLevelMode(false, true))
        assert.are.equal("ellipsis", GTD.ChooseCharacterTitleLevelMode(false, false))
      end)
    end)

    describe("BuildRosterLastOnlineMap", function()
      it("returns an empty map when not in a guild", function()
        local map = GTD.BuildRosterLastOnlineMap({
          isInGuild = function() return false end,
          getNumGuildMembers = function() return 3 end,
        })
        assert.are.same({}, map)
      end)

      it("maps online and offline members by short name", function()
        local roster = {
          [1] = { name = "Alice-Realm", online = true },
          [2] = { name = "Bob", online = false, years = 0, months = 0, days = 2, hours = 4 },
        }
        local map = GTD.BuildRosterLastOnlineMap({
          isInGuild = function() return true end,
          getNumGuildMembers = function() return 2 end,
          getGuildRosterInfo = function(i)
            local e = roster[i]
            return e.name, nil, nil, nil, nil, nil, nil, nil, e.online
          end,
          getGuildRosterLastOnline = function(i)
            local e = roster[i]
            return e.years, e.months, e.days, e.hours
          end,
        })
        assert.are.same({
          alice = { online = true },
          bob = { online = false, years = 0, months = 0, days = 2, hours = 4 },
        }, map)
      end)
    end)

    describe("BuildRosterInfoMap", function()
      it("returns an empty map when not in a guild", function()
        local map = GTD.BuildRosterInfoMap({
          isInGuild = function() return false end,
          getNumGuildMembers = function() return 3 end,
        })
        assert.are.same({}, map)
      end)

      it("maps classFile and level by normalized short name", function()
        local roster = {
          [1] = { name = "Alice-Realm", level = 70, classFile = "MAGE" },
          [2] = { name = "Bob", level = 60, classFile = "WARRIOR" },
        }
        local map = GTD.BuildRosterInfoMap({
          isInGuild = function() return true end,
          getNumGuildMembers = function() return 2 end,
          getGuildRosterInfo = function(i)
            local e = roster[i]
            -- name, rank, rankIndex, level, class, zone, note, officernote, online, status, classFileName
            return e.name, nil, nil, e.level, nil, nil, nil, nil, true, nil, e.classFile
          end,
        })
        assert.are.same({
          alice = { classFile = "MAGE", level = 70, name = "Alice", note = "" },
          bob = { classFile = "WARRIOR", level = 60, name = "Bob", note = "" },
        }, map)
      end)

      it("prefers public note and falls back to officer note", function()
        local roster = {
          [1] = { name = "Alice", level = 70, classFile = "MAGE", note = "  main bank  ", officer = "ignored" },
          [2] = { name = "Bob", level = 60, classFile = "WARRIOR", note = "", officer = "Alice's alt" },
          [3] = { name = "Carol", level = 60, classFile = "PRIEST", note = "   ", officer = "  " },
        }
        local map = GTD.BuildRosterInfoMap({
          isInGuild = function() return true end,
          getNumGuildMembers = function() return 3 end,
          getGuildRosterInfo = function(i)
            local e = roster[i]
            return e.name, nil, nil, e.level, nil, nil, e.note, e.officer, true, nil, e.classFile
          end,
        })
        assert.are.equal("main bank", map.alice.note)
        assert.are.equal("Alice's alt", map.bob.note)
        assert.are.equal("", map.carol.note)
      end)

      it("skips a roster row whose name is inaccessible (secret) but keeps the rest", function()
        local roster = {
          [1] = { name = "Alice", level = 70, classFile = "MAGE" },
          [2] = { name = "SecretName", level = 60, classFile = "WARRIOR" },
        }
        _G.canaccessvalue = function(v) return v ~= "SecretName" end
        local map = GTD.BuildRosterInfoMap({
          isInGuild = function() return true end,
          getNumGuildMembers = function() return 2 end,
          getGuildRosterInfo = function(i)
            local e = roster[i]
            return e.name, nil, nil, e.level, nil, nil, nil, nil, true, nil, e.classFile
          end,
        })
        _G.canaccessvalue = nil
        assert.are.same({
          alice = { classFile = "MAGE", level = 70, name = "Alice", note = "" },
        }, map)
      end)
    end)

    describe("FormatRosterSuggestName", function()
      it("class-colors the name and appends a white level suffix", function()
        local text = GTD.FormatRosterSuggestName({
          name = "Alice",
          classFile = "MAGE",
          level = 70,
        }, function(name, classFile)
          return "[" .. classFile .. "]" .. name
        end)
        assert.are.equal("[MAGE]Alice |cffffffff(70)|r", text)
      end)

      it("uses 0 when level is missing", function()
        local text = GTD.FormatRosterSuggestName({ name = "Bob" }, function(name)
          return name
        end)
        assert.are.equal("Bob |cffffffff(0)|r", text)
      end)

      it("highlights matching substrings in the name when a query is provided", function()
        local text = GTD.FormatRosterSuggestName({
          name = "Banky",
          classFile = "WARRIOR",
          level = 60,
        }, function(name)
          return name
        end, "bank")
        assert.are.equal("|cff00ff00Bank|ry |cffffffff(60)|r", text)
      end)
    end)
  end)

  describe("SortGroups", function()
    local function grouped(members)
      return GTD.GroupMembersByMain(members)
    end

    it("sorts by preferred name ascending by default", function()
      local groups = grouped({
        member({ name = "Zed", main = "Zed", isMain = true, displayName = "Zed" }),
        member({ name = "Amy", main = "Amy", isMain = true, displayName = "Amy" }),
        member({ name = "Bob", main = "Bob", isMain = true, displayName = "Bob" }),
      })
      local sorted = GTD.SortGroups(groups, "name", true)
      assert.are.equal("Amy", sorted[1].preferredName)
      assert.are.equal("Bob", sorted[2].preferredName)
      assert.are.equal("Zed", sorted[3].preferredName)
    end)

    it("sorts by preferred name descending", function()
      local groups = grouped({
        member({ name = "Zed", main = "Zed", isMain = true, displayName = "Zed" }),
        member({ name = "Amy", main = "Amy", isMain = true, displayName = "Amy" }),
      })
      local sorted = GTD.SortGroups(groups, "name", false)
      assert.are.equal("Zed", sorted[1].preferredName)
      assert.are.equal("Amy", sorted[2].preferredName)
    end)

    it("sorts by character count", function()
      local groups = grouped({
        member({ name = "Solo", main = "Solo", isMain = true, displayName = "Solo" }),
        member({ name = "Main", main = "Main", isMain = true, displayName = "Duo" }),
        member({ name = "Alt", main = "Main" }),
      })
      local asc = GTD.SortGroups(groups, "characterCount", true)
      assert.are.equal("Solo", asc[1].preferredName)
      assert.are.equal("Duo", asc[2].preferredName)
      local desc = GTD.SortGroups(groups, "characterCount", false)
      assert.are.equal("Duo", desc[1].preferredName)
      assert.are.equal("Solo", desc[2].preferredName)
    end)

    it("sorts online as least time, then hours, days, months, years", function()
      local groups = grouped({
        member({ name = "Old", main = "Old", isMain = true, displayName = "Old" }),
        member({ name = "Live", main = "Live", isMain = true, displayName = "Live" }),
        member({ name = "Recent", main = "Recent", isMain = true, displayName = "Recent" }),
        member({ name = "DayOld", main = "DayOld", isMain = true, displayName = "DayOld" }),
        member({ name = "Gone", main = "Gone", isMain = true, displayName = "Gone" }),
      })
      local roster = {
        live = { online = true },
        recent = { online = false, years = 0, months = 0, days = 0, hours = 2 },
        dayold = { online = false, years = 0, months = 0, days = 1, hours = 0 },
        old = { online = false, years = 0, months = 0, days = 10, hours = 0 },
      }
      local sorted = GTD.SortGroups(groups, "online", true, roster)
      assert.are.equal("Live", sorted[1].preferredName)
      assert.are.equal("Recent", sorted[2].preferredName)
      assert.are.equal("DayOld", sorted[3].preferredName)
      assert.are.equal("Old", sorted[4].preferredName)
      assert.are.equal("Gone", sorted[5].preferredName)
    end)

    it("sorts online descending from most time to least, with online last", function()
      local groups = grouped({
        member({ name = "Old", main = "Old", isMain = true, displayName = "Old" }),
        member({ name = "Live", main = "Live", isMain = true, displayName = "Live" }),
        member({ name = "Recent", main = "Recent", isMain = true, displayName = "Recent" }),
        member({ name = "Gone", main = "Gone", isMain = true, displayName = "Gone" }),
      })
      local roster = {
        live = { online = true },
        recent = { online = false, years = 0, months = 0, days = 0, hours = 2 },
        old = { online = false, years = 0, months = 0, days = 10, hours = 0 },
      }
      local sorted = GTD.SortGroups(groups, "online", false, roster)
      assert.are.equal("Gone", sorted[1].preferredName)
      assert.are.equal("Old", sorted[2].preferredName)
      assert.are.equal("Recent", sorted[3].preferredName)
      assert.are.equal("Live", sorted[4].preferredName)
    end)

    it("matches roster names case-insensitively when sorting by online", function()
      local groups = grouped({
        member({ name = "Live", main = "Live", isMain = true, displayName = "Live" }),
        member({ name = "Old", main = "Old", isMain = true, displayName = "Old" }),
      })
      local roster = {
        live = { online = true },
        old = { online = false, years = 0, months = 0, days = 3, hours = 0 },
      }
      local sorted = GTD.SortGroups(groups, "online", true, roster)
      assert.are.equal("Live", sorted[1].preferredName)
      assert.are.equal("Old", sorted[2].preferredName)
    end)

    it("sorts members within a group by online when sorting by online", function()
      local groups = grouped({
        member({ name = "Main", main = "Main", isMain = true, displayName = "Chief", level = 70 }),
        member({ name = "Alt", main = "Main", level = 60 }),
      })
      local roster = {
        main = { online = false, years = 0, months = 0, days = 5, hours = 0 },
        alt = { online = true },
      }
      local sorted = GTD.SortGroups(groups, "online", true, roster)
      assert.are.equal("Alt", sorted[1].members[1].name)
      assert.are.equal("Main", sorted[1].members[2].name)
    end)

    it("ties break by preferred name ascending even when online sort is descending", function()
      local groups = grouped({
        member({ name = "B", main = "B", isMain = true, displayName = "B" }),
        member({ name = "A", main = "A", isMain = true, displayName = "A" }),
      })
      local roster = {
        a = { online = true },
        b = { online = true },
      }
      local sorted = GTD.SortGroups(groups, "online", false, roster)
      assert.are.equal("A", sorted[1].preferredName)
      assert.are.equal("B", sorted[2].preferredName)
    end)

    it("does not mutate the input list", function()
      local groups = grouped({
        member({ name = "Zed", main = "Zed", isMain = true, displayName = "Zed" }),
        member({ name = "Amy", main = "Amy", isMain = true, displayName = "Amy" }),
      })
      local first = groups[1].preferredName
      GTD.SortGroups(groups, "name", true)
      assert.are.equal(first, groups[1].preferredName)
    end)

    it("sorts pinned groups before unpinned while preserving name order within each bucket", function()
      local groups = grouped({
        member({ name = "Zed", main = "Zed", isMain = true, displayName = "Zed" }),
        member({ name = "Amy", main = "Amy", isMain = true, displayName = "Amy" }),
        member({ name = "Bob", main = "Bob", isMain = true, displayName = "Bob" }),
      })
      -- GroupMembersByMain orders Amy, Bob, Zed; pin Bob and Zed.
      groups[2].pinned = true
      groups[3].pinned = true
      local sorted = GTD.SortGroups(groups, "name", true)
      assert.are.equal("Bob", sorted[1].preferredName)
      assert.are.equal("Zed", sorted[2].preferredName)
      assert.are.equal("Amy", sorted[3].preferredName)
    end)
  end)

  describe("GetStoredCharacter", function()
    it("reads from DataStore for local entries", function()
      local savedDS = AltArmy.DataStore
      local charData = { name = "Local", Professions = { tailoring = { rank = 300 } } }
      AltArmy.DataStore = {
        GetCharacters = function(_, realm)
          if realm == "R" then return { Local = charData } end
          return {}
        end,
      }
      local entry = member({ name = "Local", realm = "R", source = "local" })
      assert.are.same(charData, GTD.GetStoredCharacter(entry))
      AltArmy.DataStore = savedDS
    end)

    it("reads from GuildShareData for remote entries", function()
      local savedGSD = AltArmy.GuildShareData
      local stored = { name = "Remote", Professions = {} }
      AltArmy.GuildShareData = {
        GetCharacter = function(name, realm)
          if name == "Remote" and realm == "R" then return stored end
          return nil
        end,
      }
      local entry = member({ name = "Remote", realm = "R", source = "Peer" })
      assert.are.same(stored, GTD.GetStoredCharacter(entry))
      AltArmy.GuildShareData = savedGSD
    end)
  end)

  describe("GetProfessionRecipes", function()
    before_each(function()
      package.loaded["GuildShareProtocol"] = nil
      require("GuildShareProtocol")
    end)

    it("returns primary recipe ids sorted, excluding aliases", function()
      local entry = member({
        name = "A",
        profs = {
          { key = "alchemy", name = "Alchemy", rank = 300 },
        },
      })
      entry.Professions.alchemy.Recipes = {
        [11449] = { primaryRecipeID = 11449, resultItemID = 9187 },
        [11334] = { primaryRecipeID = 11449 },
      }
      assert.are.same({
        { recipeID = 11449, resultItemID = 9187 },
      }, GTD.GetProfessionRecipes(entry, "alchemy"))
    end)

    it("carries the scan-time recipe name when one was stored", function()
      local entry = member({
        name = "A",
        profs = {
          { key = "alchemy", name = "Alchemy", rank = 300 },
        },
      })
      entry.Professions.alchemy.Recipes = {
        [11449] = { primaryRecipeID = 11449, resultItemID = 9187, name = "Elixir of Giants" },
      }
      assert.are.same({
        { recipeID = 11449, resultItemID = 9187, name = "Elixir of Giants" },
      }, GTD.GetProfessionRecipes(entry, "alchemy"))
    end)

    it("returns empty when profession is missing", function()
      assert.are.same({}, GTD.GetProfessionRecipes(member({ name = "A" }), "alchemy"))
    end)

    it("reads recipes from DataStore for local entries", function()
      local savedDS = AltArmy.DataStore
      AltArmy.DataStore = {
        GetCharacters = function(_, realm)
          if realm == "R" then
            return {
              Local = {
                Professions = {
                  tailoring = {
                    Recipes = {
                      [12045] = { primaryRecipeID = 12045 },
                      [12046] = { primaryRecipeID = 12046 },
                    },
                  },
                },
              },
            }
          end
          return {}
        end,
      }
      local entry = member({ name = "Local", realm = "R", source = "local" })
      assert.are.same({
        { recipeID = 12045 },
        { recipeID = 12046 },
      }, GTD.GetProfessionRecipes(entry, "tailoring"))
      AltArmy.DataStore = savedDS
    end)

    -- WoW Forever: Skinning has recipes (e.g. Camp Chair) but isn't in Search's profession tables,
    -- so the display-cased stored key "Skinning" must still match the "skinning" tab key.
    it("finds Skinning recipes stored under the display-cased profession name", function()
      local savedDS = AltArmy.DataStore
      AltArmy.DataStore = {
        GetCharacters = function(_, realm)
          if realm == "R" then
            return {
              Frell = {
                Professions = {
                  Skinning = {
                    rank = 150,
                    Recipes = {
                      [1229517] = { primaryRecipeID = 1229517, resultItemID = 279979, name = "Camp Chair" },
                    },
                  },
                },
              },
            }
          end
          return {}
        end,
      }
      local entry = member({ name = "Frell", realm = "R", source = "local" })
      local ok, result = pcall(GTD.GetProfessionRecipes, entry, "skinning")
      AltArmy.DataStore = savedDS
      assert.is_true(ok, tostring(result))
      assert.are.same({
        { recipeID = 1229517, resultItemID = 279979, name = "Camp Chair" },
      }, result)
    end)
  end)

  describe("FormatCharacterTitle", function()
    it("returns class-colored name via formatName", function()
      local m = member({ name = "Mage", classFile = "MAGE" })
      assert.are.equal("Mage", GTD.FormatCharacterTitle(m, plainFormatName))
    end)
  end)

  describe("FormatNoProfessionsMessage", function()
    it("embeds the class-colored character name when there are no professions", function()
      local m = member({ name = "Newbie", classFile = "WARRIOR" })
      assert.are.equal("No known professions for Newbie",
        GTD.FormatNoProfessionsMessage(m, plainFormatName))
    end)

    it("says they have no professions with recipes when only gathering is known", function()
      local m = member({ name = "Gatherer", classFile = "DRUID", profs = {
        { key = "mining", name = "Mining", rank = 300 },
        { key = "herbalism", name = "Herbalism", rank = 150 },
      } })
      assert.are.equal("Gatherer has no professions with recipes",
        GTD.FormatNoProfessionsMessage(m, plainFormatName))
    end)

    it("treats secondary-only skills as no known professions", function()
      local m = member({ name = "Cook", classFile = "MAGE", profs = {
        { key = "cooking", name = "Cooking", rank = 300 },
        { key = "firstAid", name = "First Aid", rank = 300 },
        { key = "fishing", name = "Fishing", rank = 300 },
        { key = "lockpicking", name = "Lockpicking", rank = 300 },
        { key = "poisons", name = "Poisons", rank = 300 },
      } })
      assert.are.equal("No known professions for Cook",
        GTD.FormatNoProfessionsMessage(m, plainFormatName))
    end)
  end)

  describe("FormatNoProfessionRecipesMessage", function()
    it("embeds the profession, class-colored character name, and a gray sharing hint", function()
      local m = member({ name = "Bob", classFile = "MAGE" })
      assert.are.equal(
        "No known Alchemy recipes for Bob\n\n|cff808080Data will be shared when they open their Alchemy screen|r",
        GTD.FormatNoProfessionRecipesMessage(m, plainFormatName, "Alchemy"))
    end)
  end)

  describe("CollectAccountGuilds", function()
    it("returns sorted unique guild names from account characters", function()
      local savedDS = AltArmy.DataStore
      AltArmy.DataStore = {
        ForEachCharacter = function(_, fn)
          fn("R1", "A", { guildName = "Zeta Guild" })
          fn("R1", "B", { guildName = "Alpha Guild" })
          fn("R2", "C", { guildName = "Alpha Guild" })
          fn("R2", "D", { guildName = nil })
        end,
      }
      assert.are.same({ "Alpha Guild", "Zeta Guild" }, GTD.CollectAccountGuilds())
      AltArmy.DataStore = savedDS
    end)

    it("returns empty when DataStore is unavailable", function()
      local savedDS = AltArmy.DataStore
      AltArmy.DataStore = nil
      assert.are.same({}, GTD.CollectAccountGuilds())
      AltArmy.DataStore = savedDS
    end)
  end)

  describe("CollectGuildsOnRealm", function()
    it("returns sorted unique guild names for characters on that realm only", function()
      local savedDS = AltArmy.DataStore
      AltArmy.DataStore = {
        GetCharacters = function(_, realm)
          if realm == "R1" then
            return {
              A = { guildName = "Zeta Guild" },
              B = { guildName = "Alpha Guild" },
            }
          end
          if realm == "R2" then
            return {
              C = { guildName = "Other Realm Guild" },
              D = { guildName = nil },
            }
          end
          return {}
        end,
      }
      assert.are.same({ "Alpha Guild", "Zeta Guild" }, GTD.CollectGuildsOnRealm("R1"))
      assert.are.same({ "Other Realm Guild" }, GTD.CollectGuildsOnRealm("R2"))
      assert.are.same({}, GTD.CollectGuildsOnRealm("Missing"))
      assert.are.same({}, GTD.CollectGuildsOnRealm(nil))
      AltArmy.DataStore = savedDS
    end)
  end)

  describe("ShouldShowGuildTab", function()
    it("requires the guildShare feature flag and at least one guilded character", function()
      assert.is_false(GTD.ShouldShowGuildTab(false, true))
      assert.is_false(GTD.ShouldShowGuildTab(true, false))
      assert.is_false(GTD.ShouldShowGuildTab(false, false))
      assert.is_true(GTD.ShouldShowGuildTab(true, true))
    end)
  end)

  describe("HasGuildedCharactersOnRealm", function()
    it("is true only when a character on that realm has a guild", function()
      local savedDS = AltArmy.DataStore
      AltArmy.DataStore = {
        GetCharacters = function(_, realm)
          if realm == "Current" then
            return { Unguilded = { guildName = nil } }
          end
          if realm == "Other" then
            return { Guilded = { guildName = "Other Guild" } }
          end
          return {}
        end,
      }
      assert.is_false(GTD.HasGuildedCharactersOnRealm("Current"))
      assert.is_true(GTD.HasGuildedCharactersOnRealm("Other"))
      assert.is_false(GTD.HasGuildedCharactersOnRealm(nil))
      AltArmy.DataStore = savedDS
    end)
  end)

  describe("GetAutoBrowseGuild", function()
    it("returns the sole guild when there is exactly one", function()
      assert.are.equal("Only Guild", GTD.GetAutoBrowseGuild({ "Only Guild" }))
    end)

    it("returns nil when there are zero or multiple guilds", function()
      assert.is_nil(GTD.GetAutoBrowseGuild({}))
      assert.is_nil(GTD.GetAutoBrowseGuild({ "A", "B" }))
      assert.is_nil(GTD.GetAutoBrowseGuild(nil))
    end)
  end)

  describe("FormatRecipeSearchPlaceholder", function()
    it("uses the character name in plain text", function()
      assert.are.equal("Search for recipes on Mindfrell", GTD.FormatRecipeSearchPlaceholder("Mindfrell"))
    end)

    it("falls back when the name is missing", function()
      assert.are.equal("Search for recipes on this character", GTD.FormatRecipeSearchPlaceholder(nil))
    end)
  end)

  describe("FilterRecipesBySearch", function()
    local recipes = {
      { recipeID = 1, name = "Bolt of Silk Cloth" },
      { recipeID = 2, name = "Mooncloth" },
    }

    it("returns all recipes when the query is empty", function()
      assert.are.same(recipes, GTD.FilterRecipesBySearch(recipes, "", function(r) return r.name end))
    end)

    it("filters by case-insensitive substring on the resolved name", function()
      local out = GTD.FilterRecipesBySearch(recipes, "moon", function(r) return r.name end)
      assert.are.same({ { recipeID = 2, name = "Mooncloth" } }, out)
    end)
  end)

  describe("AreRecipeListsEqual", function()
    it("returns true for the same table reference", function()
      local recipes = { { recipeID = 1 } }
      assert.is_true(GTD.AreRecipeListsEqual(recipes, recipes))
    end)

    it("returns true when ordered recipeIDs match despite different table references", function()
      local a = { { recipeID = 10, resultItemID = 1 }, { recipeID = 20 } }
      local b = { { recipeID = 10, resultItemID = 99 }, { recipeID = 20, name = "x" } }
      assert.is_true(GTD.AreRecipeListsEqual(a, b))
    end)

    it("treats numeric-string recipeIDs as equal to numbers", function()
      assert.is_true(GTD.AreRecipeListsEqual(
        { { recipeID = 42 } },
        { { recipeID = "42" } }
      ))
    end)

    it("returns false when lengths differ", function()
      assert.is_false(GTD.AreRecipeListsEqual(
        { { recipeID = 1 } },
        { { recipeID = 1 }, { recipeID = 2 } }
      ))
    end)

    it("returns false when order differs", function()
      assert.is_false(GTD.AreRecipeListsEqual(
        { { recipeID = 1 }, { recipeID = 2 } },
        { { recipeID = 2 }, { recipeID = 1 } }
      ))
    end)

    it("returns false when a recipeID differs", function()
      assert.is_false(GTD.AreRecipeListsEqual(
        { { recipeID = 1 } },
        { { recipeID = 2 } }
      ))
    end)

    it("returns false for nil or non-table inputs", function()
      assert.is_false(GTD.AreRecipeListsEqual(nil, {}))
      assert.is_false(GTD.AreRecipeListsEqual({}, nil))
      assert.is_false(GTD.AreRecipeListsEqual("x", {}))
    end)

    it("returns true for two empty lists", function()
      assert.is_true(GTD.AreRecipeListsEqual({}, {}))
    end)
  end)

  describe("FormatRecipeSkillCell", function()
    local savedRCL

    before_each(function()
      savedRCL = AltArmy.RecipeInfo
    end)

    after_each(function()
      AltArmy.RecipeInfo = savedRCL
    end)

    it("delegates to RecipeInfo when recipe data is loaded", function()
      AltArmy.RecipeInfo = {
        EnrichEntry = function(entry)
          entry.recipeSkillRequired = 180
          entry.difficulty = "yellow"
        end,
        FormatSkillCell = function(req, rank, difficulty)
          return string.format("%d/%d/%s", req, rank, difficulty)
        end,
      }
      local text = GTD.FormatRecipeSkillCell(
        { recipeID = 26751, resultItemID = 21842 },
        "Tailoring",
        375
      )
      assert.are.equal("180/375/yellow", text)
    end)

    it("falls back to skill rank without recipe data", function()
      AltArmy.RecipeInfo = nil
      assert.are.equal("300", GTD.FormatRecipeSkillCell({ recipeID = 1 }, "Alchemy", 300))
    end)

    it("shows em dash when skill rank is zero and recipe data is missing", function()
      AltArmy.RecipeInfo = {
        EnrichEntry = function() end,
        FormatSkillCell = function()
          return "—"
        end,
      }
      assert.are.equal("—", GTD.FormatRecipeSkillCell({ recipeID = 1 }, "Alchemy", 0))
    end)
  end)

  describe("EnrichRecipeEntry", function()
    local savedRCL

    before_each(function()
      savedRCL = AltArmy.RecipeInfo
    end)

    after_each(function()
      AltArmy.RecipeInfo = savedRCL
    end)

    it("surfaces recipe-data-backfilled resultItemID for guild recipe rows", function()
      AltArmy.RecipeInfo = {
        EnrichEntry = function(entry)
          if not entry.resultItemID then
            entry.resultItemID = 6370
          end
        end,
      }
      local enriched = GTD.EnrichRecipeEntry({ recipeID = 7837 }, "Alchemy", 300)
      assert.are.equal(7837, enriched.recipeID)
      assert.are.equal(6370, enriched.resultItemID)
      assert.are.equal("Alchemy", enriched.professionName)
      assert.are.equal(300, enriched.skillRank)
    end)

    it("preserves an existing resultItemID", function()
      AltArmy.RecipeInfo = {
        EnrichEntry = function(entry)
          if not entry.resultItemID then
            entry.resultItemID = 6370
          end
        end,
      }
      local enriched = GTD.EnrichRecipeEntry(
        { recipeID = 7837, resultItemID = 9999 },
        "Alchemy",
        300
      )
      assert.are.equal(9999, enriched.resultItemID)
    end)
  end)

  describe("ResolveRecipeDisplay", function()
    local savedGetItemInfo
    local savedGetItemIcon
    local savedGetItemInfoInstant
    local savedGetSpellInfo

    before_each(function()
      savedGetItemInfo = _G.GetItemInfo
      savedGetItemIcon = _G.GetItemIcon
      savedGetItemInfoInstant = _G.GetItemInfoInstant
      savedGetSpellInfo = _G.GetSpellInfo
      _G.GetItemInfo = nil
      _G.GetItemIcon = nil
      _G.GetItemInfoInstant = nil
      _G.GetSpellInfo = nil
    end)

    after_each(function()
      _G.GetItemInfo = savedGetItemInfo
      _G.GetItemIcon = savedGetItemIcon
      _G.GetItemInfoInstant = savedGetItemInfoInstant
      _G.GetSpellInfo = savedGetSpellInfo
    end)

    it("uses GetItemIcon for result item when GetItemInfo has not cached yet", function()
      _G.GetSpellInfo = function(id)
        if id == 100 then return "Bolt of Silk" end
      end
      _G.GetItemInfo = function()
        return nil
      end
      _G.GetItemIcon = function(id)
        if id == 4306 then return 132905 end
      end
      local name, icon = GTD.ResolveRecipeDisplay(100, 4306)
      assert.are.equal("Bolt of Silk", name)
      assert.are.equal(132905, icon)
    end)

    it("falls back to GetItemInfoInstant icon when GetItemIcon is absent", function()
      _G.GetSpellInfo = function(id)
        if id == 100 then return "Bolt of Silk" end
      end
      _G.GetItemInfo = function() return nil end
      _G.GetItemInfoInstant = function(id)
        if id == 4306 then
          return 4306, "Tradeskill", "Cloth", "", 132905, 7, 5
        end
      end
      local name, icon = GTD.ResolveRecipeDisplay(100, 4306)
      assert.are.equal("Bolt of Silk", name)
      assert.are.equal(132905, icon)
    end)

    it("uses GetItemInfo icon when the item is already cached", function()
      _G.GetSpellInfo = function(id)
        if id == 100 then return "Bolt of Silk" end
      end
      _G.GetItemInfo = function(id)
        if id == 4306 then
          return "Silk Cloth", nil, nil, nil, nil, nil, nil, nil, nil, "Interface\\Icons\\INV_Fabric_Silk_01"
        end
      end
      local name, icon = GTD.ResolveRecipeDisplay(100, 4306)
      assert.are.equal("Bolt of Silk", name)
      assert.are.equal("Interface\\Icons\\INV_Fabric_Silk_01", icon)
    end)

    it("falls back to spell icon when no result item is known", function()
      _G.GetSpellInfo = function(id)
        if id == 100 then return "Bolt of Silk", nil, "Interface\\Icons\\Spell_Nature_Dryad" end
      end
      local name, icon = GTD.ResolveRecipeDisplay(100, nil)
      assert.are.equal("Bolt of Silk", name)
      assert.are.equal("Interface\\Icons\\Spell_Nature_Dryad", icon)
    end)

    it("returns question-mark icon when nothing resolves", function()
      local name, icon = GTD.ResolveRecipeDisplay(999, 888)
      assert.are.equal("Recipe 999", name)
      assert.are.equal("Interface\\Icons\\INV_Misc_QuestionMark", icon)
    end)

    it("reports whether an unresolved item id should be watched for cache arrival", function()
      _G.GetSpellInfo = function(id)
        if id == 100 then return "Bolt of Silk" end
      end
      _G.GetItemInfo = function() return nil end
      local name, icon, pendingItemID = GTD.ResolveRecipeDisplay(100, 4306)
      assert.are.equal("Bolt of Silk", name)
      assert.are.equal("Interface\\Icons\\INV_Misc_QuestionMark", icon)
      assert.are.equal(4306, pendingItemID)
    end)

    it("does not mark pending when an instant icon is already available", function()
      _G.GetSpellInfo = function(id)
        if id == 100 then return "Bolt of Silk" end
      end
      _G.GetItemIcon = function(id)
        if id == 4306 then return 132905 end
      end
      local _, icon, pendingItemID = GTD.ResolveRecipeDisplay(100, 4306)
      assert.are.equal(132905, icon)
      assert.is_nil(pendingItemID)
    end)

    describe("without the legacy GetSpellInfo global (WoW Forever)", function()
      local savedCSpell
      before_each(function()
        savedCSpell = _G.C_Spell
        _G.C_Spell = {
          GetSpellInfo = function(id)
            if id == 2662 then
              return { name = "Copper Chain Pants", iconID = 132535, spellID = 2662 }
            end
          end,
        }
      end)
      after_each(function()
        _G.C_Spell = savedCSpell
      end)

      it("resolves the recipe name via C_Spell instead of misreading the spell id as an item id", function()
        _G.GetItemInfo = function(id)
          if id == 2662 then return "Unrelated Item" end
        end
        local name = GTD.ResolveRecipeDisplay(2662, nil)
        assert.are.equal("Copper Chain Pants", name)
      end)

      it("uses the C_Spell icon when no result item is known", function()
        _G.GetItemIcon = function(id)
          if id == 2662 then return 999999 end
        end
        local _, icon = GTD.ResolveRecipeDisplay(2662, nil)
        assert.are.equal(132535, icon)
      end)
    end)

    it("prefers the scan-time recipe name over any id-based lookup", function()
      _G.GetSpellInfo = function() return "Wrong Spell" end
      _G.GetItemInfo = function() return "Wrong Item" end
      local name = GTD.ResolveRecipeDisplay(100, nil, "Bolt of Silk")
      assert.are.equal("Bolt of Silk", name)
    end)

    it("uses the crafted item's name before guessing the recipe id as an item id", function()
      _G.GetItemInfo = function(id)
        if id == 4306 then return "Silk Cloth" end
        if id == 100 then return "Unrelated Item" end
      end
      local name = GTD.ResolveRecipeDisplay(100, 4306)
      assert.are.equal("Silk Cloth", name)
    end)
  end)

  describe("GetDefaultRecipeSort", function()
    it("defaults to name ascending without recipe data", function()
      local sortKey, ascending = GTD.GetDefaultRecipeSort(false)
      assert.are.equal("recipe", sortKey)
      assert.is_true(ascending)
    end)

    it("defaults to required skill descending with recipe data", function()
      local sortKey, ascending = GTD.GetDefaultRecipeSort(true)
      assert.are.equal("skill", sortKey)
      assert.is_false(ascending)
    end)
  end)

  describe("GetDefaultListSort", function()
    it("defaults to online ascending when roster last-online can be looked up", function()
      local sortKey, ascending = GTD.GetDefaultListSort(true)
      assert.are.equal("online", sortKey)
      assert.is_true(ascending)
    end)

    it("defaults to name ascending when roster last-online cannot be looked up", function()
      local sortKey, ascending = GTD.GetDefaultListSort(false)
      assert.are.equal("name", sortKey)
      assert.is_true(ascending)
    end)
  end)

  describe("SortRecipes", function()
    local savedRCL
    local recipes = {
      { recipeID = 1, name = "Zebra Cloth" },
      { recipeID = 2, name = "Alpha Bolt" },
      { recipeID = 3, name = "Mooncloth" },
    }
    local function nameOf(r)
      return r.name
    end

    before_each(function()
      savedRCL = AltArmy.RecipeInfo
    end)

    after_each(function()
      AltArmy.RecipeInfo = savedRCL
    end)

    it("sorts by recipe name ascending", function()
      local out = GTD.SortRecipes(recipes, "recipe", true, { getRecipeName = nameOf })
      assert.are.equal(2, out[1].recipeID)
      assert.are.equal(3, out[2].recipeID)
      assert.are.equal(1, out[3].recipeID)
    end)

    it("sorts by recipe name descending", function()
      local out = GTD.SortRecipes(recipes, "recipe", false, { getRecipeName = nameOf })
      assert.are.equal(1, out[1].recipeID)
      assert.are.equal(3, out[2].recipeID)
      assert.are.equal(2, out[3].recipeID)
    end)

    it("sorts by required skill ascending with name tiebreaker", function()
      AltArmy.RecipeInfo = {
        EnrichEntry = function(entry)
          if entry.recipeID == 1 then
            entry.recipeSkillRequired = 300
            entry.difficulty = "orange"
          elseif entry.recipeID == 2 then
            entry.recipeSkillRequired = 150
            entry.difficulty = "yellow"
          elseif entry.recipeID == 3 then
            entry.recipeSkillRequired = 300
            entry.difficulty = "green"
          end
        end,
      }
      local out = GTD.SortRecipes(recipes, "skill", true, {
        professionName = "Tailoring",
        skillRank = 375,
        getRecipeName = nameOf,
      })
      assert.are.equal(2, out[1].recipeID)
      assert.are.equal(1, out[2].recipeID)
      assert.are.equal(3, out[3].recipeID)
    end)

    it("sorts by required skill descending with name tiebreaker", function()
      AltArmy.RecipeInfo = {
        EnrichEntry = function(entry)
          if entry.recipeID == 1 then
            entry.recipeSkillRequired = 300
            entry.difficulty = "orange"
          elseif entry.recipeID == 2 then
            entry.recipeSkillRequired = 150
            entry.difficulty = "yellow"
          elseif entry.recipeID == 3 then
            entry.recipeSkillRequired = 300
            entry.difficulty = "green"
          end
        end,
      }
      local out = GTD.SortRecipes(recipes, "skill", false, {
        professionName = "Tailoring",
        skillRank = 375,
        getRecipeName = nameOf,
      })
      assert.are.equal(3, out[1].recipeID)
      assert.are.equal(1, out[2].recipeID)
      assert.are.equal(2, out[3].recipeID)
    end)

    it("treats missing required skill as 0 when sorting by skill", function()
      AltArmy.RecipeInfo = {
        EnrichEntry = function(entry)
          if entry.recipeID == 1 then
            entry.recipeSkillRequired = nil
          elseif entry.recipeID == 2 then
            entry.recipeSkillRequired = 100
          elseif entry.recipeID == 3 then
            entry.recipeSkillRequired = 50
          end
        end,
      }
      local three = {
        { recipeID = 1, name = "Unknown" },
        { recipeID = 2, name = "High" },
        { recipeID = 3, name = "Low" },
      }
      local ascending = GTD.SortRecipes(three, "skill", true, {
        professionName = "Alchemy",
        skillRank = 300,
        getRecipeName = nameOf,
      })
      assert.are.equal(1, ascending[1].recipeID)
      assert.are.equal(3, ascending[2].recipeID)
      assert.are.equal(2, ascending[3].recipeID)

      local descending = GTD.SortRecipes(three, "skill", false, {
        professionName = "Alchemy",
        skillRank = 300,
        getRecipeName = nameOf,
      })
      assert.are.equal(2, descending[1].recipeID)
      assert.are.equal(3, descending[2].recipeID)
      assert.are.equal(1, descending[3].recipeID)
    end)
  end)

  describe("explicit main star", function()
    setup(function()
      _G.RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS or {
        MAGE = { r = 0.41, g = 0.8, b = 0.94 },
        WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
      }
      package.loaded["ClassColor"] = nil
      package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
      require("ClassColor")
    end)

    it("IsExplicitMain is true only for declared mains", function()
      assert.is_true(GTD.IsExplicitMain(member({ name = "Main", isMain = true, mainDeclared = true })))
      assert.is_false(GTD.IsExplicitMain(member({ name = "Main", isMain = true, mainDeclared = false })))
      assert.is_false(GTD.IsExplicitMain(member({ name = "Alt", isMain = false, mainDeclared = true })))
      assert.is_false(GTD.IsExplicitMain(nil))
    end)

    it("FormatMainStarTooltip uses your for own characters", function()
      local text = GTD.FormatMainStarTooltip("Alice", "MAGE", true)
      assert.truthy(text:find("|cff"))
      assert.truthy(text:find("Alice"))
      assert.truthy(text:find(" is your main character$"))
    end)

    it("FormatMainStarTooltip uses their for other players' characters", function()
      local text = GTD.FormatMainStarTooltip("Bob", "WARRIOR", false)
      assert.truthy(text:find("Bob"))
      assert.truthy(text:find(" is their main character$"))
    end)

    it("PresentMainStarTooltip shows title and gray Click to configure hint", function()
      local lines = {}
      local owner = {}
      _G.GameTooltip = {
        SetOwner = function() end,
        ClearLines = function() end,
        AddLine = function(_, text, r, g, b)
          lines[#lines + 1] = { text = text, r = r, g = g, b = b }
        end,
        Show = function() end,
      }
      assert.is_true(GTD.PresentMainStarTooltip(owner, "ANCHOR_BOTTOMLEFT", {
        name = "Alice",
        classFile = "MAGE",
        isOwn = true,
        showConfigureHint = true,
      }))
      assert.truthy(lines[1].text:find("Alice"))
      assert.truthy(lines[1].text:find(" is your main character"))
      assert.are.equal(1, lines[1].r)
      assert.are.equal("Click to configure", lines[2].text)
      assert.are.equal(0.5, lines[2].r)
      assert.are.equal(0.5, lines[2].g)
      assert.are.equal(0.5, lines[2].b)
    end)

    it("PresentMainStarTooltip omits configure hint when not requested", function()
      local lines = {}
      _G.GameTooltip = {
        SetOwner = function() end,
        ClearLines = function() end,
        AddLine = function(_, text)
          lines[#lines + 1] = text
        end,
        Show = function() end,
      }
      assert.is_true(GTD.PresentMainStarTooltip({}, "ANCHOR_BOTTOMLEFT", {
        name = "Bob",
        classFile = "WARRIOR",
        isOwn = false,
      }))
      assert.are.equal(1, #lines)
      assert.truthy(lines[1]:find(" is their main character"))
    end)
  end)

  describe("FormatCharacterName", function()
    it("includes the class-colored name and gray level", function()
      local m = member({ name = "Mage", classFile = "MAGE", level = 70 })
      assert.are.equal("Mage |cff808080(level 70)|r",
        GTD.FormatCharacterName(m, plainFormatName))
    end)

    it("highlights the matching portion of the character name", function()
      local m = member({ name = "Mindfrell", classFile = "MAGE", level = 70 })
      local out = GTD.FormatCharacterName(m, plainFormatName, "frell")
      assert.are.equal("Mind|cff00ff00frell|r |cff808080(level 70)|r", out)
    end)

    it("floors fractional levels", function()
      local m = member({ name = "Odd", level = 42.9 })
      local text = GTD.FormatCharacterName(m, plainFormatName)
      assert.truthy(text:find("(level 42)", 1, true))
    end)
  end)

  describe("notes wizard member row formatting", function()
    it("FormatNotesWizardMemberName class-colors the name and grays the level", function()
      assert.are.equal(
        "Alice |cff808080(level 70)|r",
        GTD.FormatNotesWizardMemberName("Alice", "MAGE", 70, plainFormatName))
    end)

    it("FormatNotesWizardMemberNote returns a white quoted note line", function()
      assert.are.equal(
        '|cffffffff"Alice\'s bank alt"|r',
        GTD.FormatNotesWizardMemberNote("Alice's bank alt"))
    end)

    it("FormatNotesWizardMemberNote escapes pipe sequences in note text", function()
      assert.are.equal(
        '|cffffffff"||cff00ff00Hacked||r"|r',
        GTD.FormatNotesWizardMemberNote("|cff00ff00Hacked|r"))
      assert.are.equal(
        '|cffffffff"||TInterface\\Icons\\INV_Misc_QuestionMark:16||t"|r',
        GTD.FormatNotesWizardMemberNote("|TInterface\\Icons\\INV_Misc_QuestionMark:16|t"))
    end)

    it("FormatNotesWizardMemberNote returns empty when note is missing", function()
      assert.are.equal("", GTD.FormatNotesWizardMemberNote(nil))
      assert.are.equal("", GTD.FormatNotesWizardMemberNote(""))
      assert.are.equal("", GTD.FormatNotesWizardMemberNote("   "))
    end)

    it("FormatNotesWizardMemberNote highlights matching substrings inside white quotes", function()
      assert.are.equal(
        '|cffffffff"|r|cff00ff00bank|r|cffffffff alt|r|cffffffff"|r',
        GTD.FormatNotesWizardMemberNote("bank alt", "bank"))
    end)

    it("FormatNotesWizardMemberAttribution uses text match in guild note for note kind", function()
      assert.are.equal(
        "|cff808080Reason: text match in guild note|r",
        GTD.FormatNotesWizardMemberAttribution("note", "From note: 'Alice alt'"))
    end)

    it("FormatNotesWizardMemberAttribution uses added manually for manual kind", function()
      assert.are.equal(
        "|cff808080Reason: added manually|r",
        GTD.FormatNotesWizardMemberAttribution("manual"))
    end)

    it("FormatNotesWizardMemberAttribution uses the provided shared/referred reason in lowercase start", function()
      assert.are.equal(
        "|cff808080Reason: from Alt Army shared data|r",
        GTD.FormatNotesWizardMemberAttribution("shared", "From Alt Army shared data"))
      assert.are.equal(
        "|cff808080Reason: referred to by other notes|r",
        GTD.FormatNotesWizardMemberAttribution("referred"))
    end)

    it("NotesWizardInclusionReasonLabel returns short column labels", function()
      assert.are.equal("Name in note", GTD.NotesWizardInclusionReasonLabel("note"))
      assert.are.equal("Manually added", GTD.NotesWizardInclusionReasonLabel("manual"))
      assert.are.equal("Shared via Alt Army", GTD.NotesWizardInclusionReasonLabel("shared"))
      assert.are.equal("Referred to by note", GTD.NotesWizardInclusionReasonLabel("main"))
      assert.are.equal("Referred to by note", GTD.NotesWizardInclusionReasonLabel("referred"))
      assert.are.equal("", GTD.NotesWizardInclusionReasonLabel(nil))
      assert.are.equal("", GTD.NotesWizardInclusionReasonLabel("unknown"))
    end)

    it("ClassifyNotesWizardInclusionReason picks kind from row role and provenance", function()
      assert.are.equal("main", GTD.ClassifyNotesWizardInclusionReason({ isMain = true }))
      assert.are.equal("shared", GTD.ClassifyNotesWizardInclusionReason({
        isMain = true, mainFromShared = true,
      }))
      assert.are.equal("shared", GTD.ClassifyNotesWizardInclusionReason({ isKnownShared = true }))
      assert.are.equal("note", GTD.ClassifyNotesWizardInclusionReason({
        noteText = "bob alt",
      }))
      assert.are.equal("note", GTD.ClassifyNotesWizardInclusionReason({
        alreadyMapped = true, origin = "note",
      }))
      assert.are.equal("manual", GTD.ClassifyNotesWizardInclusionReason({
        alreadyMapped = true, origin = "user",
      }))
      assert.are.equal("manual", GTD.ClassifyNotesWizardInclusionReason({}))
      assert.are.equal("manual", GTD.ClassifyNotesWizardInclusionReason({
        isMain = true, origin = "user",
      }))
      assert.are.equal("manual", GTD.ClassifyNotesWizardInclusionReason({
        isMain = true, isManualMember = true,
      }))
      assert.are.equal("main", GTD.ClassifyNotesWizardInclusionReason({
        isMain = true, origin = "note",
      }))
    end)
  end)

  describe("CountNotesProposalCharacters", function()
    it("counts main only as 1", function()
      assert.are.equal(1, GTD.CountNotesProposalCharacters({
        main = "Bob",
        members = {},
      }))
    end)

    it("counts main plus members", function()
      assert.are.equal(3, GTD.CountNotesProposalCharacters({
        main = "Bob",
        members = {
          { name = "Bobsalt" },
          { name = "Bank" },
        },
      }))
    end)

    it("does not double-count a member that is a case-variant of the main", function()
      assert.are.equal(2, GTD.CountNotesProposalCharacters({
        main = "Bob",
        members = {
          { name = "bob" },
          { name = "Bobsalt" },
        },
      }))
    end)

    it("includes knownMembers in the count (Accept enabled with shared-only companions)", function()
      -- Documented: main + only knownMembers enables Accept (writes a redundant anchor).
      assert.are.equal(2, GTD.CountNotesProposalCharacters({
        main = "Bob",
        members = {},
        knownMembers = { { name = "SharedAlt" } },
      }))
    end)

    it("returns 0 for nil or empty proposals", function()
      assert.are.equal(0, GTD.CountNotesProposalCharacters(nil))
      assert.are.equal(0, GTD.CountNotesProposalCharacters({}))
      assert.are.equal(0, GTD.CountNotesProposalCharacters({ main = "" }))
    end)
  end)

  describe("AddManualProposalMember / RemoveManualProposalMember", function()
    it("AddManualProposalMember sets main on first add", function()
      local proposal = { main = nil, members = {}, manual = true }
      local ok = GTD.AddManualProposalMember(proposal, "Bob")
      assert.is_true(ok)
      assert.are.equal("Bob", proposal.main)
      assert.are.equal(0, #proposal.members)
      assert.are.same({ "Bob" }, proposal.order)
    end)

    it("AddManualProposalMember appends subsequent names as manually-added members", function()
      local proposal = { main = "Bob", members = {}, order = { "Bob" }, manual = true }
      local ok = GTD.AddManualProposalMember(proposal, "Bobsalt")
      assert.is_true(ok)
      assert.are.equal(1, #proposal.members)
      assert.are.equal("Bobsalt", proposal.members[1].name)
      assert.is_true(proposal.members[1].addedManually)
      assert.are.same({ "Bob", "Bobsalt" }, proposal.order)
    end)

    it("AddManualProposalMember rejects duplicates and empty names", function()
      local proposal = {
        main = "Bob",
        members = { { name = "Bobsalt", addedManually = true } },
        order = { "Bob", "Bobsalt" },
      }
      assert.is_false(GTD.AddManualProposalMember(proposal, "Bob"))
      assert.is_false(GTD.AddManualProposalMember(proposal, "bobsalt"))
      assert.is_false(GTD.AddManualProposalMember(proposal, ""))
      assert.is_false(GTD.AddManualProposalMember(proposal, nil))
      assert.are.equal(1, #proposal.members)
    end)

    it("RemoveManualProposalMember removes an alt member", function()
      local proposal = {
        main = "Bob",
        members = {
          { name = "Bobsalt", addedManually = true },
          { name = "Bank", addedManually = true },
        },
        order = { "Bob", "Bobsalt", "Bank" },
      }
      local ok = GTD.RemoveManualProposalMember(proposal, "Bobsalt")
      assert.is_true(ok)
      assert.are.equal("Bob", proposal.main)
      assert.are.equal(1, #proposal.members)
      assert.are.equal("Bank", proposal.members[1].name)
      assert.are.same({ "Bob", "Bank" }, proposal.order)
    end)

    it("RemoveManualProposalMember promotes next member when main is removed", function()
      local proposal = {
        main = "Bob",
        members = {
          { name = "Bobsalt", addedManually = true },
          { name = "Bank", addedManually = true },
        },
        order = { "Bob", "Bobsalt", "Bank" },
      }
      local ok = GTD.RemoveManualProposalMember(proposal, "Bob")
      assert.is_true(ok)
      assert.are.equal("Bobsalt", proposal.main)
      assert.are.equal(1, #proposal.members)
      assert.are.equal("Bank", proposal.members[1].name)
      assert.are.same({ "Bobsalt", "Bank" }, proposal.order)
    end)

    it("RemoveManualProposalMember clears main when last character is removed", function()
      local proposal = { main = "Bob", members = {}, order = { "Bob" } }
      local ok = GTD.RemoveManualProposalMember(proposal, "Bob")
      assert.is_true(ok)
      assert.is_nil(proposal.main)
      assert.are.equal(0, #proposal.members)
      assert.are.same({}, proposal.order)
    end)

    it("RemoveManualProposalMember returns false for unknown names", function()
      local proposal = { main = "Bob", members = {}, order = { "Bob" } }
      assert.is_false(GTD.RemoveManualProposalMember(proposal, "Nobody"))
      assert.are.equal("Bob", proposal.main)
    end)

    it("SetManualProposalMain changes main without changing display order", function()
      local proposal = {
        main = "Bob",
        members = {
          { name = "Bobsalt", addedManually = true },
          { name = "Bank", addedManually = true },
        },
        order = { "Bob", "Bobsalt", "Bank" },
      }
      local ok = GTD.SetManualProposalMain(proposal, "Bank")
      assert.is_true(ok)
      assert.are.equal("Bank", proposal.main)
      assert.are.same({ "Bob", "Bobsalt", "Bank" }, proposal.order)
      assert.are.equal(2, #proposal.members)
      assert.are.equal("Bob", proposal.members[1].name)
      assert.are.equal("Bobsalt", proposal.members[2].name)
      assert.are.same(
        { "Bob", "Bobsalt", "Bank" },
        GTD.ManualProposalDisplayOrder(proposal))
    end)

    it("SetManualProposalMain is a no-op success when name is already main", function()
      local proposal = {
        main = "Bob",
        members = { { name = "Bobsalt", addedManually = true } },
        order = { "Bob", "Bobsalt" },
      }
      assert.is_true(GTD.SetManualProposalMain(proposal, "Bob"))
      assert.are.equal("Bob", proposal.main)
      assert.are.equal(1, #proposal.members)
      assert.are.equal("Bobsalt", proposal.members[1].name)
      assert.are.same({ "Bob", "Bobsalt" }, proposal.order)
    end)

    it("SetManualProposalMain returns false for unknown or empty names", function()
      local proposal = {
        main = "Bob",
        members = { { name = "Bobsalt", addedManually = true } },
        order = { "Bob", "Bobsalt" },
      }
      assert.is_false(GTD.SetManualProposalMain(proposal, "Nobody"))
      assert.is_false(GTD.SetManualProposalMain(proposal, ""))
      assert.is_false(GTD.SetManualProposalMain(proposal, nil))
      assert.are.equal("Bob", proposal.main)
    end)

    it("ManualProposalDisplayOrder synthesizes order from main+members when missing", function()
      local proposal = {
        main = "Bob",
        members = { { name = "Bobsalt", addedManually = true } },
      }
      assert.are.same({ "Bob", "Bobsalt" }, GTD.ManualProposalDisplayOrder(proposal))
      assert.are.same({ "Bob", "Bobsalt" }, proposal.order)
    end)
  end)
  describe("GetProfessionIcon", function()
    local savedGetSpellInfo, savedCSpell

    before_each(function()
      savedGetSpellInfo, savedCSpell = _G.GetSpellInfo, _G.C_Spell
      _G.GetSpellInfo, _G.C_Spell = nil, nil
    end)

    after_each(function()
      _G.GetSpellInfo, _G.C_Spell = savedGetSpellInfo, savedCSpell
    end)

    it("uses the profession spell's icon via C_Spell (WoW Forever)", function()
      _G.C_Spell = {
        GetSpellInfo = function(id)
          if id == 2259 then return { name = "Alchemy", iconID = 4620669 } end
        end,
      }
      assert.are.equal(4620669, GTD.GetProfessionIcon("alchemy"))
    end)

    it("uses the legacy GetSpellInfo icon when present", function()
      _G.GetSpellInfo = function(id)
        if id == 8613 then return "Skinning", nil, 134366 end
      end
      assert.are.equal(134366, GTD.GetProfessionIcon("skinning"))
    end)

    it("falls back to a static texture when the spell does not resolve", function()
      assert.are.equal("Interface\\Icons\\Trade_Tailoring", GTD.GetProfessionIcon("tailoring"))
    end)

    it("returns the question mark for unknown keys", function()
      assert.are.equal("Interface\\Icons\\INV_Misc_QuestionMark", GTD.GetProfessionIcon("fishing"))
      assert.are.equal("Interface\\Icons\\INV_Misc_QuestionMark", GTD.GetProfessionIcon(nil))
    end)
  end)
end)
