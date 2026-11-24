--[[
  Unit tests for GuildChatMainName.lua (pure guild-chat main-name annotation).
  Run from project root: npm test
]]

describe("GuildChatMainName", function()
  local GCM

  local function mains(map)
    return function(sender) return map[sender] end
  end

  local function mainClasses(map)
    return function(_sender, main) return map[main] end
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS or {
      WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
      MAGE = { r = 0.41, g = 0.8, b = 0.94 },
    }
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("ClassColor")
    require("GuildChatMainName")
    GCM = AltArmy.GuildChatMainName
    assert.truthy(GCM)
  end)

  it("prefixes the main name in square brackets when the sender is a known alt", function()
    local out = GCM.Transform("Alt", "hello", mains({ Alt = "Mainman" }))
    assert.is_true(out:find("^%[.-Mainman.-] hello$") ~= nil, out)
    assert.is_true(out:find("hello", 1, true) ~= nil)
  end)

  it("colors the main name with the main character class", function()
    local out = GCM.Transform(
      "Alt",
      "hello",
      mains({ Alt = "Mainman" }),
      mainClasses({ Mainman = "MAGE" })
    )
    assert.is_true(out:find("|cff", 1, true) ~= nil, out)
    assert.is_true(out:find("Mainman", 1, true) ~= nil)
    assert.is_false(out:find("808080", 1, true) ~= nil, "should not use gray")
  end)

  it("omits class color when colorByClass is false", function()
    local out = GCM.Transform(
      "Alt",
      "hello",
      mains({ Alt = "Mainman" }),
      mainClasses({ Mainman = "MAGE" }),
      nil,
      false
    )
    assert.are.equal("[Mainman] hello", out)
  end)

  it("leaves the message unchanged when the label matches the sender name", function()
    assert.are.equal("hello", GCM.Transform("Mainman", "hello", mains({ Mainman = "Mainman" })))
  end)

  it("leaves the message unchanged when the label matches the sender without realm suffix", function()
    assert.are.equal(
      "hello",
      GCM.Transform("Mainman-Realm", "hello", mains({ ["Mainman-Realm"] = "Mainman" }))
    )
  end)

  it("annotates when the sender is their own main but the preferred label differs", function()
    local out = GCM.Transform(
      "Mainman",
      "hello",
      mains({ Mainman = "Mainman" }),
      nil,
      function() return "SomethingElse" end,
      false)
    assert.are.equal("[SomethingElse] hello", out)
  end)

  describe("FilterMessage channel gating", function()
    local savedDebug
    local savedGSS

    setup(function()
      savedDebug = AltArmy.Debug
      savedGSS = AltArmy.GuildShareSettings
      AltArmy.Debug = { IsGuildShareEnabled = function() return true end }
      AltArmy.GuildShareSettings = {
        IsSharingEnabled = function() return true end,
        IsChatInsertionEnabled = function() return true end,
        IsChatInsertionChannelEnabled = function(key) return key == "guild" end,
      }
      AltArmy.GuildShareData = {
        GetMainOf = function() return "Mainman" end,
        FindCharacter = function() return { realm = "R", classFile = "MAGE" } end,
      }
    end)

    teardown(function()
      AltArmy.Debug = savedDebug
      AltArmy.GuildShareSettings = savedGSS
      AltArmy.GuildShareData = nil
    end)

    it("returns nil when the channel is disabled", function()
      assert.is_nil(GCM.FilterMessage("hello", "Alt", "party"))
    end)

    it("annotates when the channel is enabled", function()
      local out = GCM.FilterMessage("hello", "Alt", "guild")
      assert.is_true(out and out:find("Mainman", 1, true) ~= nil, out)
    end)

    it("omits class color when chat insertion class color is disabled", function()
      AltArmy.GuildShareSettings.IsChatInsertionClassColorEnabled = function() return false end
      local out = GCM.FilterMessage("hello", "Alt", "guild")
      assert.are.equal("[Mainman] hello", out)
    end)

    it("returns nil when guild sharing is opted out", function()
      AltArmy.GuildShareSettings.IsSharingEnabled = function() return false end
      assert.is_nil(GCM.FilterMessage("hello", "Alt", "guild"))
    end)

    it("returns nil instead of annotating when the message is inaccessible (secret)", function()
      AltArmy.GuildShareSettings.IsSharingEnabled = function() return true end
      _G.canaccessvalue = function() return false end
      local out = GCM.FilterMessage("hello", "Alt", "guild")
      _G.canaccessvalue = nil
      assert.is_nil(out)
    end)
  end)

  describe("HasOtherAddonNameTag", function()
    it("detects Name2Chat's (Name): prefix", function()
      assert.is_true(GCM.HasOtherAddonNameTag("(Nexi/Icky): Hello"))
      assert.is_true(GCM.HasOtherAddonNameTag("(Nexi the Great): hi"))
    end)

    it("detects a [Name]: prefix", function()
      assert.is_true(GCM.HasOtherAddonNameTag("[Nexi]: hi"))
    end)

    it("ignores a tag that is not at the start", function()
      assert.is_false(GCM.HasOtherAddonNameTag("Hello (Nexi): x"))
    end)

    it("needs the colon and space after the tag", function()
      assert.is_false(GCM.HasOtherAddonNameTag("(x)Hello"))
      assert.is_false(GCM.HasOtherAddonNameTag("(x) Hello"))
    end)

    it("ignores an item link at the start", function()
      local link = "|cff1eff00|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r: anyone?"
      assert.is_false(GCM.HasOtherAddonNameTag(link))
    end)

    it("does not take Alt Army's own [Label] prefix for one", function()
      assert.is_false(GCM.HasOtherAddonNameTag("[Nexi] hi"))
    end)

    it("ignores a tag longer than the cap", function()
      local long = string.rep("a", GCM.MAX_NAME_TAG_LENGTH + 1)
      assert.is_false(GCM.HasOtherAddonNameTag("(" .. long .. "): hi"))
      local max = string.rep("a", GCM.MAX_NAME_TAG_LENGTH)
      assert.is_true(GCM.HasOtherAddonNameTag("(" .. max .. "): hi"))
    end)

    it("is false for what is not a string", function()
      assert.is_false(GCM.HasOtherAddonNameTag(nil))
      assert.is_false(GCM.HasOtherAddonNameTag(42))
    end)
  end)

  describe("StripOtherAddonNameTag", function()
    it("returns the message without the tag", function()
      assert.are.equal("Hello", GCM.StripOtherAddonNameTag("(Nexi/Icky): Hello"))
      assert.are.equal("hi there", GCM.StripOtherAddonNameTag("[Nexi]: hi there"))
    end)

    it("returns nil when there is no tag", function()
      assert.is_nil(GCM.StripOtherAddonNameTag("Hello"))
      assert.is_nil(GCM.StripOtherAddonNameTag(nil))
    end)
  end)

  describe("ColorOtherAddonNameTag", function()
    it("colors only the name inside the brackets", function()
      local out = GCM.ColorOtherAddonNameTag("(Nexi/Icky): Hello", "MAGE")
      assert.are.equal("(" .. AltArmy.ClassColor.formatName("Nexi/Icky", "MAGE") .. "): Hello", out)
    end)

    it("colors a [Name]: tag the same way", function()
      local out = GCM.ColorOtherAddonNameTag("[Nexi]: hi", "WARRIOR")
      assert.are.equal("[" .. AltArmy.ClassColor.formatName("Nexi", "WARRIOR") .. "]: hi", out)
    end)

    it("returns nil without a tag or a class", function()
      assert.is_nil(GCM.ColorOtherAddonNameTag("Hello", "MAGE"))
      assert.is_nil(GCM.ColorOtherAddonNameTag("(Nexi): Hello", nil))
    end)

    it("does not take a tag already holding escape codes for one", function()
      assert.is_nil(GCM.ColorOtherAddonNameTag("(|cffff0000Nexi|r): Hello", "MAGE"))
    end)
  end)

  describe("FilterMessage with other addons' name tags", function()
    local savedDebug
    local savedGSS
    local mode
    local main
    local color
    local mainClass

    setup(function()
      savedDebug = AltArmy.Debug
      savedGSS = AltArmy.GuildShareSettings
      AltArmy.Debug = { IsGuildShareEnabled = function() return true end }
      AltArmy.GuildShareSettings = {
        IsSharingEnabled = function() return true end,
        IsChatInsertionEnabled = function() return true end,
        IsChatInsertionChannelEnabled = function() return true end,
        IsChatInsertionClassColorEnabled = function() return color end,
        GetChatOtherNamesMode = function() return mode end,
      }
      AltArmy.GuildShareData = {
        GetMainOf = function() return main end,
        FindCharacter = function() return { realm = "R", classFile = mainClass } end,
      }
    end)

    before_each(function()
      main = "Mainman"
      color = false
      mainClass = "MAGE"
      _G.GetPlayerInfoByGUID = nil
    end)

    teardown(function()
      AltArmy.Debug = savedDebug
      AltArmy.GuildShareSettings = savedGSS
      AltArmy.GuildShareData = nil
      _G.GetPlayerInfoByGUID = nil
    end)

    local function tinted(name, classFile)
      return AltArmy.ClassColor.formatName(name, classFile)
    end

    it("theirs: colors their name by the main's class when class color is on", function()
      mode = "theirs"
      color = true
      assert.are.equal("(" .. tinted("Nexi/Icky", "MAGE") .. "): Hello",
        GCM.FilterMessage("(Nexi/Icky): Hello", "Alt", "guild", "Player-1-0001"))
    end)

    it("theirs: falls back to the sender's own class when the main is unknown", function()
      mode = "theirs"
      color = true
      main = nil
      _G.GetPlayerInfoByGUID = function(guid)
        assert.are.equal("Player-1-0001", guid)
        return "Warrior", "WARRIOR"
      end
      assert.are.equal("(" .. tinted("Nexi/Icky", "WARRIOR") .. "): Hello",
        GCM.FilterMessage("(Nexi/Icky): Hello", "Stranger", "guild", "Player-1-0001"))
    end)

    it("theirs: falls back to the sender's class when the main's class is unknown", function()
      mode = "theirs"
      color = true
      mainClass = nil
      _G.GetPlayerInfoByGUID = function() return "Warrior", "WARRIOR" end
      assert.are.equal("(" .. tinted("Nexi/Icky", "WARRIOR") .. "): Hello",
        GCM.FilterMessage("(Nexi/Icky): Hello", "Alt", "guild", "Player-1-0001"))
    end)

    it("theirs: leaves their tag alone when no class is known", function()
      mode = "theirs"
      color = true
      main = nil
      assert.is_nil(GCM.FilterMessage("(Nexi/Icky): Hello", "Stranger", "guild", nil))
    end)

    it("theirs: ignores an inaccessible (secret) GUID", function()
      mode = "theirs"
      color = true
      main = nil
      _G.GetPlayerInfoByGUID = function() return "Warrior", "WARRIOR" end
      _G.canaccessvalue = function(v) return v ~= "secret" end
      local out = GCM.FilterMessage("(Nexi/Icky): Hello", "Stranger", "guild", "secret")
      _G.canaccessvalue = nil
      assert.is_nil(out)
    end)

    it("both: leaves their tag uncolored", function()
      mode = "both"
      color = true
      local out = GCM.FilterMessage("(Nexi/Icky): Hello", "Alt", "guild", "Player-1-0001")
      assert.is_true(out:sub(-#"(Nexi/Icky): Hello") == "(Nexi/Icky): Hello", out)
    end)

    it("theirs: leaves a tagged message alone", function()
      mode = "theirs"
      assert.is_nil(GCM.FilterMessage("(Nexi/Icky): Hello", "Alt", "guild"))
    end)

    it("theirs: still annotates an untagged message", function()
      mode = "theirs"
      assert.are.equal("[Mainman] Hello", GCM.FilterMessage("Hello", "Alt", "guild"))
    end)

    it("ours: replaces their tag with ours", function()
      mode = "ours"
      assert.are.equal("[Mainman] Hello", GCM.FilterMessage("(Nexi/Icky): Hello", "Alt", "guild"))
    end)

    it("ours: keeps their tag when Alt Army has no name to show", function()
      mode = "ours"
      main = nil
      assert.is_nil(GCM.FilterMessage("(Nexi/Icky): Hello", "Alt", "guild"))
    end)

    it("both: shows ours before theirs", function()
      mode = "both"
      assert.are.equal("[Mainman] (Nexi/Icky): Hello",
        GCM.FilterMessage("(Nexi/Icky): Hello", "Alt", "guild"))
    end)
  end)

  describe("FilterMessage manual-group class color", function()
    local savedDebug
    local savedGSS
    local savedGSD
    local savedGMG

    setup(function()
      savedDebug = AltArmy.Debug
      savedGSS = AltArmy.GuildShareSettings
      savedGSD = AltArmy.GuildShareData
      savedGMG = AltArmy.GuildManualGroups
      AltArmy.Debug = { IsGuildShareEnabled = function() return true end }
      AltArmy.GuildShareSettings = {
        IsSharingEnabled = function() return true end,
        IsChatInsertionEnabled = function() return true end,
        IsChatInsertionChannelEnabled = function(key) return key == "guild" end,
        IsChatInsertionClassColorEnabled = function() return true end,
      }
      -- Manual-only: main resolved via GetMainOf, but FindCharacter has no .chars entry.
      AltArmy.GuildShareData = {
        GetMainOf = function() return "Mainman" end,
        FindCharacter = function() return nil end,
      }
      AltArmy.GuildManualGroups = {
        GetMapping = function(name)
          if name == "Mainman" then
            return { main = "Mainman", classFile = "WARRIOR" }
          end
          return nil
        end,
      }
    end)

    teardown(function()
      AltArmy.Debug = savedDebug
      AltArmy.GuildShareSettings = savedGSS
      AltArmy.GuildShareData = savedGSD
      AltArmy.GuildManualGroups = savedGMG
    end)

    it("colors the main from the manual mapping classFile when FindCharacter misses", function()
      local out = GCM.FilterMessage("hello", "Alt", "guild")
      assert.is_true(out and out:find("|cff", 1, true) ~= nil, out)
      assert.is_true(out:find("Mainman", 1, true) ~= nil, out)
      -- Warrior class color, not white fallback.
      assert.is_true(out:find("|cffc79c6eMainman|r", 1, true) ~= nil, out)
      assert.is_false(out:find("|cffffffffMainman|r", 1, true) ~= nil, out)
    end)
  end)

  describe("Communities guild UI helpers", function()
    local savedDebug
    local savedGSS
    local savedEnum

    local function guildClub()
      return { clubType = 2 } -- Enum.ClubType.Guild
    end

    local function characterClub()
      return { clubType = 1 } -- Enum.ClubType.Character
    end

    local function msg(opts)
      opts = opts or {}
      return {
        content = opts.content or "hello",
        destroyed = opts.destroyed,
        author = opts.author ~= nil and opts.author or { name = opts.name or "Alt" },
      }
    end

    setup(function()
      savedDebug = AltArmy.Debug
      savedGSS = AltArmy.GuildShareSettings
      savedEnum = _G.Enum
      _G.Enum = { ClubType = { Guild = 2, Character = 1, BattleNet = 0 } }
      AltArmy.Debug = { IsGuildShareEnabled = function() return true end }
      AltArmy.GuildShareSettings = {
        IsSharingEnabled = function() return true end,
        IsChatInsertionEnabled = function() return true end,
        IsChatInsertionChannelEnabled = function(key) return key == "guild" end,
        IsChatInsertionClassColorEnabled = function() return false end,
      }
      AltArmy.GuildShareData = {
        GetMainOf = function() return "Mainman" end,
        FindCharacter = function() return { realm = "R", classFile = "MAGE" } end,
      }
    end)

    teardown(function()
      AltArmy.Debug = savedDebug
      AltArmy.GuildShareSettings = savedGSS
      AltArmy.GuildShareData = nil
      _G.Enum = savedEnum
    end)

    it("ShouldAnnotateClubMessage is true for guild club messages with an author", function()
      assert.is_true(GCM.ShouldAnnotateClubMessage(guildClub(), msg()))
    end)

    it("ShouldAnnotateClubMessage is false for non-guild clubs", function()
      assert.is_false(GCM.ShouldAnnotateClubMessage(characterClub(), msg()))
    end)

    it("ShouldAnnotateClubMessage is false when clubInfo is missing", function()
      assert.is_false(GCM.ShouldAnnotateClubMessage(nil, msg()))
    end)

    it("ShouldAnnotateClubMessage is false for destroyed messages", function()
      assert.is_false(GCM.ShouldAnnotateClubMessage(guildClub(), msg({ destroyed = true })))
    end)

    it("ShouldAnnotateClubMessage is false when author name is missing", function()
      assert.is_false(GCM.ShouldAnnotateClubMessage(guildClub(), msg({ author = {} })))
      assert.is_false(GCM.ShouldAnnotateClubMessage(guildClub(), msg({ author = { name = "" } })))
    end)

    it("ShouldAnnotateClubMessage is false when author name is inaccessible (secret)", function()
      _G.canaccessvalue = function() return false end
      local result = GCM.ShouldAnnotateClubMessage(guildClub(), msg())
      _G.canaccessvalue = nil
      assert.is_false(result)
    end)

    it("AnnotateClubMessageContent annotates when guild insertion is allowed", function()
      local out = GCM.AnnotateClubMessageContent("Alt", "hello")
      assert.are.equal("[Mainman] hello", out)
    end)

    it("WrapCommunitiesFormatMessage annotates via the frame instance FormatMessage", function()
      local savedCClub = _G.C_Club
      _G.C_Club = {
        GetClubInfo = function() return guildClub() end,
      }
      local owner = {
        FormatMessage = function(_, _, _, message)
          return "FMT:" .. (message.content or "")
        end,
      }
      assert.is_true(GCM.WrapCommunitiesFormatMessage(owner))
      local out = owner:FormatMessage("club", "stream", msg({ content = "hello" }))
      assert.are.equal("FMT:[Mainman] hello", out)
      _G.C_Club = savedCClub
    end)

    it("WrapCommunitiesFormatMessage is idempotent on the same owner", function()
      local owner = {
        FormatMessage = function(_, _, _, message)
          return message.content
        end,
      }
      assert.is_true(GCM.WrapCommunitiesFormatMessage(owner))
      assert.is_false(GCM.WrapCommunitiesFormatMessage(owner))
    end)

    it("AnnotateClubMessageContent returns nil when the guild channel is disabled", function()
      AltArmy.GuildShareSettings.IsChatInsertionChannelEnabled = function() return false end
      assert.is_nil(GCM.AnnotateClubMessageContent("Alt", "hello"))
      AltArmy.GuildShareSettings.IsChatInsertionChannelEnabled = function(key) return key == "guild" end
    end)

    it("AnnotateClubMessageContent returns nil when chat insertion is disabled", function()
      AltArmy.GuildShareSettings.IsChatInsertionEnabled = function() return false end
      assert.is_nil(GCM.AnnotateClubMessageContent("Alt", "hello"))
      AltArmy.GuildShareSettings.IsChatInsertionEnabled = function() return true end
    end)
  end)

  it("leaves the message unchanged when the sender is unknown", function()
    assert.are.equal("hi", GCM.Transform("Stranger", "hi", mains({})))
  end)

  it("leaves the message unchanged with no resolver", function()
    assert.are.equal("hi", GCM.Transform("Alt", "hi", nil))
  end)

  it("does not annotate twice if the main equals the sender name case-sensitively only", function()
    local out = GCM.Transform("Alt", "yo", mains({ Alt = "Boss" }))
    local _, count = out:gsub("Boss", "Boss")
    assert.are.equal(1, count)
  end)

  it("uses getLabel for the bracket text when provided", function()
    local out = GCM.Transform(
      "Alt",
      "hello",
      mains({ Alt = "Mainman" }),
      nil,
      function() return "Buddy" end)
    assert.is_true(out:find("Buddy", 1, true) ~= nil, out)
    assert.is_false(out:find("Mainman", 1, true) ~= nil, out)
  end)

  it("skips annotation when getLabel matches the sender name", function()
    local out = GCM.Transform(
      "Alt",
      "hello",
      mains({ Alt = "Mainman" }),
      nil,
      function() return "Alt" end)
    assert.are.equal("hello", out)
  end)

  describe("FilterMessage display label", function()
    local savedDebug
    local savedGSS
    local savedGSD

    setup(function()
      savedDebug = AltArmy.Debug
      savedGSS = AltArmy.GuildShareSettings
      savedGSD = AltArmy.GuildShareData
      AltArmy.Debug = { IsGuildShareEnabled = function() return true end }
      AltArmy.GuildShareSettings = {
        IsSharingEnabled = function() return true end,
        IsChatInsertionEnabled = function() return true end,
        IsChatInsertionChannelEnabled = function() return true end,
        GetGroupOverrideName = function(main, realm)
          if main == "Mainman" and realm == "R" then return "Buddy" end
          return nil
        end,
      }
      AltArmy.GuildShareData = {
        GetMainOf = function() return "Mainman" end,
        FindCharacter = function(name)
          if name == "Alt" then
            return { realm = "R", classFile = "WARRIOR", main = "Mainman", displayName = "Chief" }
          end
          if name == "Mainman" then
            return { realm = "R", classFile = "MAGE", main = "Mainman", displayName = "Chief" }
          end
          return nil
        end,
      }
    end)

    teardown(function()
      AltArmy.Debug = savedDebug
      AltArmy.GuildShareSettings = savedGSS
      AltArmy.GuildShareData = savedGSD
    end)

    it("prefers override name in the chat bracket", function()
      local out = GCM.FilterMessage("hello", "Alt", "guild")
      assert.is_true(out and out:find("Buddy", 1, true) ~= nil, out)
      assert.is_false(out:find("Mainman", 1, true) ~= nil, out)
      assert.is_false(out:find("Chief", 1, true) ~= nil, out)
    end)

    it("falls back to displayName when no override", function()
      AltArmy.GuildShareSettings.GetGroupOverrideName = function() return nil end
      local out = GCM.FilterMessage("hello", "Alt", "guild")
      assert.is_true(out and out:find("Chief", 1, true) ~= nil, out)
    end)

    it("annotates when the sender is the main but displayName differs", function()
      AltArmy.GuildShareSettings.GetGroupOverrideName = function() return nil end
      AltArmy.GuildShareSettings.IsChatInsertionClassColorEnabled = function() return false end
      local out = GCM.FilterMessage("hello", "Mainman", "guild")
      assert.are.equal("[Chief] hello", out)
    end)
  end)

  describe("online/offline system messages", function()
    local ONLINE = "|Hplayer:Allystie|h[Allystie]|h has come online."
    local OFFLINE = "Allystie has gone offline."

    setup(function()
      _G.ERR_FRIEND_ONLINE_SS = "|Hplayer:%s|h[%s]|h has come online."
      _G.ERR_FRIEND_OFFLINE_S = "%s has gone offline."
    end)

    it("ParseOnlineOffline extracts the name from an online message", function()
      local name, kind = GCM.ParseOnlineOffline(ONLINE)
      assert.are.equal("Allystie", name)
      assert.are.equal("online", kind)
    end)

    it("ParseOnlineOffline extracts the name from an offline message", function()
      local name, kind = GCM.ParseOnlineOffline(OFFLINE)
      assert.are.equal("Allystie", name)
      assert.are.equal("offline", kind)
    end)

    it("ParseOnlineOffline returns nil for unrelated system text", function()
      assert.is_nil(GCM.ParseOnlineOffline("You receive loot: [Foo]."))
    end)

    it("inserts the main after the character name on online", function()
      local out = GCM.TransformOnlineOffline(ONLINE, mains({ Allystie = "Treebus" }))
      assert.is_true(out:find("|Hplayer:Allystie|h%[Allystie%]|h %[.-Treebus.-] has come online%.$", 1) ~= nil, out)
    end)

    it("inserts the main after the character name on offline", function()
      local out = GCM.TransformOnlineOffline(OFFLINE, mains({ Allystie = "Treebus" }))
      assert.is_true(out:find("^Allystie %[.-Treebus.-] has gone offline%.$", 1) ~= nil, out)
    end)

    it("colors the main name with the main character class", function()
      local out = GCM.TransformOnlineOffline(
        ONLINE,
        mains({ Allystie = "Treebus" }),
        mainClasses({ Treebus = "MAGE" })
      )
      assert.is_true(out:find("|cff", 1, true) ~= nil, out)
      assert.is_true(out:find("Treebus", 1, true) ~= nil)
      assert.is_false(out:find("808080", 1, true) ~= nil, "should not use gray")
    end)

    it("omits class color when colorByClass is false", function()
      local out = GCM.TransformOnlineOffline(
        OFFLINE,
        mains({ Allystie = "Treebus" }),
        mainClasses({ Treebus = "MAGE" }),
        nil,
        false
      )
      assert.are.equal("Allystie [Treebus] has gone offline.", out)
    end)

    it("leaves online/offline unchanged when the label matches the character name", function()
      assert.are.equal(ONLINE, GCM.TransformOnlineOffline(ONLINE, mains({ Allystie = "Allystie" })))
      assert.are.equal(OFFLINE, GCM.TransformOnlineOffline(OFFLINE, mains({ Allystie = "Allystie" })))
    end)

    it("annotates online/offline when the character is their main but preferred label differs", function()
      local out = GCM.TransformOnlineOffline(
        OFFLINE,
        mains({ Allystie = "Allystie" }),
        nil,
        function() return "SomethingElse" end,
        false)
      assert.are.equal("Allystie [SomethingElse] has gone offline.", out)
    end)

    it("keeps a Forever surname before the brackets on offline, not after", function()
      local out = GCM.TransformOnlineOffline(
        "Lizardbait Guttermoss has gone offline.",
        mains({ ["Lizardbait Guttermoss"] = "Drubbles" }),
        nil, nil, false)
      assert.are.equal("Lizardbait Guttermoss [Drubbles] has gone offline.", out)
    end)

    it("puts a whole preferred name with a surname inside the brackets on offline", function()
      local out = GCM.TransformOnlineOffline(
        "Lizardbait Guttermoss has gone offline.",
        mains({ ["Lizardbait Guttermoss"] = "Drubbles" }),
        nil,
        function() return "Drubbles Guttermoss" end,
        false)
      assert.are.equal("Lizardbait Guttermoss [Drubbles Guttermoss] has gone offline.", out)
    end)

    it("keeps a Forever surname before the brackets on online", function()
      local out = GCM.TransformOnlineOffline(
        "|Hplayer:Lizardbait Guttermoss|h[Lizardbait Guttermoss]|h has come online.",
        mains({ ["Lizardbait Guttermoss"] = "Drubbles" }),
        nil, nil, false)
      assert.are.equal(
        "|Hplayer:Lizardbait Guttermoss|h[Lizardbait Guttermoss]|h [Drubbles] has come online.", out)
    end)

    it("keeps the realm suffix when splitting the offline message", function()
      local out = GCM.TransformOnlineOffline(
        "Allystie-Dreamscythe has gone offline.",
        mains({ Allystie = "Treebus" }),
        nil, nil, false)
      assert.are.equal("Allystie-Dreamscythe [Treebus] has gone offline.", out)
    end)

    it("leaves online/offline unchanged when the character is unknown", function()
      assert.are.equal(ONLINE, GCM.TransformOnlineOffline(ONLINE, mains({})))
    end)

    it("uses getLabel for the bracket text when provided", function()
      local out = GCM.TransformOnlineOffline(
        OFFLINE,
        mains({ Allystie = "Treebus" }),
        nil,
        function() return "Buddy" end)
      assert.is_true(out:find("Buddy", 1, true) ~= nil, out)
      assert.is_false(out:find("Treebus", 1, true) ~= nil, out)
    end)

    describe("FilterSystemMessage gating", function()
      local savedDebug
      local savedGSS

      setup(function()
        savedDebug = AltArmy.Debug
        savedGSS = AltArmy.GuildShareSettings
        AltArmy.Debug = { IsGuildShareEnabled = function() return true end }
        AltArmy.GuildShareSettings = {
          IsSharingEnabled = function() return true end,
          IsChatInsertionEnabled = function() return true end,
        }
        AltArmy.GuildShareData = {
          GetMainOf = function() return "Treebus" end,
          FindCharacter = function(name)
            if name == "Allystie" then
              return { realm = "R", classFile = "WARRIOR", main = "Treebus" }
            end
            if name == "Treebus" then
              return { realm = "R", classFile = "MAGE", main = "Treebus", displayName = "Treebus" }
            end
            return nil
          end,
        }
      end)

      teardown(function()
        AltArmy.Debug = savedDebug
        AltArmy.GuildShareSettings = savedGSS
        AltArmy.GuildShareData = nil
      end)

      it("annotates when chat insertion is enabled", function()
        local out = GCM.FilterSystemMessage(ONLINE)
        assert.is_true(out and out:find("Treebus", 1, true) ~= nil, out)
      end)

      it("returns nil when chat insertion is disabled", function()
        AltArmy.GuildShareSettings.IsChatInsertionEnabled = function() return false end
        assert.is_nil(GCM.FilterSystemMessage(ONLINE))
      end)

      it("returns nil when guild sharing is opted out", function()
        AltArmy.GuildShareSettings.IsSharingEnabled = function() return false end
        assert.is_nil(GCM.FilterSystemMessage(ONLINE))
      end)

      it("returns nil for non online/offline system text", function()
        assert.is_nil(GCM.FilterSystemMessage("You receive loot: [Foo]."))
      end)

      it("returns nil instead of annotating when the message is inaccessible (secret)", function()
        AltArmy.GuildShareSettings.IsSharingEnabled = function() return true end
        AltArmy.GuildShareSettings.IsChatInsertionEnabled = function() return true end
        _G.canaccessvalue = function() return false end
        local out = GCM.FilterSystemMessage(ONLINE)
        _G.canaccessvalue = nil
        assert.is_nil(out)
      end)
    end)
  end)

  describe("chat filter installation", function()
    local savedDebug, savedGSS
    local installed, insertion

    local function count()
      local n = 0
      for _ in pairs(installed) do n = n + 1 end
      return n
    end

    before_each(function()
      savedDebug = AltArmy.Debug
      savedGSS = AltArmy.GuildShareSettings
      insertion = true
      AltArmy.Debug = { IsGuildShareEnabled = function() return true end }
      AltArmy.GuildShareSettings = {
        IsSharingEnabled = function() return true end,
        IsChatInsertionEnabled = function() return insertion end,
      }
      installed = {}
      _G.ChatFrame_AddMessageEventFilter = function(event, fn) installed[fn] = event end
      _G.ChatFrame_RemoveMessageEventFilter = function(_, fn) installed[fn] = nil end
    end)

    after_each(function()
      insertion = false
      GCM.SyncFilters()
      AltArmy.Debug = savedDebug
      AltArmy.GuildShareSettings = savedGSS
      _G.ChatFrame_AddMessageEventFilter = nil
      _G.ChatFrame_RemoveMessageEventFilter = nil
      _G.InCombatLockdown = nil
      _G.C_ChatInfo = nil
    end)

    it("installs nothing while chat insertion is off", function()
      insertion = false
      assert.is_false(GCM.SyncFilters())
      assert.are.equal(0, count())
    end)

    it("installs the filters once chat insertion is on, and removes them when it goes off", function()
      assert.is_true(GCM.SyncFilters())
      assert.is_true(count() > 0)
      insertion = false
      assert.is_false(GCM.SyncFilters())
      assert.are.equal(0, count())
    end)

    it("takes the filters out in combat, when messages may be secret", function()
      assert.is_true(GCM.SyncFilters())
      _G.InCombatLockdown = function() return true end
      assert.is_false(GCM.SyncFilters())
      assert.are.equal(0, count())
      _G.InCombatLockdown = function() return false end
      assert.is_true(GCM.SyncFilters())
    end)

    it("takes the filters out while an addon restriction is active, and puts them back after", function()
      assert.is_true(GCM.SyncFilters())
      GCM._OnEvent(nil, "ADDON_RESTRICTION_STATE_CHANGED", 4, 1) -- Map, Activating
      assert.are.equal(0, count())
      GCM._OnEvent(nil, "ADDON_RESTRICTION_STATE_CHANGED", 4, 0) -- Map, Inactive
      assert.is_true(count() > 0)
    end)

    it("takes the filters out during an encounter", function()
      GCM._OnEvent(nil, "ENCOUNTER_START")
      assert.are.equal(0, count())
      GCM._OnEvent(nil, "ENCOUNTER_END")
      assert.is_true(count() > 0)
    end)

    it("never replaces Communities FormatMessage on clients with secret values", function()
      local orig = function() return "x" end
      local owner = { FormatMessage = orig }
      _G.canaccessvalue = function() return true end
      local wrapped = GCM.WrapCommunitiesFormatMessage(owner)
      _G.canaccessvalue = nil
      assert.is_false(wrapped)
      assert.are.equal(orig, owner.FormatMessage)
    end)

    it("takes the filters out during chat lockdown", function()
      _G.C_ChatInfo = { InChatMessagingLockdown = function() return true end }
      assert.is_false(GCM.SyncFilters())
      assert.are.equal(0, count())
    end)
  end)
end)
