--[[
  Unit tests for GuildShareSettings.lua (guild data sharing: send-side privacy).
  Run from project root: npm test
]]

describe("GuildShareSettings", function()
  local GSS

  local function setChars(realm, chars)
    AltArmyTBC_Data.Characters[realm] = chars
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.CreateFrame = _G.CreateFrame or function()
      return { SetScript = function() end, RegisterEvent = function() end }
    end
    _G.UIParent = _G.UIParent or {}
    _G.time = _G.time or function() return 1700000000 end
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    _G.AltArmyTBC_Data = { Characters = {} }
    require("CharKey")
    require("DataStore")
    require("DataStoreCharacter")
    require("GuildShareSettings")
    GSS = AltArmy.GuildShareSettings
    assert.truthy(GSS)
  end)

  before_each(function()
    _G.AltArmyTBC_SharingSettings = nil
    _G.AltArmyTBC_Data = { Characters = {} }
    AltArmy.DataStore.accountData = _G.AltArmyTBC_Data
    AltArmy.DB = _G.AltArmyTBC_Data
    _G.ChatTypeInfo = nil
    _G.SetChatColorNameByClass = nil
    _G.SetCVar = nil
  end)

  describe("defaults", function()
    it("sharing is disabled by default (opt-in)", function()
      assert.is_false(GSS.IsSharingEnabled())
    end)
    it("exposes a tooltip for controls that require sharing to be on", function()
      assert.truthy(GSS.SHARING_REQUIRED_CONTROL_TOOLTIP)
      assert.matches("guild sharing", GSS.SHARING_REQUIRED_CONTROL_TOOLTIP:lower())
    end)

    it("PresentSharingRequiredTooltip can include a gray Click to configure hint", function()
      local lines = {}
      local owner = {}
      _G.GameTooltip = {
        SetOwner = function(_, o, anchor)
          owner.frame = o
          owner.anchor = anchor
        end,
        ClearLines = function() lines = {} end,
        AddLine = function(_, text, r, g, b)
          lines[#lines + 1] = { text = text, r = r, g = g, b = b }
        end,
        Show = function() end,
      }
      assert.is_true(GSS.PresentSharingRequiredTooltip({}, "ANCHOR_RIGHT", {
        showConfigureHint = true,
      }))
      assert.are.equal(2, #lines)
      assert.are.equal(GSS.SHARING_REQUIRED_CONTROL_TOOLTIP, lines[1].text)
      assert.are.equal("Click to configure", lines[2].text)
      assert.are.equal(0.5, lines[2].r)
      assert.are.equal(0.5, lines[2].g)
      assert.are.equal(0.5, lines[2].b)

      assert.is_true(GSS.PresentSharingRequiredTooltip({}, "ANCHOR_RIGHT", {}))
      assert.are.equal(1, #lines)
      assert.are.equal(GSS.SHARING_REQUIRED_CONTROL_TOOLTIP, lines[1].text)
    end)
    it("chat insertion defaults to enabled", function()
      assert.is_true(GSS.IsChatInsertionEnabled())
    end)
    it("auto-delete old data defaults to enabled", function()
      assert.is_true(GSS.IsAutoDeleteOldDataEnabled())
    end)
    it("auto-delete prune age is 180 days", function()
      assert.are.equal(60 * 60 * 24 * 180, GSS.AUTO_DELETE_MAX_AGE_SEC)
    end)
    it("exposes a tooltip explaining 6-month auto-deletion of shared data", function()
      assert.truthy(GSS.AUTO_DELETE_OLD_DATA_TOOLTIP)
      assert.matches("6 months", GSS.AUTO_DELETE_OLD_DATA_TOOLTIP:lower())
      assert.matches("shared by others", GSS.AUTO_DELETE_OLD_DATA_TOOLTIP:lower())
    end)
    it("chat insertion class color defaults from Blizzard channel majority", function()
      _G.ChatTypeInfo = {
        SAY = { colorNameByClass = true },
        YELL = { colorNameByClass = true },
        EMOTE = { colorNameByClass = true },
        GUILD = { colorNameByClass = true },
        PARTY = { colorNameByClass = false },
        RAID = { colorNameByClass = false },
        INSTANCE_CHAT = { colorNameByClass = false },
        WHISPER = { colorNameByClass = false },
      }
      assert.is_true(GSS.ShouldDefaultChatInsertionClassColorEnabled())
      assert.is_true(GSS.IsChatInsertionClassColorEnabled())

      _G.AltArmyTBC_SharingSettings = nil
      _G.ChatTypeInfo = {
        SAY = { colorNameByClass = true },
        YELL = { colorNameByClass = true },
        EMOTE = { colorNameByClass = true },
        GUILD = { colorNameByClass = false },
        PARTY = { colorNameByClass = false },
        RAID = { colorNameByClass = false },
        INSTANCE_CHAT = { colorNameByClass = false },
        WHISPER = { colorNameByClass = false },
      }
      assert.is_false(GSS.ShouldDefaultChatInsertionClassColorEnabled())
      assert.is_false(GSS.IsChatInsertionClassColorEnabled())
    end)
    it("chat insertion channels default to all enabled", function()
      local channels = GSS.GetChatInsertionChannels()
      assert.is_true(channels.say)
      assert.is_true(channels.yell)
      assert.is_true(channels.emote)
      assert.is_true(channels.guild)
      assert.is_true(channels.party)
      assert.is_true(channels.raid)
      assert.is_true(channels.battleground)
      assert.is_true(channels.whisper)
    end)
    it("main, display name, opt-out, onboarding default to empty/false", function()
      assert.is_nil(GSS.GetMain("R"))
      assert.is_nil(GSS.GetDisplayName("R"))
      assert.is_false(GSS.IsCharacterOptedOut("Bob", "R"))
      assert.is_false(GSS.IsOnboardingCompleted("R"))
      assert.is_false(GSS.IsNonGuildedOptedIn("Bob", "R"))
    end)
  end)

  describe("setters persist", function()
    it("SetSharingEnabled", function()
      GSS.SetSharingEnabled(true)
      assert.is_true(GSS.IsSharingEnabled())
      assert.is_true(AltArmyTBC_SharingSettings.enabled)
    end)
    it("SetMain / SetDisplayName per realm", function()
      GSS.SetMain("R", "Bob")
      GSS.SetDisplayName("R", "Bobby")
      assert.are.equal("Bob", GSS.GetMain("R"))
      assert.are.equal("Bobby", GSS.GetDisplayName("R"))
    end)
    it("IsConfiguredMain is true only for the realm's saved main", function()
      assert.is_false(GSS.IsConfiguredMain("Bob", "R"))
      GSS.SetMain("R", "Bob")
      assert.is_true(GSS.IsConfiguredMain("Bob", "R"))
      assert.is_false(GSS.IsConfiguredMain("Alice", "R"))
      assert.is_false(GSS.IsConfiguredMain("Bob", "Other"))
      assert.is_false(GSS.IsConfiguredMain(nil, "R"))
      assert.is_false(GSS.IsConfiguredMain("", "R"))
    end)
    it("SetDisplayName truncates to DISPLAY_NAME_MAX_LENGTH", function()
      local longName = string.rep("x", GSS.DISPLAY_NAME_MAX_LENGTH + 5)
      GSS.SetDisplayName("R", longName)
      assert.are.equal(GSS.DISPLAY_NAME_MAX_LENGTH, #GSS.GetDisplayName("R"))
      assert.are.equal(string.rep("x", GSS.DISPLAY_NAME_MAX_LENGTH), GSS.GetDisplayName("R"))
    end)
    it("NormalizeDisplayName returns nil for empty input", function()
      assert.is_nil(GSS.NormalizeDisplayName(nil))
      assert.is_nil(GSS.NormalizeDisplayName(""))
    end)
    it("ShouldSyncDisplayNameWithMain when preferred still matches main (case-insensitive)", function()
      assert.is_true(GSS.ShouldSyncDisplayNameWithMain("Bob", "Bob"))
      assert.is_true(GSS.ShouldSyncDisplayNameWithMain("Bob", "bob"))
      assert.is_true(GSS.ShouldSyncDisplayNameWithMain("BOB", "Bob"))
    end)
    it("ShouldSyncDisplayNameWithMain when preferred is empty (nothing custom to keep)", function()
      assert.is_true(GSS.ShouldSyncDisplayNameWithMain("Bob", nil))
      assert.is_true(GSS.ShouldSyncDisplayNameWithMain("Bob", ""))
      assert.is_true(GSS.ShouldSyncDisplayNameWithMain(nil, nil))
    end)
    it("ShouldSyncDisplayNameWithMain is false when preferred differs from main", function()
      assert.is_false(GSS.ShouldSyncDisplayNameWithMain("Bob", "Chief"))
      assert.is_false(GSS.ShouldSyncDisplayNameWithMain("Bob", "Bobby"))
      assert.is_false(GSS.ShouldSyncDisplayNameWithMain(nil, "Chief"))
    end)
    it("FirstName returns the first space-separated word", function()
      assert.are.equal("Bob", GSS.FirstName("Bob Smith"))
      assert.are.equal("Bob", GSS.FirstName("Bob"))
      assert.are.equal("", GSS.FirstName(""))
      assert.is_nil(GSS.FirstName(nil))
    end)
    it("ShouldSyncDisplayNameWithMain matches a WoW Forever main's first name (case-insensitive)", function()
      assert.is_true(GSS.ShouldSyncDisplayNameWithMain("Bob Smith", "Bob"))
      assert.is_true(GSS.ShouldSyncDisplayNameWithMain("Bob Smith", "bob"))
      assert.is_false(GSS.ShouldSyncDisplayNameWithMain("Bob Smith", "Smith"))
    end)
    it("ShouldSyncDisplayNameWithMain matches any realm character's full or first name", function()
      local chars = { ["Alice Jones"] = {}, Carl = {}, ["Bob Smith"] = {} }
      assert.is_true(GSS.ShouldSyncDisplayNameWithMain("Bob Smith", "Alice", chars))
      assert.is_true(GSS.ShouldSyncDisplayNameWithMain("Bob Smith", "Alice Jones", chars))
      assert.is_true(GSS.ShouldSyncDisplayNameWithMain("Bob Smith", "Carl", chars))
      assert.is_true(GSS.ShouldSyncDisplayNameWithMain(nil, "carl", chars))
      assert.is_true(GSS.ShouldSyncDisplayNameWithMain("Bob Smith", "Bob Smith", chars))
    end)
    it("ShouldSyncDisplayNameWithMain keeps a custom name that matches no character", function()
      local chars = { ["Alice Jones"] = {}, Carl = {} }
      assert.is_false(GSS.ShouldSyncDisplayNameWithMain("Carl", "Chief", chars))
      assert.is_false(GSS.ShouldSyncDisplayNameWithMain("Carl", "Jones", chars))
      assert.is_false(GSS.ShouldSyncDisplayNameWithMain("Carl", "Ali", chars))
    end)
    it("SetCharacterOptedOut", function()
      GSS.SetCharacterOptedOut("Bob", "R", true)
      assert.is_true(GSS.IsCharacterOptedOut("Bob", "R"))
      GSS.SetCharacterOptedOut("Bob", "R", false)
      assert.is_false(GSS.IsCharacterOptedOut("Bob", "R"))
    end)
    it("SetNonGuildedOptIn stores a guild, cleared with nil", function()
      GSS.SetNonGuildedOptIn("Alt", "R", "The Guild")
      assert.is_true(GSS.IsNonGuildedOptedIn("Alt", "R"))
      assert.are.equal("The Guild", GSS.GetNonGuildedOptInGuild("Alt", "R"))
      GSS.SetNonGuildedOptIn("Alt", "R", nil)
      assert.is_false(GSS.IsNonGuildedOptedIn("Alt", "R"))
    end)
    it("SetChatInsertionEnabled / SetOnboardingCompleted", function()
      GSS.SetChatInsertionEnabled(false)
      assert.is_false(GSS.IsChatInsertionEnabled())
      GSS.SetOnboardingCompleted("R", true)
      assert.is_true(GSS.IsOnboardingCompleted("R"))
    end)
    it("SetAutoDeleteOldDataEnabled persists", function()
      GSS.SetAutoDeleteOldDataEnabled(false)
      assert.is_false(GSS.IsAutoDeleteOldDataEnabled())
      assert.is_false(AltArmyTBC_SharingSettings.autoDeleteOldData)
      GSS.SetAutoDeleteOldDataEnabled(true)
      assert.is_true(GSS.IsAutoDeleteOldDataEnabled())
      assert.is_true(AltArmyTBC_SharingSettings.autoDeleteOldData)
    end)
    it("does not reset a saved auto-delete off value", function()
      _G.AltArmyTBC_SharingSettings = { autoDeleteOldData = false }
      assert.is_false(GSS.IsAutoDeleteOldDataEnabled())
    end)
    it("SetChatInsertionClassColorEnabled", function()
      GSS.SetChatInsertionClassColorEnabled(false)
      assert.is_false(GSS.IsChatInsertionClassColorEnabled())
      GSS.SetChatInsertionClassColorEnabled(true)
      assert.is_true(GSS.IsChatInsertionClassColorEnabled())
    end)
    it("SetChatInsertionClassColorEnabled(true) sets chatClassColorOverride to respect per-channel", function()
      local calls = {}
      _G.SetCVar = function(name, value)
        calls[#calls + 1] = { name = name, value = value }
      end
      GSS.SetChatInsertionClassColorEnabled(true)
      assert.equals(1, #calls)
      assert.equals("chatClassColorOverride", calls[1].name)
      assert.equals("2", calls[1].value)
    end)
    it("SetChatInsertionClassColorEnabled(false) does not change chatClassColorOverride", function()
      local calls = {}
      _G.SetCVar = function(name, value)
        calls[#calls + 1] = { name = name, value = value }
      end
      GSS.SetChatInsertionClassColorEnabled(false)
      assert.equals(0, #calls)
    end)
    it("SetChatInsertionClassColorEnabled syncs Blizzard class color for enabled channels", function()
      local calls = {}
      _G.SetChatColorNameByClass = function(chatType, on)
        calls[#calls + 1] = { chatType = chatType, on = on }
      end
      _G.ChatTypeInfo = {
        GUILD = {}, PARTY = {}, PARTY_LEADER = {},
        RAID = {}, RAID_LEADER = {}, WHISPER = {},
      }
      GSS.SetChatInsertionClassColorEnabled(true)
      local byType = {}
      for _, c in ipairs(calls) do byType[c.chatType] = c.on end
      assert.is_true(byType.SAY)
      assert.is_true(byType.YELL)
      assert.is_true(byType.EMOTE)
      assert.is_true(byType.GUILD)
      assert.is_true(byType.OFFICER)
      assert.is_true(byType.PARTY)
      assert.is_true(byType.PARTY_LEADER)
      assert.is_true(byType.RAID)
      assert.is_true(byType.RAID_LEADER)
      assert.is_true(byType.INSTANCE_CHAT)
      assert.is_true(byType.INSTANCE_CHAT_LEADER)
      assert.is_true(byType.BATTLEGROUND)
      assert.is_true(byType.BATTLEGROUND_LEADER)
      assert.is_true(byType.WHISPER)

      calls = {}
      GSS.SetChatInsertionClassColorEnabled(false)
      byType = {}
      for _, c in ipairs(calls) do byType[c.chatType] = c.on end
      assert.is_false(byType.SAY)
      assert.is_false(byType.YELL)
      assert.is_false(byType.EMOTE)
      assert.is_false(byType.INSTANCE_CHAT)
      assert.is_false(byType.GUILD)
      assert.is_false(byType.PARTY)
      assert.is_false(byType.WHISPER)
    end)
    it("disables Blizzard class color for channels turned off in the dropdown", function()
      local calls = {}
      _G.SetChatColorNameByClass = function(chatType, on)
        calls[#calls + 1] = { chatType = chatType, on = on }
      end
      GSS.SetChatInsertionClassColorEnabled(true)
      calls = {}
      GSS.SetChatInsertionChannelEnabled("party", false)
      local byType = {}
      for _, c in ipairs(calls) do byType[c.chatType] = c.on end
      assert.is_false(byType.PARTY)
      assert.is_false(byType.PARTY_LEADER)
      assert.is_true(byType.SAY)
      assert.is_true(byType.GUILD)
      assert.is_true(byType.WHISPER)

      calls = {}
      GSS.SetChatInsertionChannelEnabled("party", true)
      byType = {}
      for _, c in ipairs(calls) do byType[c.chatType] = c.on end
      assert.is_true(byType.PARTY)
      assert.is_true(byType.PARTY_LEADER)
    end)
    it("ApplyStoredChatClassColorToBlizzard no-ops when setting is unset", function()
      local cvarCalls = {}
      local chatCalls = {}
      _G.SetCVar = function(name, value)
        cvarCalls[#cvarCalls + 1] = { name = name, value = value }
      end
      _G.SetChatColorNameByClass = function(chatType, on)
        chatCalls[#chatCalls + 1] = { chatType = chatType, on = on }
      end
      assert.is_false(GSS.ApplyStoredChatClassColorToBlizzard())
      assert.equals(0, #cvarCalls)
      assert.equals(0, #chatCalls)
      assert.is_nil(AltArmyTBC_SharingSettings.chatInsertionClassColor)
    end)
    it("ApplyStoredChatClassColorToBlizzard syncs when setting is true", function()
      local cvarCalls = {}
      local chatCalls = {}
      _G.SetCVar = function(name, value)
        cvarCalls[#cvarCalls + 1] = { name = name, value = value }
      end
      _G.SetChatColorNameByClass = function(chatType, on)
        chatCalls[#chatCalls + 1] = { chatType = chatType, on = on }
      end
      _G.AltArmyTBC_SharingSettings = { chatInsertionClassColor = true, chatInsertionChannels = {} }
      assert.is_true(GSS.ApplyStoredChatClassColorToBlizzard())
      assert.equals(1, #cvarCalls)
      assert.equals("chatClassColorOverride", cvarCalls[1].name)
      assert.equals("2", cvarCalls[1].value)
      assert.is_true(#chatCalls > 0)
      local byType = {}
      for _, c in ipairs(chatCalls) do byType[c.chatType] = c.on end
      assert.is_true(byType.GUILD)
    end)
    it("ApplyStoredChatClassColorToBlizzard syncs off without clearing override CVar", function()
      local cvarCalls = {}
      local chatCalls = {}
      _G.SetCVar = function(name, value)
        cvarCalls[#cvarCalls + 1] = { name = name, value = value }
      end
      _G.SetChatColorNameByClass = function(chatType, on)
        chatCalls[#chatCalls + 1] = { chatType = chatType, on = on }
      end
      _G.AltArmyTBC_SharingSettings = { chatInsertionClassColor = false, chatInsertionChannels = {} }
      assert.is_true(GSS.ApplyStoredChatClassColorToBlizzard())
      assert.equals(0, #cvarCalls)
      assert.is_true(#chatCalls > 0)
      local byType = {}
      for _, c in ipairs(chatCalls) do byType[c.chatType] = c.on end
      assert.is_false(byType.GUILD)
    end)
  end)

  describe("GetAllGuildedCharacters (flag OFF default set)", function()
    it("returns every character in the guild, ignoring settings", function()
      setChars("R", {
        Main = { name = "Main", realm = "R", guildName = "G" },
        Alt = { name = "Alt", realm = "R", guildName = "G" },
        Other = { name = "Other", realm = "R", guildName = "Different" },
        NoGuild = { name = "NoGuild", realm = "R" },
      })
      -- Even when sharing is off and a char is opted out, all guilded are returned.
      GSS.SetSharingEnabled(false)
      GSS.SetCharacterOptedOut("Alt", "R", true)
      local list = GSS.GetAllGuildedCharacters("G", "R")
      local names = {}
      for _, e in ipairs(list) do names[e.name] = true end
      assert.is_true(names.Main)
      assert.is_true(names.Alt)
      assert.is_nil(names.Other)
      assert.is_nil(names.NoGuild)
    end)
    it("returns empty when guild is nil", function()
      setChars("R", { Main = { name = "Main", realm = "R", guildName = "G" } })
      assert.are.equal(0, #GSS.GetAllGuildedCharacters(nil, "R"))
    end)
  end)

  describe("GetShareableCharacters (flag ON opt-in set)", function()
    it("is empty when sharing is disabled", function()
      setChars("R", { Main = { name = "Main", realm = "R", guildName = "G" } })
      GSS.SetSharingEnabled(false)
      assert.are.equal(0, #GSS.GetShareableCharacters("G", "R"))
    end)
    it("returns guilded chars not opted out when enabled", function()
      setChars("R", {
        Main = { name = "Main", realm = "R", guildName = "G" },
        Alt = { name = "Alt", realm = "R", guildName = "G" },
        Other = { name = "Other", realm = "R", guildName = "Different" },
      })
      GSS.SetSharingEnabled(true)
      GSS.SetCharacterOptedOut("Alt", "R", true)
      local list = GSS.GetShareableCharacters("G", "R")
      local names = {}
      for _, e in ipairs(list) do names[e.name] = true end
      assert.is_true(names.Main)
      assert.is_nil(names.Alt)
      assert.is_nil(names.Other)
    end)
    it("includes non-guilded characters opted in to this guild", function()
      setChars("R", {
        Main = { name = "Main", realm = "R", guildName = "G" },
        Bank = { name = "Bank", realm = "R" },
        Bank2 = { name = "Bank2", realm = "R" },
      })
      GSS.SetSharingEnabled(true)
      GSS.SetNonGuildedOptIn("Bank", "R", "G")
      GSS.SetNonGuildedOptIn("Bank2", "R", "OtherGuild")
      local list = GSS.GetShareableCharacters("G", "R")
      local names = {}
      for _, e in ipairs(list) do names[e.name] = true end
      assert.is_true(names.Main)
      assert.is_true(names.Bank)
      assert.is_nil(names.Bank2)
    end)
  end)

  describe("GUID-keyed characters", function()
    it("reports the stored full name, not the storage key", function()
      setChars("R", {
        ["Player-1-A"] = { name = "Frell Ofelements", guid = "Player-1-A", realm = "R", guildName = "G" },
        ["Player-1-B"] = { name = "Frell Blast", guid = "Player-1-B", realm = "R" },
      })
      GSS.SetSharingEnabled(true)
      GSS.SetNonGuildedOptIn("Frell Blast", "R", "G")
      local names = {}
      for _, e in ipairs(GSS.GetShareableCharacters("G", "R")) do names[e.name] = true end
      assert.are.same({ ["Frell Ofelements"] = true, ["Frell Blast"] = true }, names)
      local all = GSS.GetAllGuildedCharacters("G", "R")
      assert.are.equal("Frell Ofelements", all[1].name)
    end)

    it("neither lists nor shares a pre-v3 first-name copy of a character", function()
      setChars("R", {
        ["Player-1-B"] = { name = "Not Kaiborn", guid = "Player-1-B", realm = "R", guildName = "G",
          classFile = "SHAMAN", level = 14 },
        Not = { name = "Not", realm = "R", guildName = "G", classFile = "SHAMAN", level = 9 },
        Nason = { name = "Nason", realm = "R", guildName = "G", classFile = "MAGE", level = 6 },
      })
      GSS.SetSharingEnabled(true)
      for _, list in ipairs({ GSS.GetShareableCharacters("G", "R"), GSS.GetAllGuildedCharacters("G", "R") }) do
        local names = {}
        for _, e in ipairs(list) do names[e.name] = true end
        assert.are.same({ ["Not Kaiborn"] = true, Nason = true }, names)
      end
    end)

    it("syncs the display name against stored names", function()
      local chars = { ["Player-1-A"] = { name = "Frell Ofelements" } }
      assert.is_true(GSS.ShouldSyncDisplayNameWithMain("Other", "Frell", chars))
      assert.is_false(GSS.ShouldSyncDisplayNameWithMain("Other", "Player-1-A", chars))
    end)
  end)

  describe("RenameCharacter", function()
    it("moves main, opt-out and non-guilded opt-in to the new name", function()
      GSS.SetMain("R", "Frell")
      GSS.SetCharacterOptedOut("Frell", "R", true)
      GSS.SetNonGuildedOptIn("Frell", "R", "G")
      GSS.SetMain("Other", "Frell")
      GSS.RenameCharacter("R", "Frell", "Frell Blast")
      assert.are.equal("Frell Blast", GSS.GetMain("R"))
      assert.are.equal("Frell", GSS.GetMain("Other"))
      assert.is_true(GSS.IsCharacterOptedOut("Frell Blast", "R"))
      assert.is_false(GSS.IsCharacterOptedOut("Frell", "R"))
      assert.are.equal("G", GSS.GetNonGuildedOptInGuild("Frell Blast", "R"))
      assert.is_nil(GSS.GetNonGuildedOptInGuild("Frell", "R"))
    end)

    it("keeps settings already saved under the new name", function()
      GSS.SetNonGuildedOptIn("Frell", "R", "Old")
      GSS.SetNonGuildedOptIn("Frell Blast", "R", "New")
      GSS.RenameCharacter("R", "Frell", "Frell Blast")
      assert.are.equal("New", GSS.GetNonGuildedOptInGuild("Frell Blast", "R"))
    end)
  end)

  describe("chat insertion channels", function()
    it("SetChatInsertionChannelEnabled toggles individual channels", function()
      GSS.SetChatInsertionChannelEnabled("party", false)
      assert.is_false(GSS.IsChatInsertionChannelEnabled("party"))
      assert.is_true(GSS.IsChatInsertionChannelEnabled("guild"))
    end)

    it("FormatChatInsertionChannelSummary lists every enabled channel", function()
      local summary = GSS.FormatChatInsertionChannelSummary(
        GSS.CHAT_INSERTION_CHANNEL_ORDER,
        GSS.CHAT_INSERTION_CHANNEL_LABELS,
        GSS.GetChatInsertionChannels()
      )
      assert.is_true(summary:find("Guild", 1, true) ~= nil, summary)
      assert.is_true(summary:find("Party", 1, true) ~= nil, summary)
      assert.is_true(summary:find("Raid", 1, true) ~= nil, summary)
      assert.is_true(summary:find("Whisper", 1, true) ~= nil, summary)
    end)

    it("FormatChatInsertionChannelSummary lists enabled channel labels", function()
      GSS.SetChatInsertionChannelEnabled("guild", true)
      GSS.SetChatInsertionChannelEnabled("party", false)
      GSS.SetChatInsertionChannelEnabled("raid", false)
      GSS.SetChatInsertionChannelEnabled("whisper", true)
      local summary = GSS.FormatChatInsertionChannelSummary(
        GSS.CHAT_INSERTION_CHANNEL_ORDER,
        GSS.CHAT_INSERTION_CHANNEL_LABELS,
        GSS.GetChatInsertionChannels()
      )
      assert.is_true(summary:find("Guild", 1, true) ~= nil, summary)
      assert.is_true(summary:find("Whisper", 1, true) ~= nil, summary)
      assert.is_nil(summary:find("Party", 1, true))
    end)

    it("FormatChatInsertionChannelSummary keeps short single-word labels", function()
      local summary = GSS.FormatChatInsertionChannelSummary(
        { "guild", "party" },
        GSS.CHAT_INSERTION_CHANNEL_LABELS,
        { guild = true, party = true }
      )
      assert.is_nil(summary:find("Officer", 1, true), summary)
      assert.is_nil(summary:find("Party Leader", 1, true), summary)
      assert.is_nil(summary:find(" / ", 1, true), summary)
      assert.is_true(summary:find("Guild", 1, true) ~= nil, summary)
      assert.is_true(summary:find("Party", 1, true) ~= nil, summary)
    end)

    it("FormatChatInsertionChannelDetailLabel lists all affected channels", function()
      local function stripColor(s)
        return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
      end
      assert.equals("Guild / Officer", stripColor(GSS.FormatChatInsertionChannelDetailLabel("guild")))
      assert.equals("Party / Party Leader", stripColor(GSS.FormatChatInsertionChannelDetailLabel("party")))
      assert.equals("Raid / Raid Leader", stripColor(GSS.FormatChatInsertionChannelDetailLabel("raid")))
      assert.equals(
        "Battleground / Battleground Leader",
        stripColor(GSS.FormatChatInsertionChannelDetailLabel("battleground"))
      )
      assert.equals("Say", stripColor(GSS.FormatChatInsertionChannelDetailLabel("say")))
    end)

    it("FormatChatInsertionChannelDetailLabel colors each channel word", function()
      package.loaded["ClassColor"] = nil
      require("ClassColor")
      local CC = AltArmy.ClassColor
      local guildColor = GSS.CHAT_INSERTION_CHANNEL_COLORS.guild
      local officerColor = GSS.CHAT_INSERTION_CHANNEL_COLORS.officer
      local expected = CC.formatHex(guildColor[1], guildColor[2], guildColor[3], "Guild")
        .. " / "
        .. CC.formatHex(officerColor[1], officerColor[2], officerColor[3], "Officer")
      assert.equals(expected, GSS.FormatChatInsertionChannelDetailLabel("guild"))
    end)

    it("CHAT_INSERTION_CHANNEL_COLORS match Blizzard defaults", function()
      local function assertRgb(key, r, g, b)
        local c = GSS.CHAT_INSERTION_CHANNEL_COLORS[key]
        assert.truthy(c, key)
        assert.is_true(math.abs(c[1] - r) < 1e-6, key .. " r")
        assert.is_true(math.abs(c[2] - g) < 1e-6, key .. " g")
        assert.is_true(math.abs(c[3] - b) < 1e-6, key .. " b")
      end
      assertRgb("say", 1, 1, 1)
      assertRgb("yell", 255 / 255, 64 / 255, 64 / 255)
      assertRgb("emote", 255 / 255, 128 / 255, 64 / 255)
      assertRgb("guild", 64 / 255, 255 / 255, 64 / 255)
      assertRgb("officer", 64 / 255, 192 / 255, 64 / 255)
      assertRgb("party", 170 / 255, 170 / 255, 255 / 255)
      assertRgb("partyLeader", 118 / 255, 200 / 255, 255 / 255)
      assertRgb("raid", 255 / 255, 127 / 255, 0)
      assertRgb("raidLeader", 255 / 255, 72 / 255, 9 / 255)
      assertRgb("battleground", 255 / 255, 127 / 255, 0)
      assertRgb("battlegroundLeader", 255 / 255, 72 / 255, 9 / 255)
      assertRgb("whisper", 255 / 255, 128 / 255, 255 / 255)
    end)

    it("FormatChatInsertionChannelDetailLabel uses distinct leader colors", function()
      package.loaded["ClassColor"] = nil
      require("ClassColor")
      local CC = AltArmy.ClassColor
      local colors = GSS.CHAT_INSERTION_CHANNEL_COLORS
      local expected = CC.formatHex(colors.party[1], colors.party[2], colors.party[3], "Party")
        .. " / "
        .. CC.formatHex(
          colors.partyLeader[1], colors.partyLeader[2], colors.partyLeader[3], "Party Leader"
        )
      assert.equals(expected, GSS.FormatChatInsertionChannelDetailLabel("party"))
    end)
  end)

  describe("EnsureDefaultMainIfMissing", function()
    it("sets the top-ranked character when no main is saved", function()
      setChars("R", {
        Alt = { name = "Alt", realm = "R", level = 40, classFile = "MAGE" },
        Main = { name = "Main", realm = "R", level = 70, classFile = "WARRIOR" },
      })
      AltArmy.GuildShareOnboarding = AltArmy.GuildShareOnboarding or {}
      local GSO = AltArmy.GuildShareOnboarding
      local origBuild = GSO.BuildRealmCharEntries
      GSO.BuildRealmCharEntries = function(chars)
        return {
          { id = "Main", label = "Main" },
          { id = "Alt", label = "Alt" },
        }
      end
      local picked = GSS.EnsureDefaultMainIfMissing("R")
      GSO.BuildRealmCharEntries = origBuild
      assert.are.equal("Main", picked)
      assert.are.equal("Main", GSS.GetMain("R"))
    end)

    it("seeds the display name with only the top character's first name", function()
      setChars("R", {
        ["Main Toon"] = { name = "Main Toon", realm = "R", level = 70, classFile = "WARRIOR" },
      })
      AltArmy.GuildShareOnboarding = AltArmy.GuildShareOnboarding or {}
      local GSO = AltArmy.GuildShareOnboarding
      local origBuild = GSO.BuildRealmCharEntries
      GSO.BuildRealmCharEntries = function(chars)
        return { { id = "Main Toon", label = "Main Toon" } }
      end
      GSS.EnsureDefaultMainIfMissing("R")
      GSO.BuildRealmCharEntries = origBuild
      assert.are.equal("Main Toon", GSS.GetMain("R"))
      assert.are.equal("Main", GSS.GetDisplayName("R"))
    end)
  end)

  describe("character share mode", function()
    before_each(function()
      _G.GetGuildInfo = function() return "G" end
    end)

    it("defaults to default when no overrides are set", function()
      assert.are.equal("default", GSS.GetCharacterShareMode("Bob", "R"))
    end)

    it("returns dont_share when opted out", function()
      GSS.SetCharacterOptedOut("Bob", "R", true)
      assert.are.equal("dont_share", GSS.GetCharacterShareMode("Bob", "R"))
    end)

    it("returns share when a non-guilded character is opted in", function()
      setChars("R", { Bank = { name = "Bank", realm = "R" } })
      GSS.SetNonGuildedOptIn("Bank", "R", "G")
      assert.are.equal("share", GSS.GetCharacterShareMode("Bank", "R"))
    end)

    it("SetCharacterShareMode default clears overrides", function()
      GSS.SetCharacterOptedOut("Bob", "R", true)
      GSS.SetCharacterShareMode("Bob", "R", "default")
      assert.are.equal("default", GSS.GetCharacterShareMode("Bob", "R"))
    end)

    it("SetCharacterShareMode dont_share opts out guilded characters", function()
      setChars("R", { Alt = { name = "Alt", realm = "R", guildName = "G" } })
      GSS.SetCharacterShareMode("Alt", "R", "dont_share")
      assert.is_true(GSS.IsCharacterOptedOut("Alt", "R"))
    end)

    it("SetCharacterShareMode share opts in non-guilded characters to current guild", function()
      setChars("R", { Bank = { name = "Bank", realm = "R" } })
      GSS.SetCharacterShareMode("Bank", "R", "share")
      assert.are.equal("G", GSS.GetNonGuildedOptInGuild("Bank", "R"))
    end)

    it("GetCharacterShareModeDefaultLabel reflects global sharing", function()
      GSS.SetSharingEnabled(true)
      assert.are.equal("Use global setting (share)", GSS.GetCharacterShareModeDefaultLabel())
      GSS.SetSharingEnabled(false)
      assert.are.equal("Use global setting (don't share)", GSS.GetCharacterShareModeDefaultLabel())
    end)

    it("GetCharacterShareModeEntries includes dynamic default label", function()
      GSS.SetSharingEnabled(true)
      local entries = GSS.GetCharacterShareModeEntries()
      assert.are.equal(3, #entries)
      assert.are.equal("default", entries[1].id)
      assert.are.equal("Use global setting (share)", entries[1].label)
      assert.are.equal("Always share", entries[2].label)
      assert.are.equal("Never share", entries[3].label)
    end)
  end)

  describe("ResolvePresenceMainAndDisplay", function()
    local function charEntry(name, level)
      return { name = name, realm = "R", char = { name = name, level = level or 0 } }
    end

    it("returns saved main and display name when both are set", function()
      GSS.SetMain("R", "SavedMain")
      GSS.SetDisplayName("R", "Chief")
      local main, display = GSS.ResolvePresenceMainAndDisplay({
        charEntry("Alt", 40), charEntry("SavedMain", 70),
      }, "R")
      assert.are.equal("SavedMain", main)
      assert.are.equal("Chief", display)
    end)

    it("leaves main and display nil when neither is saved (receivers guess the main)", function()
      local main, display = GSS.ResolvePresenceMainAndDisplay({
        charEntry("Alt", 40), charEntry("Topchar", 70),
      }, "R")
      assert.is_nil(main)
      assert.is_nil(display)
    end)

    it("sends a saved display name even when main is unset", function()
      GSS.SetDisplayName("R", "Chief")
      local main, display = GSS.ResolvePresenceMainAndDisplay({
        charEntry("Alt", 40), charEntry("Topchar", 70),
      }, "R")
      assert.is_nil(main)
      assert.are.equal("Chief", display)
    end)

    it("uses the main name as display when main is saved but display is not", function()
      GSS.SetMain("R", "SavedMain")
      local main, display = GSS.ResolvePresenceMainAndDisplay({ charEntry("SavedMain", 70) }, "R")
      assert.are.equal("SavedMain", main)
      assert.are.equal("SavedMain", display)
    end)

    it("uses only the main's first name as display for a WoW Forever 'First Last' main", function()
      GSS.SetMain("R", "Saved Main")
      local main, display = GSS.ResolvePresenceMainAndDisplay({ charEntry("Saved Main", 70) }, "R")
      assert.are.equal("Saved Main", main)
      assert.are.equal("Saved", display)
    end)
  end)

  describe("group UI prefs", function()
    it("pin defaults to false", function()
      assert.is_false(GSS.IsGroupPinned("Mainman", "R"))
    end)

    it("SetGroupPinned persists per realm and main", function()
      GSS.SetGroupPinned("Mainman", "R", true)
      assert.is_true(GSS.IsGroupPinned("Mainman", "R"))
      assert.is_false(GSS.IsGroupPinned("Other", "R"))
      assert.is_false(GSS.IsGroupPinned("Mainman", "OtherRealm"))
      GSS.SetGroupPinned("Mainman", "R", false)
      assert.is_false(GSS.IsGroupPinned("Mainman", "R"))
    end)

    it("override name defaults to nil", function()
      assert.is_nil(GSS.GetGroupOverrideName("Mainman", "R"))
    end)

    it("SetGroupOverrideName persists and truncates like display names", function()
      GSS.SetGroupOverrideName("Mainman", "R", "Buddy")
      assert.are.equal("Buddy", GSS.GetGroupOverrideName("Mainman", "R"))
      local longName = string.rep("y", GSS.DISPLAY_NAME_MAX_LENGTH + 5)
      GSS.SetGroupOverrideName("Mainman", "R", longName)
      assert.are.equal(string.rep("y", GSS.DISPLAY_NAME_MAX_LENGTH), GSS.GetGroupOverrideName("Mainman", "R"))
    end)

    it("SetGroupOverrideName clears when empty", function()
      GSS.SetGroupOverrideName("Mainman", "R", "Buddy")
      GSS.SetGroupOverrideName("Mainman", "R", "")
      assert.is_nil(GSS.GetGroupOverrideName("Mainman", "R"))
    end)

    it("ClearGroupUiPrefs removes pin and override for that group", function()
      GSS.SetGroupPinned("Mainman", "R", true)
      GSS.SetGroupOverrideName("Mainman", "R", "Buddy")
      GSS.SetGroupPinned("Other", "R", true)
      GSS.ClearGroupUiPrefs("Mainman", "R")
      assert.is_false(GSS.IsGroupPinned("Mainman", "R"))
      assert.is_nil(GSS.GetGroupOverrideName("Mainman", "R"))
      assert.is_true(GSS.IsGroupPinned("Other", "R"))
    end)
  end)
end)
