--[[
  Unit tests for the pure helpers in GuildShareComm.lua (flag-branched send-set + sender
  normalization). The AceComm wiring itself is exercised in-game, not here.
  Run from project root: npm test
]]

describe("GuildShareComm helpers", function()
  local Comm

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.CreateFrame = _G.CreateFrame or function()
      return { RegisterEvent = function() end, SetScript = function() end }
    end
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("GuildShareComm")
    Comm = AltArmy.GuildShareComm
    assert.truthy(Comm)
  end)

  before_each(function()
    AltArmy.GuildShareSettings = {
      GetShareableCharacters = function() return { { name = "OptedIn" } } end,
      GetAllGuildedCharacters = function() return { { name = "AllGuilded" } } end,
    }
  end)

  describe("_CollectOnlineGuildMembers", function()
    it("skips a roster row whose name is inaccessible (secret) but keeps the rest", function()
      local roster = {
        { "Alice", nil, nil, nil, nil, nil, nil, nil, true },
        { "SecretName", nil, nil, nil, nil, nil, nil, nil, true },
      }
      _G.UnitName = function() return "Me" end
      _G.IsInGuild = function() return true end
      _G.GetNumGuildMembers = function() return #roster end
      _G.GetGuildRosterInfo = function(i) return unpack(roster[i]) end
      _G.canaccessvalue = function(v) return v ~= "SecretName" end
      local out = Comm._CollectOnlineGuildMembers()
      _G.canaccessvalue = nil
      assert.are.same({ Alice = true }, out)
    end)
  end)

  describe("STALE_MAX_AGE", function()
    it("purges received guild data after 180 days", function()
      assert.are.equal(60 * 60 * 24 * 180, Comm.STALE_MAX_AGE)
    end)
  end)

  describe("PurgeStaleReceived", function()
    it("purges when auto-delete is enabled", function()
      local purgedAge
      AltArmy.GuildShareSettings.IsAutoDeleteOldDataEnabled = function() return true end
      AltArmy.GuildShareSettings.AUTO_DELETE_MAX_AGE_SEC = 60 * 60 * 24 * 180
      AltArmy.GuildShareData = {
        PurgeStale = function(age)
          purgedAge = age
          return 1
        end,
      }
      Comm.PurgeStaleReceived()
      assert.are.equal(60 * 60 * 24 * 180, purgedAge)
    end)

    it("does not purge when auto-delete is disabled", function()
      local called = false
      AltArmy.GuildShareSettings.IsAutoDeleteOldDataEnabled = function() return false end
      AltArmy.GuildShareData = {
        PurgeStale = function()
          called = true
        end,
      }
      Comm.PurgeStaleReceived()
      assert.is_false(called)
    end)
  end)

  describe("_SelectShareChars", function()
    it("uses the opt-in set when the flag is ON", function()
      local list = Comm._SelectShareChars(true, "G", "R")
      assert.are.equal(1, #list)
      assert.are.equal("OptedIn", list[1].name)
    end)
    it("uses the all-guilded set (ignoring settings) when the flag is OFF", function()
      local list = Comm._SelectShareChars(false, "G", "R")
      assert.are.equal(1, #list)
      assert.are.equal("AllGuilded", list[1].name)
    end)
  end)

  describe("_BroadcastSkippedLogMessage", function()
    it("never skips for sharing-disabled: empty opt-out presence is sent instead", function()
      assert.is_nil(Comm._BroadcastSkippedLogMessage(false, false))
      assert.is_nil(Comm._BroadcastSkippedLogMessage(false, true))
      assert.is_nil(Comm._BroadcastSkippedLogMessage(true, true))
      assert.is_nil(Comm._BroadcastSkippedLogMessage(true, false))
    end)
  end)

  describe("_PresenceForShareChars", function()
    before_each(function()
      package.loaded["GuildShareProtocol"] = nil
      require("GuildShareProtocol")
    end)

    it("builds an empty presence when the flag is ON and the share set is empty", function()
      local presence = Comm._PresenceForShareChars(true, {})
      assert.truthy(presence)
      assert.are.equal(0, #presence.chars)
    end)

    it("returns nil when the flag is OFF and the share set is empty", function()
      assert.is_nil(Comm._PresenceForShareChars(false, {}))
    end)

    it("builds a normal presence when characters are present", function()
      local char = {
        name = "Main", classFile = "MAGE", faction = "Alliance", level = 70, Professions = {},
      }
      local presence = Comm._PresenceForShareChars(true, {
        { name = "Main", realm = "R", char = char },
      }, "Main", "Display")
      assert.truthy(presence)
      assert.are.equal(1, #presence.chars)
      assert.are.equal("Main", presence.main)
      assert.are.equal("Display", presence.displayName)
    end)
  end)

  describe("_WithLoginAnnounce", function()
    it("stamps login=true on a presence when announcing login", function()
      local presence = { v = 1, chars = {} }
      local out = Comm._WithLoginAnnounce(presence, true)
      assert.are.equal(presence, out)
      assert.is_true(out.login)
    end)

    it("leaves presence unchanged when not a login announce", function()
      local presence = { v = 1, chars = {}, login = true }
      local out = Comm._WithLoginAnnounce(presence, false)
      assert.is_nil(out.login)
    end)

    it("returns nil unchanged", function()
      assert.is_nil(Comm._WithLoginAnnounce(nil, true))
    end)
  end)

  describe("_ShouldBroadcastOnEnteringWorld", function()
    it("broadcasts on initial login", function()
      assert.is_true(Comm._ShouldBroadcastOnEnteringWorld(true, false))
    end)

    it("broadcasts on UI reload", function()
      assert.is_true(Comm._ShouldBroadcastOnEnteringWorld(false, true))
    end)

    it("does not broadcast on zone transitions", function()
      assert.is_false(Comm._ShouldBroadcastOnEnteringWorld(false, false))
      assert.is_false(Comm._ShouldBroadcastOnEnteringWorld(nil, nil))
    end)
  end)

  describe("_ShouldSendGuildBroadcast", function()
    it("requires IsInGuild and a non-empty guild name", function()
      assert.is_true(Comm._ShouldSendGuildBroadcast(true, "Reign of Error"))
      assert.is_false(Comm._ShouldSendGuildBroadcast(true, nil),
        "IsInGuild can be true before GetGuildInfo is ready; do not send")
      assert.is_false(Comm._ShouldSendGuildBroadcast(true, ""))
      assert.is_false(Comm._ShouldSendGuildBroadcast(false, "G"))
      assert.is_false(Comm._ShouldSendGuildBroadcast(false, nil))
    end)
  end)

  describe("ScheduleBroadcast", function()
    local scheduled, broadcastCount, realBroadcast

    before_each(function()
      scheduled = {}
      broadcastCount = 0
      realBroadcast = Comm.Broadcast
      Comm.Broadcast = function() broadcastCount = broadcastCount + 1 end
      _G.C_Timer = {
        After = function(delay, fn)
          scheduled[#scheduled + 1] = { delay = delay, fn = fn }
        end,
      }
      if Comm.CancelScheduledBroadcast then
        Comm.CancelScheduledBroadcast()
      end
    end)

    after_each(function()
      Comm.Broadcast = realBroadcast
      _G.C_Timer = nil
      if Comm.CancelScheduledBroadcast then
        Comm.CancelScheduledBroadcast()
      end
    end)

    it("debounces settings broadcasts for 5 seconds", function()
      assert.are.equal(5, Comm.SETTINGS_BROADCAST_DEBOUNCE_SEC)
      Comm.ScheduleBroadcast()
      assert.are.equal(0, broadcastCount)
      assert.are.equal(1, #scheduled)
      assert.are.equal(5, scheduled[1].delay)
      scheduled[1].fn()
      assert.are.equal(1, broadcastCount)
    end)

    it("accepts an explicit debounce delay (e.g. longer profession quiet period)", function()
      assert.are.equal(30, Comm.PROFESSION_BROADCAST_DEBOUNCE_SEC)
      Comm.ScheduleBroadcast(Comm.PROFESSION_BROADCAST_DEBOUNCE_SEC)
      assert.are.equal(1, #scheduled)
      assert.are.equal(30, scheduled[1].delay)
    end)

    it("resets the debounce window when called again before it fires", function()
      Comm.ScheduleBroadcast()
      Comm.ScheduleBroadcast()
      assert.are.equal(2, #scheduled)
      scheduled[1].fn()
      assert.are.equal(0, broadcastCount, "cancelled first timer must not broadcast")
      scheduled[2].fn()
      assert.are.equal(1, broadcastCount)
    end)

    it("later ScheduleBroadcast replaces an earlier longer delay", function()
      Comm.ScheduleBroadcast(15)
      Comm.ScheduleBroadcast(5)
      assert.are.equal(2, #scheduled)
      assert.are.equal(15, scheduled[1].delay)
      assert.are.equal(5, scheduled[2].delay)
      scheduled[1].fn()
      assert.are.equal(0, broadcastCount)
      scheduled[2].fn()
      assert.are.equal(1, broadcastCount)
    end)

    it("CancelScheduledBroadcast prevents a pending timer from broadcasting", function()
      Comm.ScheduleBroadcast()
      Comm.CancelScheduledBroadcast()
      scheduled[1].fn()
      assert.are.equal(0, broadcastCount)
    end)
  end)

  describe("_GuildMembershipChanged", function()
    it("is true when joining or leaving a guild", function()
      assert.is_true(Comm._GuildMembershipChanged(nil, "G"))
      assert.is_true(Comm._GuildMembershipChanged("G", nil))
      assert.is_true(Comm._GuildMembershipChanged("A", "B"))
    end)

    it("is false when the guild is unchanged", function()
      assert.is_false(Comm._GuildMembershipChanged(nil, nil))
      assert.is_false(Comm._GuildMembershipChanged("G", "G"))
    end)
  end)

  describe("_HandlePlayerGuildUpdate", function()
    local broadcastCount, lastLoginAnnounce, purged, realBroadcast

    before_each(function()
      broadcastCount = 0
      lastLoginAnnounce = nil
      purged = nil
      realBroadcast = Comm.Broadcast
      AltArmy.GuildShareData = {
        PurgeGuild = function(g) purged = g end,
      }
      Comm.Broadcast = function(_, isLoginAnnounce)
        broadcastCount = broadcastCount + 1
        lastLoginAnnounce = isLoginAnnounce == true
      end
      Comm.NotifyDataChanged = function() end
      -- Sync module knownGuild to nil so tests do not depend on order.
      _G.IsInGuild = function() return false end
      _G.GetGuildInfo = function() return nil end
      Comm._HandlePlayerGuildUpdate()
      broadcastCount = 0
      lastLoginAnnounce = nil
      purged = nil
      _G.IsInGuild = function() return true end
      _G.GetGuildInfo = function() return "NewGuild" end
    end)

    after_each(function()
      Comm.Broadcast = realBroadcast
    end)

    it("broadcasts once when guild membership changes", function()
      Comm._HandlePlayerGuildUpdate()
      assert.are.equal(1, broadcastCount)
      Comm._HandlePlayerGuildUpdate()
      assert.are.equal(1, broadcastCount, "duplicate PLAYER_GUILD_UPDATE should not rebroadcast")
    end)

    it("login-announces when guild name becomes available (login race)", function()
      -- Simulate PEW having set knownGuild=nil because GetGuildInfo was not ready yet.
      _G.GetGuildInfo = function() return nil end
      Comm._HandlePlayerGuildUpdate()
      assert.are.equal(0, broadcastCount)
      _G.GetGuildInfo = function() return "Reign of Error" end
      Comm._HandlePlayerGuildUpdate()
      assert.are.equal(1, broadcastCount)
      assert.is_true(lastLoginAnnounce)
    end)

    it("does not broadcast when leaving a guild", function()
      Comm._HandlePlayerGuildUpdate()
      assert.are.equal(1, broadcastCount)
      _G.GetGuildInfo = function() return nil end
      _G.IsInGuild = function() return false end
      Comm._HandlePlayerGuildUpdate()
      assert.are.equal(1, broadcastCount, "leave must not send a GUILD clear")
      assert.are.equal("NewGuild", purged)
    end)
  end)

  describe("Broadcast guild gate", function()
    local sent

    before_each(function()
      sent = {}
      Comm._TestHookSend = function(msgType, payload, distribution)
        sent[#sent + 1] = { msgType = msgType, payload = payload, distribution = distribution }
      end
      AltArmy.Debug = {
        IsGuildShareEnabled = function() return true end,
        LogGuildShare = function() end,
      }
      AltArmy.GuildShareSettings = {
        GetShareableCharacters = function() return {} end,
        GetAllGuildedCharacters = function() return {} end,
        ResolvePresenceMainAndDisplay = function() return nil, nil end,
      }
      AltArmy.GuildShareProtocol = {
        BuildPresence = function(chars, main, displayName)
          return { v = 1, main = main, displayName = displayName, chars = chars or {} }
        end,
      }
      _G.GetRealmName = function() return "R" end
      _G.GetTime = function() return 100 end
    end)

    after_each(function()
      Comm._TestHookSend = nil
    end)

    it("does not send when IsInGuild is true but guild name is nil", function()
      _G.IsInGuild = function() return true end
      _G.GetGuildInfo = function() return nil end
      Comm.Broadcast(true, true)
      assert.are.equal(0, #sent)
    end)

    it("sends when both IsInGuild and guild name are available", function()
      _G.IsInGuild = function() return true end
      _G.GetGuildInfo = function() return "Reign of Error" end
      Comm.Broadcast(true, true)
      assert.are.equal(1, #sent)
      assert.are.equal("P", sent[1].msgType)
      assert.are.equal("GUILD", sent[1].distribution)
      assert.is_true(sent[1].payload.login)
    end)
  end)

  describe("_NormalizeSender", function()
    it("strips a realm suffix", function()
      assert.are.equal("Bob", Comm._NormalizeSender("Bob-Faerlina"))
      assert.are.equal("Bob", Comm._NormalizeSender("Bob"))
    end)
  end)

  describe("_IsLocalSender", function()
    it("matches the player name with or without a realm suffix", function()
      _G.UnitName = function() return "Bob-Faerlina" end
      assert.is_true(Comm._IsLocalSender("Bob"))
      assert.is_true(Comm._IsLocalSender("Bob-Faerlina"))
      assert.is_false(Comm._IsLocalSender("Alice"))
    end)

    it("returns false when the player name is unavailable", function()
      _G.UnitName = function() return "" end
      assert.is_false(Comm._IsLocalSender("Bob"))
    end)
  end)

  describe("_FormatMsgType", function()
    it("includes a human-readable label for known message types", function()
      assert.are.equal("P (presence)", Comm._FormatMsgType("P"))
      assert.are.equal("PR (presence reply)", Comm._FormatMsgType("PR"))
      assert.are.equal("RQ (recipe request)", Comm._FormatMsgType("RQ"))
      assert.are.equal("RC (recipes)", Comm._FormatMsgType("RC"))
      assert.are.equal("CQ (char card request)", Comm._FormatMsgType("CQ"))
      assert.are.equal("CC (char card)", Comm._FormatMsgType("CC"))
    end)

    it("returns unknown types unchanged", function()
      assert.are.equal("??", Comm._FormatMsgType("??"))
    end)
  end)

  describe("_FormatUndecodableRecvLog", function()
    it("includes prefix, distribution, byte length, deserialize reason, and message head", function()
      local msg = "not-ace-serializer-payload"
      local line = Comm._FormatUndecodableRecvLog(
        "AltArmyGS", msg, "GUILD", "Orfiman", false, "Supplied data is not AceSerializer data (rev 1)"
      )
      assert.truthy(line:find("recv %(undecodable%) from Orfiman", 1, false))
      assert.truthy(line:find("prefix=AltArmyGS", 1, true))
      assert.truthy(line:find("dist=GUILD", 1, true))
      assert.truthy(line:find("bytes=" .. #msg, 1, true))
      assert.truthy(line:find("reason=Supplied data is not AceSerializer data (rev 1)", 1, true))
      assert.truthy(line:find("head=not-ace-serializer-payload", 1, true))
    end)

    it("truncates a long message head and reports msgType type when deserialize ok but type wrong", function()
      local msg = string.rep("x", 80)
      local line = Comm._FormatUndecodableRecvLog(
        "AltArmyGS", msg, "WHISPER", "Bob", true, 42
      )
      assert.truthy(line:find("dist=WHISPER", 1, true))
      assert.truthy(line:find("bytes=80", 1, true))
      assert.truthy(line:find("reason=msgType=number", 1, true))
      assert.truthy(line:find("head=" .. string.rep("x", 48) .. "...", 1, true))
      assert.is_nil(line:find(string.rep("x", 49), 1, true))
    end)
  end)

  describe("_BuildUndecodableDump", function()
    it("captures the full raw message plus receive metadata", function()
      local msg = "^1^SP^T^Schars^T^N1^T^SclassFile^SPALADIN^t^t^^"
      local dump = Comm._BuildUndecodableDump(
        "AltArmyGS", msg, "GUILD", "Orfinam", false,
        "Invalid AceSerializer control code '^t'"
      )
      assert.are.equal(1, dump.version)
      assert.are.equal("AltArmyGS", dump.prefix)
      assert.are.equal("GUILD", dump.distribution)
      assert.are.equal("Orfinam", dump.sender)
      assert.are.equal(#msg, dump.bytes)
      assert.are.equal(msg, dump.message)
      assert.is_false(dump.deserializeOk)
      assert.are.equal("Invalid AceSerializer control code '^t'", dump.reason)
      assert.truthy(dump.head:find("^1^SP", 1, true))
      assert.truthy(dump.timestamp)
    end)
  end)

  describe("_ShouldRespondToRecipeRequest", function()
    local flagOn, sharingEnabled

    before_each(function()
      flagOn = true
      sharingEnabled = true
      AltArmy.Debug = {
        IsGuildShareEnabled = function() return flagOn end,
      }
      AltArmy.GuildShareSettings = {
        IsSharingEnabled = function() return sharingEnabled end,
      }
    end)

    it("is true when the feature flag is off", function()
      flagOn = false
      sharingEnabled = false
      assert.is_true(Comm._ShouldRespondToRecipeRequest())
    end)

    it("is false when the feature flag is on and sharing is disabled", function()
      sharingEnabled = false
      assert.is_false(Comm._ShouldRespondToRecipeRequest())
    end)

    it("is true when the feature flag is on and sharing is enabled", function()
      assert.is_true(Comm._ShouldRespondToRecipeRequest())
    end)
  end)

  describe("_IsInboundAllowed", function()
    local flagOn

    before_each(function()
      flagOn = true
      AltArmy.Debug = {
        IsGuildShareEnabled = function() return flagOn end,
      }
    end)

    it("allows RQ and CQ regardless of the feature flag", function()
      flagOn = false
      assert.is_true(Comm._IsInboundAllowed("RQ"))
      assert.is_true(Comm._IsInboundAllowed("CQ"))
    end)

    it("blocks P, PR, RC, and CC when the feature flag is off", function()
      flagOn = false
      assert.is_false(Comm._IsInboundAllowed("P"))
      assert.is_false(Comm._IsInboundAllowed("PR"))
      assert.is_false(Comm._IsInboundAllowed("RC"))
      assert.is_false(Comm._IsInboundAllowed("CC"))
    end)

    it("allows all message types when the feature flag is on", function()
      assert.is_true(Comm._IsInboundAllowed("P"))
      assert.is_true(Comm._IsInboundAllowed("PR"))
      assert.is_true(Comm._IsInboundAllowed("RQ"))
      assert.is_true(Comm._IsInboundAllowed("RC"))
      assert.is_true(Comm._IsInboundAllowed("CQ"))
      assert.is_true(Comm._IsInboundAllowed("CC"))
    end)
  end)

  describe("_DispatchReceivedMessage", function()
    local saved, notifyCount, presenceMatches

    before_each(function()
      saved = {}
      notifyCount = 0
      presenceMatches = false
      _G.UnitName = function() return "Bob" end
      AltArmy.Debug = {
        IsGuildShareEnabled = function() return true end,
        LogGuildShare = function() end,
      }
      AltArmy.GuildShareProtocol = {
        ParsePresence = function(msg) return msg end,
        ParseRecipes = function(msg) return msg end,
        BuildPresence = function(chars, main, displayName)
          return { v = 1, main = main, displayName = displayName, chars = chars or {} }
        end,
        BuildRecipes = function(name, realm, char)
          return { v = 1, name = name, realm = realm, profs = {} }
        end,
      }
      AltArmy.GuildShareData = {
        SaveReceived = function(sender, presence)
          saved.received = { sender = sender, presence = presence }
        end,
        SaveRecipes = function(_, payload)
          saved.recipes = payload
        end,
        GetProfessionsNeedingRecipes = function() return {} end,
        PresenceMatchesStored = function()
          return presenceMatches
        end,
        TouchReceivedAt = function(sender, presence, realm)
          saved.touched = { sender = sender, presence = presence, realm = realm }
          return true
        end,
      }
      Comm.NotifyDataChanged = function()
        notifyCount = notifyCount + 1
      end
      AltArmy.GuildShareSettings = {
        GetShareableCharacters = function() return {} end,
        GetAllGuildedCharacters = function() return {} end,
        ResolvePresenceMainAndDisplay = function() return nil, nil end,
      }
      _G.GetGuildInfo = function() return "G" end
      _G.GetRealmName = function() return "R" end
    end)

    it("ignores presence messages from the local player", function()
      Comm._DispatchReceivedMessage("P", { chars = { { name = "Bob" } } }, "Bob")
      assert.is_nil(saved.received)
    end)

    it("stores presence from other players", function()
      Comm._DispatchReceivedMessage("P", { chars = { { name = "Alice" } } }, "Alice")
      assert.truthy(saved.received)
      assert.are.equal("Alice", saved.received.sender)
    end)

    it("touches receivedAt and notifies without SaveReceived when presence matches", function()
      presenceMatches = true
      Comm._DispatchReceivedMessage("P", { chars = { { name = "Alice" } } }, "Alice")
      assert.is_nil(saved.received)
      assert.truthy(saved.touched)
      assert.are.equal("Alice", saved.touched.sender)
      assert.are.equal("R", saved.touched.realm)
      assert.are.equal(1, notifyCount)
    end)

    it("does not notify when TouchReceivedAt finds nothing to bump", function()
      presenceMatches = true
      AltArmy.GuildShareData.TouchReceivedAt = function()
        return false
      end
      Comm._DispatchReceivedMessage("P", { chars = { { name = "Alice" } } }, "Alice")
      assert.is_nil(saved.received)
      assert.are.equal(0, notifyCount)
    end)

    it("calls NotifyDataChanged when presence changed", function()
      presenceMatches = false
      Comm._DispatchReceivedMessage("P", { chars = { { name = "Alice" } } }, "Alice")
      assert.are.equal(1, notifyCount)
    end)

    it("whispers a presence reply to a login announce even when stored data matches", function()
      presenceMatches = true
      AltArmy.GuildShareSettings.GetShareableCharacters = function()
        return { { name = "Bob", realm = "R", char = { name = "Bob", Professions = {} } } }
      end
      AltArmy.GuildShareSettings.ResolvePresenceMainAndDisplay = function()
        return "Bob", "Bobby"
      end
      local sent = {}
      Comm._TestHookSend = function(msgType, payload, distribution, target)
        sent[#sent + 1] = {
          msgType = msgType, payload = payload, distribution = distribution, target = target,
        }
      end
      Comm._DispatchReceivedMessage("P", {
        v = 1, login = true, chars = { { name = "Alice" } },
      }, "Alice")
      Comm._TestHookSend = nil
      assert.is_nil(saved.received)
      assert.truthy(saved.touched)
      assert.are.equal(1, notifyCount)
      assert.are.equal(1, #sent)
      assert.are.equal("PR", sent[1].msgType)
      assert.are.equal("WHISPER", sent[1].distribution)
      assert.are.equal("Alice", sent[1].target)
    end)

    it("does not whisper a presence reply for an unchanged non-login broadcast", function()
      local sent = {}
      presenceMatches = true
      AltArmy.GuildShareSettings.GetShareableCharacters = function()
        return { { name = "Bob", realm = "R", char = { name = "Bob", Professions = {} } } }
      end
      Comm._TestHookSend = function(msgType, payload, distribution, target)
        sent[#sent + 1] = { msgType = msgType, distribution = distribution, target = target }
      end
      Comm._DispatchReceivedMessage("P", {
        v = 1, chars = { { name = "Alice" } },
      }, "Alice")
      Comm._TestHookSend = nil
      assert.are.equal(0, #sent)
    end)

    it("does not whisper a presence reply to a PR even when login is set", function()
      local sent = {}
      presenceMatches = true
      AltArmy.GuildShareSettings.GetShareableCharacters = function()
        return { { name = "Bob", realm = "R", char = { name = "Bob", Professions = {} } } }
      end
      Comm._TestHookSend = function(msgType, payload, distribution, target)
        sent[#sent + 1] = { msgType = msgType }
      end
      Comm._DispatchReceivedMessage("PR", {
        v = 1, login = true, chars = { { name = "Alice" } },
      }, "Alice")
      Comm._TestHookSend = nil
      assert.are.equal(0, #sent)
    end)

    it("handles RQ when receive flag is off by selecting all-guilded characters", function()
      local flagOn = true
      local rcBuilt = false
      AltArmy.DataStore = {}
      AltArmy.Debug.IsGuildShareEnabled = function() return flagOn end
      AltArmy.GuildShareSettings.GetAllGuildedCharacters = function()
        return { { name = "Alice", char = { name = "Alice", Professions = {} } } }
      end
      AltArmy.GuildShareSettings.GetShareableCharacters = function()
        return {}
      end
      AltArmy.GuildShareSettings.IsSharingEnabled = function() return false end
      AltArmy.GuildShareProtocol.BuildRecipes = function(name, realm)
        rcBuilt = true
        return { v = 1, name = name, realm = realm, profs = {} }
      end
      flagOn = false
      Comm._DispatchReceivedMessage("RQ", { name = "Alice", realm = "R" }, "Alice")
      assert.is_true(rcBuilt)
      assert.is_nil(saved.received)
    end)

    it("does not build RC for RQ when flag is on and sharing is disabled", function()
      local rcBuilt = false
      AltArmy.DataStore = {}
      AltArmy.GuildShareSettings.IsSharingEnabled = function() return false end
      AltArmy.GuildShareProtocol.BuildRecipes = function(name, realm)
        rcBuilt = true
        return { v = 1, name = name, realm = realm, profs = {} }
      end
      Comm._DispatchReceivedMessage("RQ", { name = "Alice", realm = "R" }, "Alice")
      assert.is_false(rcBuilt)
    end)

    it("builds RC for RQ when flag is on, sharing enabled, and character is shareable", function()
      local rcBuilt = false
      AltArmy.DataStore = {}
      AltArmy.GuildShareSettings.IsSharingEnabled = function() return true end
      AltArmy.GuildShareSettings.GetShareableCharacters = function()
        return { { name = "Alice", char = { name = "Alice", Professions = {} } } }
      end
      AltArmy.GuildShareProtocol.BuildRecipes = function(name, realm)
        rcBuilt = true
        return { v = 1, name = name, realm = realm, profs = {} }
      end
      Comm._DispatchReceivedMessage("RQ", { name = "Alice", realm = "R" }, "Alice")
      assert.is_true(rcBuilt)
    end)

    it("whispers CQ for slim presence chars that need a profession card", function()
      local sent = {}
      local realOnline = Comm.IsGuildMemberOnline
      Comm.IsGuildMemberOnline = function() return true end
      AltArmy.GuildShareProtocol.ParsePresence = function(msg) return msg end
      AltArmy.GuildShareProtocol.BuildCharCardRequest = function(name, realm)
        return { v = 2, name = name, realm = realm }
      end
      AltArmy.GuildShareData.CharsNeedingProfessionCard = function()
        return { { name = "Alice", realm = "R" } }
      end
      Comm._TestHookSend = function(msgType, payload, distribution, target)
        sent[#sent + 1] = {
          msgType = msgType, payload = payload, distribution = distribution, target = target,
        }
      end
      Comm._DispatchReceivedMessage("P", {
        v = 2, chars = { { name = "Alice", ch = 1 } },
      }, "Alice")
      Comm._TestHookSend = nil
      Comm.IsGuildMemberOnline = realOnline
      local cq
      for _, s in ipairs(sent) do
        if s.msgType == "CQ" then cq = s end
      end
      assert.truthy(cq)
      assert.are.equal("WHISPER", cq.distribution)
      assert.are.equal("Alice", cq.target)
      assert.are.equal("Alice", cq.payload.name)
    end)

    it("does not whisper CQ for legacy fat v1 presence", function()
      local sent = {}
      local realOnline = Comm.IsGuildMemberOnline
      Comm.IsGuildMemberOnline = function() return true end
      AltArmy.GuildShareProtocol.ParsePresence = function(msg) return msg end
      AltArmy.GuildShareData.CharsNeedingProfessionCard = function()
        return {}
      end
      Comm._TestHookSend = function(msgType, payload, distribution, target)
        sent[#sent + 1] = { msgType = msgType }
      end
      Comm._DispatchReceivedMessage("P", {
        v = 1, chars = { { name = "Alice", profs = { { key = "tailoring", rank = 1 } } } },
      }, "Alice")
      Comm._TestHookSend = nil
      Comm.IsGuildMemberOnline = realOnline
      for _, s in ipairs(sent) do
        assert.are_not.equal("CQ", s.msgType)
      end
    end)

    it("builds CC for CQ when flag is on, sharing enabled, and character is shareable", function()
      local ccBuilt = false
      AltArmy.GuildShareSettings.IsSharingEnabled = function() return true end
      AltArmy.GuildShareSettings.GetShareableCharacters = function()
        return { { name = "Alice", char = { name = "Alice", classFile = "MAGE", Professions = {} } } }
      end
      AltArmy.GuildShareProtocol.ParseCharCardRequest = function(msg) return msg end
      AltArmy.GuildShareProtocol.BuildCharCard = function(name, realm)
        ccBuilt = true
        return { v = 2, name = name, realm = realm, ch = 1, profs = {} }
      end
      Comm._DispatchReceivedMessage("CQ", { v = 2, name = "Alice", realm = "R" }, "Peer")
      assert.is_true(ccBuilt)
    end)

    it("saves CC and notifies data changed", function()
      local savedCard
      AltArmy.GuildShareProtocol.ParseCharCard = function(msg) return msg end
      AltArmy.GuildShareData.SaveCharCard = function(sender, card)
        savedCard = { sender = sender, card = card }
      end
      local realOnline = Comm.IsGuildMemberOnline
      Comm.IsGuildMemberOnline = function() return false end
      Comm._DispatchReceivedMessage("CC", {
        v = 2, name = "Alice", realm = "R", ch = 1, profs = {},
      }, "Peer")
      Comm.IsGuildMemberOnline = realOnline
      assert.truthy(savedCard)
      assert.are.equal("Peer", savedCard.sender)
      assert.are.equal("Alice", savedCard.card.name)
      assert.are.equal(1, notifyCount)
    end)
  end)

  describe("RequestGuildRoster", function()
    local savedInfo, savedRoster

    before_each(function()
      savedInfo, savedRoster = _G.C_GuildInfo, _G.GuildRoster
    end)

    after_each(function()
      _G.C_GuildInfo, _G.GuildRoster = savedInfo, savedRoster
    end)

    it("uses C_GuildInfo.GuildRoster where the client has it (WoW Forever has no GuildRoster global)", function()
      local calls = 0
      _G.C_GuildInfo = { GuildRoster = function() calls = calls + 1 end }
      _G.GuildRoster = nil
      assert.is_true(Comm.RequestGuildRoster())
      assert.are.equal(1, calls)
    end)

    it("falls back to the GuildRoster global, and says when neither exists", function()
      local calls = 0
      _G.C_GuildInfo = nil
      _G.GuildRoster = function() calls = calls + 1 end
      assert.is_true(Comm.RequestGuildRoster())
      assert.are.equal(1, calls)
      _G.GuildRoster = nil
      assert.is_false(Comm.RequestGuildRoster())
    end)
  end)

  describe("_PickSampleProfChar", function()
    it("returns nil when there is no DataStore", function()
      AltArmy.DataStore = nil
      assert.is_nil(Comm._PickSampleProfChar("R"))
    end)

    it("picks the character with the most professions", function()
      AltArmy.DataStore = {
        GetCharacters = function()
          return {
            NoProf = { Professions = {} },
            One = { Professions = { Tailoring = {} } },
            Two = { name = "Two", Professions = { Alchemy = {}, Herbalism = {} } },
          }
        end,
      }
      local char = Comm._PickSampleProfChar("R")
      assert.truthy(char)
      assert.are.equal("Two", char.name)
    end)
  end)

  describe("InjectTestPresence", function()
    local flagOn, saved

    before_each(function()
      flagOn = true
      saved = {}
      _G.GetRealmName = function() return "TestRealm" end
      _G.GetGuildInfo = function() return nil end
      AltArmy.Debug = {
        IsGuildShareEnabled = function() return flagOn end,
        LogGuildShare = function() end,
      }
      AltArmy.GuildShareProtocol = {
        VERSION = 1,
        BuildProfessionSummaries = function() return {} end,
        BuildRecipes = function(name, realm) return { v = 1, name = name, realm = realm, profs = {} } end,
        ParsePresence = function(msg) return msg end,
      }
      AltArmy.GuildShareData = {
        SaveReceived = function(sender, presence, guild, realm)
          saved.received = { sender = sender, presence = presence, guild = guild, realm = realm }
        end,
        SaveRecipes = function(realm, payload)
          saved.recipes = { realm = realm, payload = payload }
        end,
      }
      AltArmy.DataStore = nil
      AltArmy.SearchData = nil
      AltArmy.RefreshGuildTab = nil
    end)

    it("does nothing and reports flag-off when the feature flag is OFF", function()
      flagOn = false
      local ok, reason = Comm.InjectTestPresence()
      assert.is_false(ok)
      assert.are.equal("flag-off", reason)
      assert.is_nil(saved.received)
    end)

    it("stores a synthetic main + alt through the receive/store path when the flag is ON", function()
      local ok = Comm.InjectTestPresence()
      assert.is_true(ok)
      assert.truthy(saved.received)
      assert.are.equal("AltArmy Test Guild", saved.received.guild)
      assert.are.equal("TestRealm", saved.received.realm)
      assert.are.equal(2, #saved.received.presence.chars)
      -- No local characters to sample -> no recipe payload.
      assert.is_nil(saved.recipes)
    end)

    it("seeds recipes from a local character when one with professions exists", function()
      AltArmy.DataStore = {
        GetCharacters = function()
          return { Me = { name = "Me", Professions = { Tailoring = {} } } }
        end,
      }
      local ok = Comm.InjectTestPresence()
      assert.is_true(ok)
      assert.truthy(saved.recipes)
      assert.are.equal("AAtestmain", saved.recipes.payload.name)
    end)
  end)

  describe("unchanged presence (integration)", function()
    local GSD, P
    local NOW = 1700000000

    local function presence(main, chars)
      return { v = 1, main = main, displayName = main, chars = chars }
    end

    local function charEntry(name, profs)
      return { name = name, realm = "R", classFile = "MAGE", faction = "Alliance", level = 70, profs = profs or {} }
    end

    setup(function()
      _G.time = function() return NOW end
      package.loaded["GuildShareProtocol"] = nil
      package.loaded["GuildShareData"] = nil
      require("GuildShareProtocol")
      require("GuildShareData")
      GSD = AltArmy.GuildShareData
      P = AltArmy.GuildShareProtocol
    end)

    before_each(function()
      _G.AltArmyTBC_GuildData = nil
      GSD._Ensure()
      -- Restore real protocol/data after other describes may have stubbed them.
      AltArmy.GuildShareProtocol = P
      AltArmy.GuildShareData = GSD
      _G.UnitName = function() return "Bob" end
      _G.GetGuildInfo = function() return "MyGuild" end
      _G.GetRealmName = function() return "R" end
      AltArmy.Debug = {
        IsGuildShareEnabled = function() return true end,
        LogGuildShare = function() end,
      }
      AltArmy.GuildShareSettings = {
        GetShareableCharacters = function() return {} end,
        GetAllGuildedCharacters = function() return {} end,
        ResolvePresenceMainAndDisplay = function() return nil, nil end,
      }
    end)

    it("does not re-save when presence matches stored data", function()
      local rv = P.HashRecipeIDs({ 100, 200 })
      local msg = P.ParsePresence(presence("Peer", {
        charEntry("Peer", { { key = "tailoring", rank = 375, count = 2, rv = rv } }),
        charEntry("PeerAlt"),
      }))
      GSD.SaveReceived("Alice", msg, "MyGuild", "R")
      GSD.SaveRecipes("R", { v = 1, name = "Peer", profs = { { key = "tailoring", ids = { 100, 200 } } } })
      assert.are.equal(2, #GSD.GetGuildMembers("MyGuild"))

      _G.GetGuildInfo = function() return nil end
      Comm._DispatchReceivedMessage("P", msg, "Alice")

      assert.are.equal(2, #GSD.GetGuildMembers("MyGuild"))
      assert.are.equal("MyGuild", GSD.GetCharacter("Peer", "R").guildName)
      assert.truthy(GSD.GetCharacter("Peer", "R").Professions.tailoring.Recipes[100])
    end)

    it("bumps receivedAt without requesting recipes when presence matches", function()
      local rv = P.HashRecipeIDs({ 100, 200 })
      local msg = P.ParsePresence(presence("Peer", {
        charEntry("Peer", { { key = "tailoring", rank = 375, count = 2, rv = rv } }),
      }))
      GSD.SaveReceived("Alice", msg, "MyGuild", "R")
      GSD.SaveRecipes("R", { v = 1, name = "Peer", profs = { { key = "tailoring", ids = { 100, 200 } } } })
      GSD.GetCharacter("Peer", "R").receivedAt = NOW - 20 * 24 * 60 * 60

      local sent = {}
      Comm._TestHookSend = function(msgType, payload, distribution, target)
        sent[#sent + 1] = { msgType = msgType, target = target }
      end
      Comm._DispatchReceivedMessage("P", msg, "Alice")
      Comm._TestHookSend = nil

      assert.are.equal(NOW, GSD.GetCharacter("Peer", "R").receivedAt)
      assert.truthy(GSD.GetCharacter("Peer", "R").Professions.tailoring.Recipes[100])
      for _, s in ipairs(sent) do
        assert.are_not.equal("RQ", s.msgType)
        assert.are_not.equal("CQ", s.msgType)
      end
    end)
  end)

  describe("IsGuildMemberOnline", function()
    before_each(function()
      _G.IsInGuild = function() return true end
      _G.UnitName = function() return "Bob" end
    end)

    it("returns true when the member is online in the guild roster", function()
      _G.GetNumGuildMembers = function() return 1 end
      _G.GetGuildRosterInfo = function()
        return "Alice", nil, nil, nil, nil, nil, nil, nil, true
      end
      assert.is_true(Comm.IsGuildMemberOnline("Alice"))
    end)

    it("returns false when the member is offline", function()
      _G.GetNumGuildMembers = function() return 1 end
      _G.GetGuildRosterInfo = function()
        return "Alice", nil, nil, nil, nil, nil, nil, nil, false
      end
      assert.is_false(Comm.IsGuildMemberOnline("Alice"))
    end)
  end)

  describe("RequestRecipesForCharacter", function()
    before_each(function()
      _G.IsInGuild = function() return true end
      _G.UnitName = function() return "Bob" end
      _G.GetNumGuildMembers = function() return 1 end
      _G.GetGuildRosterInfo = function()
        return "Alice", nil, nil, nil, nil, nil, nil, nil, true
      end
    end)

    it("marks recipes requested when sender is online and recipes are needed", function()
      local marked
      AltArmy.GuildShareData = {
        GetProfessionsNeedingRecipes = function() return { "tailoring" } end,
        MarkRecipesRequested = function(name, realm, keys)
          marked = { name = name, realm = realm, keys = keys }
        end,
      }
      assert.is_true(Comm.RequestRecipesForCharacter("Alt", "R", "Alice"))
      assert.are.same({ name = "Alt", realm = "R", keys = { "tailoring" } }, marked)
    end)

    it("does nothing when sender is offline", function()
      _G.GetGuildRosterInfo = function()
        return "Alice", nil, nil, nil, nil, nil, nil, nil, false
      end
      local marked = false
      AltArmy.GuildShareData = {
        GetProfessionsNeedingRecipes = function() return { "tailoring" } end,
        MarkRecipesRequested = function() marked = true end,
      }
      assert.is_false(Comm.RequestRecipesForCharacter("Alt", "R", "Alice"))
      assert.is_false(marked)
    end)
  end)

  describe("character IDs", function()
    local saved, sent

    before_each(function()
      saved, sent = {}, {}
      _G.UnitName = function() return "Frell", "Blast" end
      _G.UnitGUID = function(unit) if unit == "player" then return "Player-1-B" end end
      AltArmy.DataStore = {}
      AltArmy.Debug = {
        IsGuildShareEnabled = function() return true end,
        LogGuildShare = function() end,
      }
      AltArmy.GuildShareProtocol = {
        ParsePresence = function(msg) return msg end,
        ParseCharCardRequest = function(msg) return msg end,
        BuildPresence = function(chars) return { v = 2, chars = chars or {} } end,
        BuildRecipes = function(name, realm, char)
          saved.recipesFor = { name = name, char = char }
          return { v = 1, name = name, realm = realm, guid = char and char.guid, profs = {} }
        end,
        BuildCharCard = function(name, realm, char)
          saved.cardFor = { name = name, char = char }
          return { v = 2, name = name, realm = realm, ch = 1, profs = {} }
        end,
        BuildCharCardRequest = function(name, realm, guid)
          return { v = 2, name = name, realm = realm, guid = guid }
        end,
      }
      AltArmy.GuildShareData = {
        SaveReceived = function(sender, presence) saved.received = { sender = sender, presence = presence } end,
        PresenceMatchesStored = function() return false end,
        CharsNeedingProfessionCard = function() return {} end,
        GetProfessionsNeedingRecipes = function(nameOrKey)
          saved.neededFor = nameOrKey
          return { "tailoring" }
        end,
        MarkRecipesRequested = function(nameOrKey) saved.markedFor = nameOrKey end,
      }
      Comm.NotifyDataChanged = function() end
      AltArmy.GuildShareSettings = {
        IsSharingEnabled = function() return true end,
        GetShareableCharacters = function()
          return { { name = "Frell Blast", char = { name = "Frell Blast", guid = "Player-1-B", Professions = {} } } }
        end,
        GetAllGuildedCharacters = function() return {} end,
        ResolvePresenceMainAndDisplay = function() return nil, nil end,
      }
      _G.GetGuildInfo = function() return "G" end
      _G.GetRealmName = function() return "R" end
      Comm._TestHookSend = function(msgType, payload, distribution, target)
        sent[#sent + 1] = { msgType = msgType, payload = payload, distribution = distribution, target = target }
      end
    end)

    after_each(function()
      Comm._TestHookSend = nil
      _G.UnitGUID = nil
    end)

    it("does not ignore another player who shares my short name", function()
      Comm._DispatchReceivedMessage("P", { from = "Player-9-X", chars = { { name = "Frell Hound" } } }, "Frell")
      assert.truthy(saved.received)
    end)

    it("ignores my own messages by ID, whatever name they arrive under", function()
      Comm._DispatchReceivedMessage("P", { from = "Player-1-B", chars = { { name = "Frell Blast" } } }, "Frelly")
      assert.is_nil(saved.received)
    end)

    it("still ignores my own messages by name when they carry no ID", function()
      Comm._DispatchReceivedMessage("P", { chars = { { name = "Frell Blast" } } }, "Frell")
      assert.is_nil(saved.received)
    end)

    it("stamps outgoing messages with my ID", function()
      local realOnline = Comm.IsGuildMemberOnline
      Comm.IsGuildMemberOnline = function() return true end
      Comm.RequestCharCard("Frell Hound", "R", "Frell", "Player-9-X")
      Comm.IsGuildMemberOnline = realOnline
      assert.are.equal(1, #sent)
      assert.are.equal("Player-1-B", sent[1].payload.from)
      assert.are.equal("Player-9-X", sent[1].payload.guid)
    end)

    it("requests recipes by ID and tracks them under that ID", function()
      local realOnline = Comm.IsGuildMemberOnline
      Comm.IsGuildMemberOnline = function() return true end
      Comm.RequestRecipesForCharacter("Frell Hound", "R", "Frell", "Player-9-X")
      Comm.IsGuildMemberOnline = realOnline
      assert.are.equal("Player-9-X", saved.neededFor)
      assert.are.equal("Player-9-X", saved.markedFor)
      assert.are.equal("RQ", sent[1].msgType)
      assert.are.same("Frell Hound", sent[1].payload.name)
      assert.are.same("Player-9-X", sent[1].payload.guid)
    end)

    it("answers recipe and card requests by ID even under an old name", function()
      Comm._DispatchReceivedMessage("RQ", { name = "Frell", realm = "R", guid = "Player-1-B" }, "Peer")
      assert.truthy(saved.recipesFor)
      -- Echo the requested name: an older requester stored the character under it.
      assert.are.equal("Frell", saved.recipesFor.name)
      Comm._DispatchReceivedMessage("CQ", { v = 2, name = "Frell", realm = "R", guid = "Player-1-B" }, "Peer")
      assert.truthy(saved.cardFor)
    end)

    describe("coalesced realms (WoW Forever)", function()
      local MINE, THEIRS = "CAMWOW US1 Realm 5 PvE", "CAMWOW US2 Realm 3 PvE"
      local savedRF

      before_each(function()
        savedRF = AltArmy.RealmFilter
        local function group(r) return ((r or ""):gsub("US%d Realm %d+", "US")) end
        AltArmy.RealmFilter = { realmGroup = group, sameRealm = function(a, b) return group(a) == group(b) end }
        AltArmy.DataStore = { GetRealms = function() return { [MINE] = true, ["CAMWOW EU1 Realm 1 PvE"] = true } end }
        AltArmy.GuildShareSettings.GetShareableCharacters = function(_, realm)
          if realm ~= MINE then return {} end
          return { { name = "Frell Blast", realm = MINE,
            char = { name = "Frell Blast", guid = "Player-1-B", Professions = {} } } }
        end
      end)

      after_each(function() AltArmy.RealmFilter = savedRF end)

      it("answers a request naming another coalesced realm, echoing that realm", function()
        Comm._DispatchReceivedMessage("CQ", { v = 2, name = "Frell Blast", realm = THEIRS, guid = "Player-1-B" },
          "Kairu Stormhoof")
        assert.truthy(saved.cardFor)
        assert.are.equal("CC", sent[1].msgType)
        assert.are.equal(THEIRS, sent[1].payload.realm)
        Comm._DispatchReceivedMessage("RQ", { name = "Frell Blast", realm = THEIRS, guid = "Player-1-B" },
          "Kairu Stormhoof")
        assert.truthy(saved.recipesFor)
      end)

      it("does not answer for a realm of another group", function()
        Comm._DispatchReceivedMessage("CQ", { v = 2, name = "Frell Blast", realm = "CAMWOW EU1 Realm 1 PvE",
          guid = "Player-1-B" }, "Kairu Stormhoof")
        assert.is_nil(saved.cardFor)
      end)

      it("asks for recipes naming the realm the character reports", function()
        AltArmy.GuildShareData.GetCharacter = function() return { charRealm = THEIRS } end
        local realOnline = Comm.IsGuildMemberOnline
        Comm.IsGuildMemberOnline = function() return true end
        Comm.RequestRecipesForCharacter("Kairu Stormhoof", MINE, "Kairu Stormhoof", "Player-6929-K")
        Comm.IsGuildMemberOnline = realOnline
        assert.are.equal("RQ", sent[1].msgType)
        assert.are.equal(THEIRS, sent[1].payload.realm)
      end)
    end)

    it("does not answer a request whose ID belongs to another character", function()
      Comm._DispatchReceivedMessage("RQ", { name = "Frell Blast", realm = "R", guid = "Player-1-Z" }, "Peer")
      assert.is_nil(saved.recipesFor)
    end)

    it("asks for profession cards by ID", function()
      local realOnline = Comm.IsGuildMemberOnline
      Comm.IsGuildMemberOnline = function() return true end
      AltArmy.GuildShareData.CharsNeedingProfessionCard = function()
        return { { name = "Frell Hound", realm = "R", guid = "Player-9-X" } }
      end
      Comm._DispatchReceivedMessage("P", {
        v = 2, from = "Player-9-X", chars = { { name = "Frell Hound", guid = "Player-9-X", ch = 1 } },
      }, "Frell")
      Comm.IsGuildMemberOnline = realOnline
      local cq
      for _, s in ipairs(sent) do if s.msgType == "CQ" then cq = s end end
      assert.truthy(cq)
      assert.are.equal("Player-9-X", cq.payload.guid)
    end)
  end)
  describe("asking again (SweepPending)", function()
    local sent, entries, due, realOnline

    before_each(function()
      sent, entries, due = {}, {}, true
      _G.IsInGuild = function() return true end
      _G.GetRealmName = function() return "R" end
      _G.GetGuildInfo = function() return "G" end
      _G.UnitName = function() return "Me" end
      realOnline = Comm.IsGuildMemberOnline
      Comm.IsGuildMemberOnline = function(name) return name ~= "Gone" end
      AltArmy.GuildShareSettings = {}
      AltArmy.GuildShareProtocol = {
        BuildCharCardRequest = function(name, realm, guid) return { v = 2, name = name, realm = realm, guid = guid } end,
      }
      AltArmy.GuildShareData = {
        SharedCharactersInGroup = function() return entries end,
        CardRetryDue = function() return due end,
        GetProfessionsNeedingRecipes = function() return { "tailoring" } end,
        MarkRecipesRequested = function() end,
        GetCharacter = function() return nil end,
      }
      Comm._TestHookSend = function(msgType, payload, distribution, target)
        sent[#sent + 1] = { msgType = msgType, payload = payload, target = target }
      end
    end)

    after_each(function()
      Comm._TestHookSend = nil
      Comm.IsGuildMemberOnline = realOnline
    end)

    it("asks an online sender again for a card still missing, naming the character's realm", function()
      entries = { { realm = "R", entry = { name = "Kairu", guid = "Player-6929-K", source = "Kairu",
        charRealm = "R3", needsProfessionCard = true } } }
      assert.are.equal(1, Comm.SweepPending())
      assert.are.equal("CQ", sent[1].msgType)
      assert.are.equal("R3", sent[1].payload.realm)
      assert.are.equal("Kairu", sent[1].target)
    end)

    it("waits out the back-off unless forced, and skips senders offline", function()
      due = false
      entries = { { realm = "R", entry = { name = "Kairu", source = "Kairu", needsProfessionCard = true } },
        { realm = "R", entry = { name = "Alt", source = "Gone", needsProfessionCard = true } } }
      assert.are.equal(0, Comm.SweepPending())
      assert.are.equal(1, Comm.SweepPending("Kairu", true))
      assert.are.equal(0, Comm.SweepPending("Gone", true))
    end)

    it("asks for recipe lists once the card is in", function()
      entries = { { realm = "R", entry = { name = "Kairu", source = "Kairu", needsProfessionCard = false } } }
      assert.are.equal(1, Comm.SweepPending())
      assert.are.equal("RQ", sent[1].msgType)
    end)

    it("sends at most SWEEP_MAX_REQUESTS", function()
      for i = 1, 20 do
        entries[i] = { realm = "R", entry = { name = "C" .. i, source = "S" .. i, needsProfessionCard = true } }
      end
      assert.are.equal(Comm.SWEEP_MAX_REQUESTS, Comm.SweepPending())
    end)
  end)

  describe("numbered parts capability", function()
    it("remembers which peers read numbered parts, from their last message", function()
      Comm._NotePeerCapabilities({ mp = 1 }, "Kairu Stormhoof-CAMWOWUS2Realm3PvE")
      assert.is_true(Comm._PeerReadsNumbered("Kairu Stormhoof"))
      Comm._NotePeerCapabilities({}, "Kairu Stormhoof")
      assert.is_false(Comm._PeerReadsNumbered("Kairu Stormhoof"))
      assert.is_false(Comm._PeerReadsNumbered("Nobody"))
    end)

    it("stamps every outgoing message with the capability", function()
      local got
      Comm._TestHookSend = function(_, payload) got = payload end
      _G.UnitGUID = function() return "Player-1-B" end
      local realOnline = Comm.IsGuildMemberOnline
      Comm.IsGuildMemberOnline = function() return true end
      AltArmy.GuildShareProtocol = { BuildCharCardRequest = function() return { v = 2 } end }
      AltArmy.GuildShareData = {}
      Comm.RequestCharCard("X", "R", "Kairu", "Player-9-X")
      Comm.IsGuildMemberOnline = realOnline
      Comm._TestHookSend = nil
      _G.UnitGUID = nil
      assert.are.equal(Comm.MULTIPART_VERSION, got.mp)
    end)

    it("makes distinct two-character message ids", function()
      local a, b = Comm._NewMessageId(), Comm._NewMessageId()
      assert.are.equal(2, #a)
      assert.are_not.equal(a, b)
    end)
  end)
end)
