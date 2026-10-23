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
end)
