--[[
  Unit tests for DataStoreMail.lua (GetNumMails, GetMailItemCount, GetMailInfo, GetMailboxLastVisit).
  Run from project root: npm test
]]

describe("DataStoreMail", function()
  local DS

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.AltArmyTBC_Data = _G.AltArmyTBC_Data or { Characters = {} }
    _G.CreateFrame = _G.CreateFrame or function()
      return { SetScript = function() end, RegisterEvent = function() end }
    end
    _G.UIParent = _G.UIParent or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("DataStore")
    require("DataStoreMail")
    DS = AltArmy.DataStore
  end)

  describe("GetNumMails", function()
    it("returns 0 when char is nil", function()
      assert.are.equal(DS:GetNumMails(nil), 0)
    end)
    it("returns 0 when Mails nil", function()
      assert.are.equal(DS:GetNumMails({}), 0)
    end)
    it("returns length of Mails", function()
      local char = { Mails = { {}, {}, {} } }
      assert.are.equal(3, DS:GetNumMails(char))
    end)
    it("counts Mails + MailCache when both exist", function()
      local char = { Mails = { {}, {} }, MailCache = { {}, {}, {} } }
      assert.are.equal(5, DS:GetNumMails(char))
    end)
  end)

  describe("GetMailItemCount", function()
    it("returns 0 when char or itemID nil", function()
      assert.are.equal(0, DS:GetMailItemCount(nil, 100))
      assert.are.equal(0, DS:GetMailItemCount({ Mails = {} }, nil))
    end)
    it("sums count for matching itemID", function()
      local char = {
        Mails = {
          { itemID = 100, count = 2 },
          { itemID = 200, count = 1 },
          { itemID = 100, count = 3 },
        },
      }
      assert.are.equal(5, DS:GetMailItemCount(char, 100))
      assert.are.equal(1, DS:GetMailItemCount(char, 200))
      assert.are.equal(0, DS:GetMailItemCount(char, 999))
    end)
    it("treats missing count as 1", function()
      local char = { Mails = { { itemID = 100 } } }
      assert.are.equal(1, DS:GetMailItemCount(char, 100))
    end)
    it("includes MailCache entries in counts", function()
      local char = {
        Mails = { { itemID = 100, count = 2 } },
        MailCache = { { itemID = 100, count = 3 }, { itemID = 200, count = 9 } },
      }
      assert.are.equal(5, DS:GetMailItemCount(char, 100))
      assert.are.equal(9, DS:GetMailItemCount(char, 200))
    end)
  end)

  describe("GetMailInfo", function()
    it("returns nil,... when index out of range", function()
      local char = { Mails = {} }
      local icon = DS:GetMailInfo(char, 1)
      assert.is_nil(icon)
    end)
    it("returns icon, count, link, money, subject, sender, daysLeft, returned", function()
      local char = {
        Mails = {
          {
            icon = "x", count = 5, link = "l", money = 100, subject = "s", sender = "S",
            daysLeft = 30, lastCheck = 0, returned = false,
          },
        },
      }
      local old = _G.time
      _G.time = function() return 86400 end
      local icon, count, link, money, subject, sender, _, returned = DS:GetMailInfo(char, 1)
      _G.time = old
      assert.are.equal("x", icon)
      assert.are.equal(5, count)
      assert.are.equal("l", link)
      assert.are.equal(100, money)
      assert.are.equal("s", subject)
      assert.are.equal("S", sender)
      assert.are.equal(false, returned)
    end)
    it("can read info from MailCache after Mails entries", function()
      local char = {
        Mails = { { icon = "m1", itemID = 1, count = 1, lastCheck = 0, daysLeft = 30 } },
        MailCache = { { icon = "c1", itemID = 2, count = 5, link = "lk", money = 0, subject = "sub", sender = "Me", lastCheck = 0, daysLeft = 30, returned = true } },
      }
      local old = _G.time
      _G.time = function() return 0 end
      local icon, count, link, money, subject, sender, daysLeft, returned = DS:GetMailInfo(char, 2)
      _G.time = old
      assert.are.equal("c1", icon)
      assert.are.equal(5, count)
      assert.are.equal("lk", link)
      assert.are.equal(0, money)
      assert.are.equal("sub", subject)
      assert.are.equal("Me", sender)
      assert.are.equal(30, daysLeft)
      assert.are.equal(true, returned)
    end)
  end)

  describe("GetMailboxLastVisit", function()
    it("returns 0 when char nil", function()
      assert.are.equal(0, DS:GetMailboxLastVisit(nil))
    end)
    it("returns lastMailCheck or 0", function()
      assert.are.equal(12345, DS:GetMailboxLastVisit({ lastMailCheck = 12345 }))
      assert.are.equal(0, DS:GetMailboxLastVisit({}))
    end)
  end)

  describe("finding the alt a mail is for", function()
    it("matches the stored name of a GUID-keyed character, ignoring case", function()
      local blast = { name = "Frell Blast", guid = "Player-1-B" }
      _G.AltArmyTBC_Data = { Characters = { R = {
        ["Player-1-A"] = { name = "Frell Ofelements", guid = "Player-1-A" },
        ["Player-1-B"] = blast,
      } } }
      assert.are.equal(blast, DS._FindCharacterByName("R", "frell blast"))
      assert.is_nil(DS._FindCharacterByName("R", "Frell"))
      assert.is_nil(DS._FindCharacterByName("R", "Player-1-B"))
    end)

    it("finds an alt on a coalesced realm (Forever's US1 and US2 play together)", function()
      local bank = { name = "Bank Frell", guid = "Player-1-C" }
      _G.AltArmyTBC_Data = { Characters = {
        ["CAMWOW US2 Realm 5 PvE"] = { ["Player-1-B"] = { name = "Frell Blast", guid = "Player-1-B" } },
        ["CAMWOW US1 Realm 5 PvE"] = { ["Player-1-C"] = bank },
        ["CAMWOW US1 Realm 5 PvP"] = { ["Player-1-D"] = { name = "Pvp Frell", guid = "Player-1-D" } },
      } }
      local saved = AltArmy.RealmFilter
      AltArmy.RealmFilter = { sameRealm = function(a, b) return a:gsub("US%d", "US") == b:gsub("US%d", "US") end }
      local found = DS._FindCharacterByName("CAMWOW US2 Realm 5 PvE", "bank frell")
      local other = DS._FindCharacterByName("CAMWOW US2 Realm 5 PvE", "Pvp Frell")
      AltArmy.RealmFilter = saved
      assert.are.equal(bank, found)
      assert.is_nil(other)
    end)
  end)

  describe("Cache + scan interactions", function()
    it("SaveMailAttachmentToCache appends an entry with expiry metadata", function()
      local char = { Mails = {}, MailCache = {} }
      local old = _G.time
      _G.time = function() return 123 end
      DS:SaveMailAttachmentToCache(char, "ic", 100, "link", 2, "Sender", "Subj", false)
      _G.time = old
      assert.are.equal(1, #char.MailCache)
      assert.are.equal(100, char.MailCache[1].itemID)
      assert.are.equal(2, char.MailCache[1].count)
      assert.are.equal("Sender", char.MailCache[1].sender)
      assert.are.equal("Subj", char.MailCache[1].subject)
      assert.are.equal(30, char.MailCache[1].daysLeft)
      assert.are.equal(123, char.MailCache[1].lastCheck)
      assert.are.equal(false, char.MailCache[1].returned)
    end)

    it("SaveMailToCache appends a money/body entry", function()
      local char = { Mails = {}, MailCache = {} }
      DS:SaveMailToCache(char, 500, "body", "sub", "Sender", false)
      assert.are.equal(1, #char.MailCache)
      assert.are.equal(500, char.MailCache[1].money)
      assert.are.equal("body", char.MailCache[1].text)
      assert.are.equal("sub", char.MailCache[1].subject)
      assert.are.equal("Sender", char.MailCache[1].sender)
    end)

    it("ScanMailbox clears MailCache once a real scan occurs", function()
      local char = { Mails = {}, MailCache = { { itemID = 100, count = 1 } } }
      -- Force current character table to this instance.
      DS._GetCurrentCharTable = function() return char end
      _G.GetInboxNumItems = function() return 0 end
      _G.CheckInbox = function() end
      local old = _G.time
      _G.time = function() return 999 end
      DS:ScanMailbox()
      _G.time = old
      assert.are.equal(0, #char.MailCache)
      assert.are.equal(999, char.lastMailCheck)
    end)

    it("ScanMailbox keeps a predicted row still on its way from another account", function()
      local char = { Mails = {}, MailCache = {
        { itemID = 100, count = 1, arrivesAt = 2000, lm = "x" },
        { itemID = 200, count = 1, arrivesAt = 900 },
        { itemID = 300, count = 1 },
      } }
      DS._GetCurrentCharTable = function() return char end
      _G.GetInboxNumItems = function() return 0 end
      _G.CheckInbox = function() end
      local old = _G.time
      _G.time = function() return 1000 end
      DS:ScanMailbox()
      _G.time = old
      assert.are.equal(1, #char.MailCache)
      assert.are.equal(100, char.MailCache[1].itemID)
    end)

    it("hands a send to a linked account's character to the link", function()
      local got
      AltArmy.LinkTransport = { MailSent = function(...) got = { ... } end }
      local saved = { DS.GetCurrentPlayerIdentity, _G.GetSendMailItem, _G.GetSendMailItemLink,
        _G.GetSendMailMoney }
      DS.GetCurrentPlayerIdentity = function() return "Me", "R" end
      _G.GetSendMailItem = function(i)
        if i == 1 then return "Linen Cloth", 2589, 132889, 20 end
      end
      _G.GetSendMailItemLink = function(i)
        if i == 1 then return "|Hitem:2589|h[Linen Cloth]|h" end
      end
      _G.GetSendMailMoney = function() return 5000 end
      DS._CacheSentMailToAlt("Linked-Realm", "Subject", "body")
      DS.GetCurrentPlayerIdentity, _G.GetSendMailItem, _G.GetSendMailItemLink, _G.GetSendMailMoney =
        saved[1], saved[2], saved[3], saved[4]
      AltArmy.LinkTransport = nil
      assert.are.equal("R", got[1])
      assert.are.equal("Linked", got[2])
      assert.are.same({
        { itemID = 2589, count = 20, link = "|Hitem:2589|h[Linen Cloth]|h", icon = 132889 },
        { money = 5000, icon = "Interface\\Icons\\INV_Misc_Coin_01" },
      }, got[3])
      assert.are.equal("Me", got[4])
      assert.is_false(got[5])
    end)

    it("ScanMailbox does not call GetInboxText (avoids marking mail as read)", function()
      local char = { Mails = {}, MailCache = {} }
      DS._GetCurrentCharTable = function() return char end
      local inboxTextCalls = 0
      _G.GetInboxNumItems = function() return 1 end
      _G.CheckInbox = function() end
      _G.GetInboxHeaderInfo = function()
        return nil, "icon", "Sender", "Subject", 0, 0, 30, 1, nil, false
      end
      _G.GetInboxItem = function(_mailIndex, attachIndex)
        if attachIndex ~= 1 then return nil end
        return "Item", 100, "itemIcon", 2
      end
      _G.GetInboxItemLink = function(_mailIndex, attachIndex)
        if attachIndex ~= 1 then return nil end
        return "|Hitem:100|h[Item]|h"
      end
      _G.GetInboxText = function()
        inboxTextCalls = inboxTextCalls + 1
        return "body"
      end
      local old = _G.time
      _G.time = function() return 1000 end
      DS:ScanMailbox()
      _G.time = old
      assert.are.equal(0, inboxTextCalls)
      assert.are.equal(1, #char.Mails)
      assert.are.equal(100, char.Mails[1].itemID)
      assert.are.equal(2, char.Mails[1].count)
    end)

    it("ScanMailbox still records money without reading body text", function()
      local char = { Mails = {}, MailCache = {} }
      DS._GetCurrentCharTable = function() return char end
      _G.GetInboxNumItems = function() return 1 end
      _G.CheckInbox = function() end
      _G.GetInboxHeaderInfo = function()
        return nil, "coinIcon", "Sender", "COD", 2500, 0, 20, nil, nil, false
      end
      _G.GetInboxItem = function() return nil end
      _G.GetInboxItemLink = function() return nil end
      _G.GetInboxText = function()
        error("GetInboxText should not be called")
      end
      local old = _G.time
      _G.time = function() return 1000 end
      DS:ScanMailbox()
      _G.time = old
      assert.are.equal(1, #char.Mails)
      assert.are.equal(2500, char.Mails[1].money)
      assert.is_nil(char.Mails[1].text)
    end)
  end)

  describe("MailRowDaysLeft", function()
    it("subtracts the time since the scan, nil without an expiry", function()
      assert.are.equal(8, DS.MailRowDaysLeft({ daysLeft = 10, lastCheck = 1000 }, 1000 + 2 * 86400))
      assert.are.equal(10, DS.MailRowDaysLeft({ daysLeft = 10 }, 0))
      assert.is_nil(DS.MailRowDaysLeft({ itemID = 1 }, 0))
      assert.is_nil(DS.MailRowDaysLeft(nil, 0))
    end)
  end)

  describe("message index (mail v2)", function()
    it("ScanMailbox stamps every row of a message with its inbox position", function()
      local char = { Mails = {}, MailCache = {} }
      DS._GetCurrentCharTable = function() return char end
      _G.GetInboxNumItems = function() return 2 end
      _G.CheckInbox = function() end
      _G.GetInboxHeaderInfo = function(i)
        if i == 1 then return nil, "icon", "Alice", "Mats", 1500, 0, 30, 2, nil, false end
        return nil, "icon", "Bob", "Gold", 2500, 0, 20, nil, nil, false
      end
      _G.GetInboxItem = function(mailIndex, attachIndex)
        if mailIndex == 1 and attachIndex <= 2 then return "Item", 100 + attachIndex, "ic", 1 end
        return nil
      end
      _G.GetInboxItemLink = function() return nil end
      _G.GetInboxText = function() error("GetInboxText should not be called") end
      local old = _G.time
      _G.time = function() return 1000 end
      DS:ScanMailbox()
      _G.time = old
      assert.are.equal(4, #char.Mails)
      assert.are.same({ 1, 1, 1, 2 }, {
        char.Mails[1].mailIndex, char.Mails[2].mailIndex, char.Mails[3].mailIndex, char.Mails[4].mailIndex,
      })
      assert.are.equal(1500, char.Mails[3].money)
      assert.are.equal(2, char.dataVersions.mail)
    end)

    it("NextMailCacheIndex counts down from -1 below the lowest cached index", function()
      local char = { MailCache = {} }
      assert.are.equal(-1, DS:NextMailCacheIndex(char))
      DS:SaveMailAttachmentToCache(char, "ic", 100, "link", 1, "Me", "Subj", false, -1)
      DS:SaveMailToCache(char, 500, "", "Subj", "Me", false, -1)
      assert.are.equal(-1, char.MailCache[1].mailIndex)
      assert.are.equal(-1, char.MailCache[2].mailIndex)
      assert.are.equal(-2, DS:NextMailCacheIndex(char))
      char.MailCache[3] = { itemID = 1, count = 1 } -- a v1 row without an index
      assert.are.equal(-2, DS:NextMailCacheIndex(char))
      assert.are.equal(-1, DS:NextMailCacheIndex(nil))
    end)
  end)
end)
