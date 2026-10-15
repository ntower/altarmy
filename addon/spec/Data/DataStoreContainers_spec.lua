--[[
  Unit tests for DataStoreContainers.lua (GetContainerItemCount, IterateContainerSlots).
  Run from project root: npm test
]]

describe("DataStoreContainers", function()
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
    require("DataStoreContainers")
    require("DataStoreMail")
    DS = AltArmy.DataStore
  end)

  describe("GetContainerItemCount", function()
    it("returns 0 when char is nil", function()
      assert.are.equal(0, DS:GetContainerItemCount(nil, 100))
    end)
    it("returns 0 when itemID is nil", function()
      assert.are.equal(0, DS:GetContainerItemCount({ Containers = {} }, nil))
    end)
    it("returns 0 when Containers empty", function()
      assert.are.equal(0, DS:GetContainerItemCount({ Containers = {} }, 100))
    end)
    it("sums count across bags for itemID", function()
      local char = {
        Containers = {
          [0] = { items = { [1] = { itemID = 100, count = 5 }, [2] = { itemID = 200, count = 1 } } },
          [1] = { items = { [1] = { itemID = 100, count = 3 } } },
        },
      }
      assert.are.equal(8, DS:GetContainerItemCount(char, 100))
      assert.are.equal(1, DS:GetContainerItemCount(char, 200))
      assert.are.equal(0, DS:GetContainerItemCount(char, 999))
    end)
    it("treats missing count as 1", function()
      local char = {
        Containers = {
          [0] = { items = { [1] = { itemID = 100 } } },
        },
      }
      assert.are.equal(1, DS:GetContainerItemCount(char, 100))
    end)
  end)

  describe("GetTotalItemCount", function()
    it("sums containers + mail", function()
      local char = {
        Containers = {
          [0] = { items = { [1] = { itemID = 100, count = 2 } } },
        },
        Mails = {
          { itemID = 100, count = 3 },
          { itemID = 200, count = 9 },
        },
      }
      assert.are.equal(5, DS:GetTotalItemCount(char, 100))
      assert.are.equal(9, DS:GetTotalItemCount(char, 200))
    end)

    it("treats missing mail module as 0 (still counts containers)", function()
      local old = DS.GetMailItemCount
      DS.GetMailItemCount = nil
      local char = { Containers = { [0] = { items = { [1] = { itemID = 100, count = 2 } } } } }
      assert.are.equal(2, DS:GetTotalItemCount(char, 100))
      DS.GetMailItemCount = old
    end)
  end)

  describe("GetBagItemCount", function()
    it("returns 0 when char is nil", function()
      assert.are.equal(0, DS:GetBagItemCount(nil, 100))
    end)
    it("returns 0 when itemID is nil", function()
      assert.are.equal(0, DS:GetBagItemCount({ Containers = {} }, nil))
    end)
    it("sums across bags but excludes bank containers", function()
      local char = {
        Containers = {
          [0] = { items = { [1] = { itemID = 100, count = 2 } } },
          [1] = { items = { [1] = { itemID = 100, count = 3 } } },
          [-1] = { items = { [1] = { itemID = 100, count = 5 } } }, -- bank container
          [5] = { items = { [1] = { itemID = 100, count = 7 } } }, -- bank bag range
        },
      }
      assert.are.equal(5, DS:GetBagItemCount(char, 100))
    end)
    it("includes keyring container", function()
      local char = {
        Containers = {
          [0] = { items = { [1] = { itemID = 100, count = 1 } } },
          [-2] = { items = { [1] = { itemID = 100, count = 4 } } },
        },
      }
      assert.are.equal(5, DS:GetBagItemCount(char, 100))
    end)
  end)

  describe("IterateContainerSlots", function()
    it("does nothing when char is nil", function()
      local n = 0
      DS:IterateContainerSlots(nil, function() n = n + 1 end)
      assert.are.equal(0, n)
    end)
    it("does nothing when callback is nil", function()
      local char = { Containers = { [0] = { items = { [1] = { itemID = 1 } } } } }
      DS:IterateContainerSlots(char, nil)
    end)
    it("invokes callback for each slot with item", function()
      local char = {
        Containers = {
          [0] = { items = { [1] = { itemID = 100, count = 2 } }, links = { [1] = "link1" } },
          [1] = { items = { [1] = { itemID = 200, count = 1 } }, links = {} },
        },
      }
      local calls = {}
      DS:IterateContainerSlots(char, function(bagID, slot, itemID, count, link)
        table.insert(calls, { bagID = bagID, slot = slot, itemID = itemID, count = count, link = link })
        return false
      end)
      assert.are.equal(2, #calls)
      assert.are.equal(0, calls[1].bagID)
      assert.are.equal(1, calls[1].slot)
      assert.are.equal(100, calls[1].itemID)
      assert.are.equal(2, calls[1].count)
      assert.are.equal("link1", calls[1].link)
      assert.are.equal(200, calls[2].itemID)
    end)
    it("stops when callback returns true", function()
      local char = {
        Containers = {
          [0] = { items = { [1] = { itemID = 100 }, [2] = { itemID = 200 } }, links = {} },
        },
      }
      local n = 0
      DS:IterateContainerSlots(char, function()
        n = n + 1
        return true
      end)
      assert.are.equal(1, n)
    end)
  end)

  describe("IterateBagSlots", function()
    it("invokes callback only for bag containers", function()
      local char = {
        Containers = {
          [0] = { items = { [1] = { itemID = 100, count = 2 } }, links = { [1] = "link1" } },
          [-1] = { items = { [1] = { itemID = 200, count = 1 } }, links = { [1] = "bank" } },
          [-2] = { items = { [1] = { itemID = 300, count = 1 } }, links = { [1] = "key" } },
        },
      }
      local calls = {}
      DS:IterateBagSlots(char, function(bagID, slot, itemID, count, link)
        table.insert(calls, { bagID = bagID, slot = slot, itemID = itemID, count = count, link = link })
        return false
      end)
      assert.are.equal(2, #calls)
      assert.are.equal(0, calls[1].bagID)
      assert.are.equal(100, calls[1].itemID)
      assert.are.equal("link1", calls[1].link)
      assert.are.equal(-2, calls[2].bagID)
      assert.are.equal(300, calls[2].itemID)
    end)
  end)

  describe("IterateBankSlots", function()
    it("invokes callback only for bank containers", function()
      local char = {
        Containers = {
          [0] = { items = { [1] = { itemID = 100, count = 2 } }, links = { [1] = "bag" } },
          [-1] = { items = { [1] = { itemID = 200, count = 1 } }, links = { [1] = "bank" } },
          ["5"] = { items = { [1] = { itemID = 300, count = 1 } }, links = { [1] = "bank5" } },
        },
      }
      local calls = {}
      DS:IterateBankSlots(char, function(bagID, slot, itemID, count, link)
        table.insert(calls, { bagID = bagID, slot = slot, itemID = itemID, count = count, link = link })
        return false
      end)
      assert.are.equal(2, #calls)
      assert.are.equal(-1, calls[1].bagID)
      assert.are.equal(200, calls[1].itemID)
      assert.are.equal("bank", calls[1].link)
      assert.are.equal(5, calls[2].bagID)
      assert.are.equal(300, calls[2].itemID)
    end)
  end)

  describe("ScanBags keyring", function()
    it("records keyring slots in char.Containers", function()
      _G.UnitName = function() return "KeyringTest" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.GetContainerNumSlots = function(bagID)
        if bagID == 0 then return 16 end
        if bagID == -2 then return 32 end
        return 0
      end
      _G.GetContainerItemLink = function(bagID, slot)
        if bagID == -2 and slot == 1 then return "|Hitem:12345:0|h[Test Key]|h" end
        return nil
      end
      _G.GetContainerItemInfo = function(bagID, slot)
        if bagID == -2 and slot == 1 then return "Test Key", 1 end
        return nil
      end
      _G.time = function() return 12345 end

      local char = DS:GetCurrentCharacter()
      char.Containers = {}
      DS:ScanBags()

      assert.truthy(char.Containers[-2])
      assert.are.equal(12345, char.Containers[-2].items[1].itemID)
      assert.are.equal("|Hitem:12345:0|h[Test Key]|h", char.Containers[-2].links[1])
    end)
  end)

  describe("ScanBank", function()
    it("preserves saved bank slots when the bank is closed", function()
      _G.UnitName = function() return "Banker" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.GetContainerNumSlots = function(bagID)
        if bagID == -1 then return 28 end
        return 0
      end
      _G.GetContainerItemLink = function() return nil end
      DS.IsBankOpen = function() return false end
      local char = DS:GetCurrentCharacter()
      char.Containers = {
        [-1] = {
          items = { [1] = { itemID = 100, count = 1 } },
          links = { [1] = "|Hitem:100:0|h[Bank Item]|h" },
        },
      }
      DS:ScanBank()
      assert.are.equal(100, char.Containers[-1].items[1].itemID)
      assert.are.equal("|Hitem:100:0|h[Bank Item]|h", char.Containers[-1].links[1])
    end)

    it("stores bank bag identity when bank is open", function()
      _G.UnitName = function() return "Banker" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.ContainerIDToInventoryID = function(bagID)
        if bagID == 5 then return 67 end
        return nil
      end
      _G.GetInventoryItemLink = function(_, invSlot)
        if invSlot == 67 then return "|Hitem:21841:0|h[Netherweave Bag]|h" end
        return nil
      end
      _G.GetContainerNumSlots = function(bagID)
        if bagID == -1 then return 28 end
        if bagID == 5 then return 16 end
        return 0
      end
      _G.GetContainerItemLink = function() return nil end
      _G.GetContainerItemInfo = function() return nil end
      _G.GetContainerNumFreeSlots = function() return 0 end
      DS.IsBankOpen = function() return true end
      local char = DS:GetCurrentCharacter()
      char.Containers = {}
      DS:ScanBank()
      assert.are.equal(21841, char.Containers[5].bagItemID)
      assert.are.equal("|Hitem:21841:0|h[Netherweave Bag]|h", char.Containers[5].bagLink)
    end)

    it("does not clear bank bag identity when bank is closed", function()
      _G.UnitName = function() return "Banker" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.GetContainerNumSlots = function() return 0 end
      DS.IsBankOpen = function() return false end
      local char = DS:GetCurrentCharacter()
      char.Containers = {
        [5] = {
          bagItemID = 21841,
          bagLink = "|Hitem:21841:0|h[Netherweave Bag]|h",
          items = { [1] = { itemID = 100, count = 1 } },
          links = { [1] = "|Hitem:100:0|h[Bank Item]|h" },
        },
      }
      DS:ScanBank()
      assert.are.equal(21841, char.Containers[5].bagItemID)
      assert.are.equal(100, char.Containers[5].items[1].itemID)
    end)
  end)

  describe("equipped bag identity", function()
    it("ScanBags stores bagLink/bagItemID for bags 1-4", function()
      _G.UnitName = function() return "BagChar" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.ContainerIDToInventoryID = function(bagID)
        return 19 + bagID -- bag 1 -> 20, etc.
      end
      _G.GetInventoryItemLink = function(_, invSlot)
        if invSlot == 20 then return "|Hitem:21841:0|h[Netherweave Bag]|h" end
        if invSlot == 21 then return "|Hitem:14156:0|h[Bottomless Bag]|h" end
        return nil
      end
      _G.GetContainerNumSlots = function(bagID)
        if bagID == 0 then return 16 end
        if bagID == 1 then return 16 end
        if bagID == 2 then return 18 end
        return 0
      end
      _G.GetContainerItemLink = function() return nil end
      _G.GetContainerItemInfo = function() return nil end
      _G.GetContainerNumFreeSlots = function() return 0 end
      _G.time = function() return 1 end

      local char = DS:GetCurrentCharacter()
      char.Containers = {}
      DS:ScanBags()

      assert.is_nil(char.Containers[0].bagItemID)
      assert.are.equal(21841, char.Containers[1].bagItemID)
      assert.are.equal("|Hitem:21841:0|h[Netherweave Bag]|h", char.Containers[1].bagLink)
      assert.are.equal(14156, char.Containers[2].bagItemID)
      assert.is_nil(char.Containers[3])
      assert.is_nil(char.Containers[4])
    end)

    it("ScanBags stores identity via GetInventorySlotInfo when ContainerIDToInventoryID is missing", function()
      _G.UnitName = function() return "BagChar" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.ContainerIDToInventoryID = nil
      _G.C_Container = nil
      _G.GetInventorySlotInfo = function(slotName)
        if slotName == "Bag0Slot" then return 20 end
        if slotName == "Bag1Slot" then return 21 end
        return nil
      end
      _G.GetInventoryItemLink = function(_, invSlot)
        if invSlot == 20 then return "|Hitem:21843:0|h[Imbued Netherweave Bag]|h" end
        return nil
      end
      _G.GetContainerNumSlots = function(bagID)
        if bagID == 0 then return 16 end
        if bagID == 1 then return 18 end
        return 0
      end
      _G.GetContainerItemLink = function() return nil end
      _G.GetContainerItemInfo = function() return nil end
      _G.GetContainerNumFreeSlots = function() return 0 end
      _G.time = function() return 1 end

      local char = DS:GetCurrentCharacter()
      char.Containers = {}
      DS:ScanBags()

      assert.are.equal(21843, char.Containers[1].bagItemID)
      assert.are.equal("|Hitem:21843:0|h[Imbued Netherweave Bag]|h", char.Containers[1].bagLink)
    end)

    it("ScanBags stores identity via C_Container.ContainerIDToInventoryID", function()
      _G.UnitName = function() return "BagChar" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.ContainerIDToInventoryID = nil
      _G.GetInventorySlotInfo = nil
      _G.C_Container = {
        ContainerIDToInventoryID = function(bagID) return 19 + bagID end,
        GetContainerNumSlots = function(bagID)
          if bagID == 0 then return 16 end
          if bagID == 1 then return 18 end
          return 0
        end,
        GetContainerItemLink = function() return nil end,
        GetContainerNumFreeSlots = function() return 0 end,
      }
      _G.GetInventoryItemLink = function(_, invSlot)
        if invSlot == 20 then return "|Hitem:21843:0|h[Imbued Netherweave Bag]|h" end
        return nil
      end
      _G.GetContainerNumSlots = nil
      _G.GetContainerItemLink = nil
      _G.GetContainerItemInfo = nil
      _G.GetContainerNumFreeSlots = nil
      _G.time = function() return 1 end

      local char = DS:GetCurrentCharacter()
      char.Containers = {}
      DS:ScanBags()

      assert.are.equal(21843, char.Containers[1].bagItemID)
    end)

    it("ScanBags uses GetInventoryItemID when the item link is not ready", function()
      _G.UnitName = function() return "BagChar" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.C_Container = nil
      _G.ContainerIDToInventoryID = function(bagID) return 19 + bagID end
      _G.GetInventoryItemLink = function() return nil end
      _G.GetInventoryItemID = function(_, invSlot)
        if invSlot == 20 then return 21843 end
        return nil
      end
      _G.GetContainerNumSlots = function(bagID)
        if bagID == 0 then return 16 end
        if bagID == 1 then return 18 end
        return 0
      end
      _G.GetContainerItemLink = function() return nil end
      _G.GetContainerItemInfo = function() return nil end
      _G.GetContainerNumFreeSlots = function() return 0 end
      _G.time = function() return 1 end

      local char = DS:GetCurrentCharacter()
      char.Containers = {}
      DS:ScanBags()

      assert.are.equal(21843, char.Containers[1].bagItemID)
    end)

    it("preserves bag identity when a bag still has slots but inventory APIs return nil", function()
      _G.UnitName = function() return "BagChar" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.C_Container = nil
      _G.ContainerIDToInventoryID = function(bagID) return 19 + bagID end
      _G.GetInventoryItemLink = function() return nil end
      _G.GetInventoryItemID = function() return nil end
      _G.GetContainerNumSlots = function(bagID)
        if bagID == 0 then return 16 end
        if bagID == 1 then return 18 end
        return 0
      end
      _G.GetContainerItemLink = function() return nil end
      _G.GetContainerItemInfo = function() return nil end
      _G.GetContainerNumFreeSlots = function() return 0 end
      _G.time = function() return 1 end

      local char = DS:GetCurrentCharacter()
      char.Containers = {
        [1] = {
          bagItemID = 21843,
          bagLink = "|Hitem:21843:0|h[Imbued Netherweave Bag]|h",
          items = {},
          links = {},
        },
      }
      DS:ScanBags()

      assert.are.equal(21843, char.Containers[1].bagItemID)
      assert.are.equal("|Hitem:21843:0|h[Imbued Netherweave Bag]|h", char.Containers[1].bagLink)
    end)

    it("clears identity and contents when an inventory bag slot is empty", function()
      _G.UnitName = function() return "BagChar" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.ContainerIDToInventoryID = function(bagID) return 19 + bagID end
      _G.GetInventoryItemLink = function() return nil end
      _G.GetContainerNumSlots = function(bagID)
        if bagID == 0 then return 16 end
        return 0
      end
      _G.GetContainerItemLink = function() return nil end
      _G.GetContainerItemInfo = function() return nil end
      _G.GetContainerNumFreeSlots = function() return 0 end
      _G.time = function() return 1 end

      local char = DS:GetCurrentCharacter()
      char.Containers = {
        [1] = {
          bagItemID = 21841,
          bagLink = "|Hitem:21841:0|h[Netherweave Bag]|h",
          items = { [1] = { itemID = 2589, count = 5 } },
          links = { [1] = "|Hitem:2589:0|h[Linen Cloth]|h" },
        },
      }
      DS:ScanBags()

      assert.is_nil(char.Containers[1].bagItemID)
      assert.is_nil(char.Containers[1].bagLink)
      assert.is_nil(char.Containers[1].items[1])
      assert.is_nil(char.Containers[1].links[1])
    end)

    it("IterateEquippedBags yields only slots with a bag item", function()
      local char = {
        Containers = {
          [0] = { items = { [1] = { itemID = 1, count = 1 } }, links = {} },
          [1] = {
            bagItemID = 21841,
            bagLink = "|Hitem:21841:0|h[Netherweave Bag]|h",
            items = { [1] = { itemID = 2589, count = 2 } },
            links = { [1] = "cloth" },
          },
          [5] = {
            bagItemID = 14156,
            bagLink = "|Hitem:14156:0|h[Bottomless Bag]|h",
            items = {},
            links = {},
          },
          [-1] = { items = { [1] = { itemID = 100, count = 1 } }, links = {} },
        },
      }
      local calls = {}
      DS:IterateEquippedBags(char, function(bagID, itemID, link)
        table.insert(calls, { bagID = bagID, itemID = itemID, link = link })
        return false
      end)
      assert.are.equal(2, #calls)
      local byBag = {}
      for _, c in ipairs(calls) do byBag[c.bagID] = c end
      assert.are.equal(21841, byBag[1].itemID)
      assert.are.equal(14156, byBag[5].itemID)
    end)

    it("IterateContainerSlots does not yield equipped bag items", function()
      local char = {
        Containers = {
          [1] = {
            bagItemID = 21841,
            bagLink = "|Hitem:21841:0|h[Netherweave Bag]|h",
            items = { [1] = { itemID = 2589, count = 2 } },
            links = { [1] = "cloth" },
          },
        },
      }
      local itemIDs = {}
      DS:IterateContainerSlots(char, function(_, _, itemID)
        table.insert(itemIDs, itemID)
        return false
      end)
      assert.are.same({ 2589 }, itemIDs)
      assert.are.equal(2, DS:GetContainerItemCount(char, 2589))
      assert.are.equal(0, DS:GetContainerItemCount(char, 21841))
    end)
  end)

  describe("slot counts (containers v3)", function()
    local function stubBags(sizes)
      _G.UnitName = function() return "Slots" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.C_Container = nil
      _G.ContainerIDToInventoryID = nil
      _G.GetInventoryItemLink = function() return nil end
      _G.GetInventoryItemID = function() return nil end
      _G.GetContainerNumSlots = function(bagID) return sizes[bagID] or 0 end
      _G.GetContainerItemLink = function() return nil end
      _G.GetContainerItemInfo = function() return nil end
      _G.GetContainerNumFreeSlots = function(bagID) return sizes[bagID] or 0 end
      _G.time = function() return 1 end
      DS.IsBankOpen = function() return true end
    end

    it("ScanBags records numSlots for the backpack, each bag and the keyring", function()
      stubBags({ [0] = 16, [1] = 18, [-2] = 12 })
      local char = DS:GetCurrentCharacter()
      char.Containers = {}
      DS:ScanBags()
      assert.are.equal(16, char.Containers[0].numSlots)
      assert.are.equal(18, char.Containers[1].numSlots)
      assert.are.equal(12, char.Containers[-2].numSlots)
      assert.are.equal(16, DS:GetContainerNumSlots(char, 0))
      assert.are.equal(4, char.dataVersions.containers)
    end)

    it("records 0 for an equippable bag slot that holds no bag", function()
      stubBags({ [0] = 16 })
      local char = DS:GetCurrentCharacter()
      char.Containers = { [2] = { items = { [1] = { itemID = 5, count = 1 } }, links = {}, numSlots = 8 } }
      DS:ScanBags()
      assert.are.equal(0, char.Containers[2].numSlots)
      assert.are.equal(0, DS:GetContainerNumSlots(char, 2))
    end)

    it("ScanBank records the main bank and bank bag sizes", function()
      stubBags({ [-1] = 24, [5] = 16 })
      local char = DS:GetCurrentCharacter()
      char.Containers = {}
      DS:ScanBank()
      assert.are.equal(24, char.Containers[-1].numSlots)
      assert.are.equal(16, char.Containers[5].numSlots)
    end)

    it("GetContainerNumSlots is nil for v2 data and unknown bags", function()
      local char = { Containers = { [0] = { items = {}, links = {} } } }
      assert.is_nil(DS:GetContainerNumSlots(char, 0))
      assert.is_nil(DS:GetContainerNumSlots(char, 3))
      assert.is_nil(DS:GetContainerNumSlots(nil, 0))
    end)
  end)

  describe("OnContainerDataChanged", function()
    it("runs listeners after a bag scan", function()
      _G.UnitName = function() return "Listener" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.C_Container = nil
      _G.GetContainerNumSlots = function(bagID) return bagID == 0 and 16 or 0 end
      _G.GetContainerItemLink = function() return nil end
      _G.GetContainerItemInfo = function() return nil end
      _G.GetInventoryItemLink = function() return nil end
      _G.GetInventoryItemID = function() return nil end
      local fired = 0
      DS:OnContainerDataChanged(function() fired = fired + 1 end)
      DS:OnContainerDataChanged("not a function")
      DS:GetCurrentCharacter().Containers = {}
      DS:ScanBags()
      assert.are.equal(1, fired)
    end)

    it("keeps running the other listeners when one errors", function()
      local fired = false
      DS:OnContainerDataChanged(function() error("boom") end)
      DS:OnContainerDataChanged(function() fired = true end)
      DS:FireContainerDataChanged()
      assert.is_true(fired)
    end)
  end)

  describe("bag roles", function()
    it("uses the Classic ids on a client without retail-style BagIndex", function()
      local r = DS._BuildBagRoles(nil)
      assert.is_false(r.retail)
      assert.are.same({ 1, 2, 3, 4 }, r.bags)
      assert.are.same({ -2, -1 }, { r.keyring, r.bank })
      assert.are.same({ 5, 6, 7, 8, 9, 10, 11 }, r.bankBags)
      assert.are.equal("Bank Bag %d", r.bankBagName)
      assert.is_nil(r.reagentBag)
      -- TBC Anniversary's enum still names a Bank container: Classic ids.
      assert.is_false(DS._BuildBagRoles({ Bank = -1, Keyring = -2, Backpack = 0, BankBag_1 = 6 }).retail)
    end)

    it("follows WoW Forever's BagIndex: keyring -1, reagent bag carried, bank tabs 6-14, no bank container", function()
      local r = DS._BuildBagRoles({
        Keyring = -1, Characterbanktab = -2, Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4,
        ReagentBag = 5, CharacterBankTab_1 = 6, CharacterBankTab_2 = 7, CharacterBankTab_3 = 8,
        CharacterBankTab_4 = 9, CharacterBankTab_5 = 10, CharacterBankTab_6 = 11, CharacterBankTab_7 = 12,
        CharacterBankTab_8 = 13, CharacterBankTab_9 = 14,
      })
      assert.is_true(r.retail)
      assert.are.same({ 1, 2, 3, 4, 5 }, r.bags)
      assert.are.equal(5, r.reagentBag)
      assert.are.equal(-1, r.keyring)
      assert.is_nil(r.bank)
      assert.are.same({ 6, 7, 8, 9, 10, 11, 12, 13, 14 }, r.bankBags)
      assert.are.equal("Bank Tab %d", r.bankBagName)
      assert.are.equal("Bank Bag", r.firstBankBagName)
      assert.is_true(r.bagSet[5])
      assert.is_true(r.bankBagSet[14])
    end)

    it("GetBagRole names each id on this (Classic) client", function()
      assert.are.equal("backpack", DS:GetBagRole(0))
      assert.are.equal("bag", DS:GetBagRole(3))
      assert.are.equal("keyring", DS:GetBagRole(-2))
      assert.are.equal("bank", DS:GetBagRole(-1))
      assert.are.equal("bankbag", DS:GetBagRole(11))
      assert.is_nil(DS:GetBagRole(12))
      assert.is_nil(DS:GetBagRole("x"))
      assert.are.same({ 4, -1, -2, 5, 11 },
        { DS.NUM_BAG_SLOTS, DS.BANK_CONTAINER, DS.KEYRING_CONTAINER, DS.MIN_BANK_BAG_ID, DS.MAX_BANK_BAG_ID })
    end)
  end)

  describe("scans under WoW Forever's roles", function()
    local FOREVER = {
      Keyring = -1, Characterbanktab = -2, Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4,
      ReagentBag = 5, CharacterBankTab_1 = 6, CharacterBankTab_2 = 7, CharacterBankTab_3 = 8,
    }
    local sizes

    before_each(function()
      DS.RebuildBagRoles(FOREVER)
      _G.UnitName = function() return "Forever" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.C_Container = nil
      _G.ContainerIDToInventoryID = function(bagID) return 60 + bagID end
      _G.GetInventoryItemLink = function(_, invSlot)
        if invSlot == 66 then return "|Hitem:242709:0|h[Character Bank Tab Bag (DNT)]|h" end
        if invSlot == 67 then return "|Hitem:5571:0|h[Small Black Pouch]|h" end
        if invSlot == 65 then return "|Hitem:277114:0|h[Reagent Pouch]|h" end
        return nil
      end
      _G.GetInventoryItemID = function() return nil end
      _G.GetContainerNumSlots = function(bagID) return sizes[bagID] or 0 end
      _G.GetContainerItemLink = function() return nil end
      _G.GetContainerItemInfo = function() return nil end
      _G.GetContainerNumFreeSlots = function(bagID) return sizes[bagID] or 0 end
      _G.time = function() return 1 end
      DS.IsBankOpen = function() return true end
    end)

    after_each(function()
      DS.RebuildBagRoles(nil)
    end)

    it("exports the roles and the Classic names from them", function()
      assert.are.same({ 5, nil, -1, 6, 8 },
        { DS.NUM_BAG_SLOTS, DS.BANK_CONTAINER, DS.KEYRING_CONTAINER, DS.MIN_BANK_BAG_ID, DS.MAX_BANK_BAG_ID })
      assert.are.equal("keyring", DS:GetBagRole(-1))
      assert.are.equal("reagentbag", DS:GetBagRole(5))
      assert.are.equal("bankbag", DS:GetBagRole(6))
      assert.is_nil(DS:GetBagRole(-2))
      assert.is_true(DS._IsPlayerCarriedBagID(5))
      assert.is_true(DS._IsPlayerCarriedBagID(-1))
    end)

    it("ScanBags scans the backpack, bags 1-5 (reagent bag with its identity) and the keyring at -1", function()
      sizes = { [0] = 20, [1] = 6, [5] = 1, [-1] = 12 }
      local char = DS:GetCurrentCharacter()
      char.Containers = {}
      DS:ScanBags()
      assert.are.equal(20, char.Containers[0].numSlots)
      assert.are.equal(6, char.Containers[1].numSlots)
      assert.are.equal(1, char.Containers[5].numSlots)
      assert.are.equal(277114, char.Containers[5].bagItemID)
      assert.are.equal(12, char.Containers[-1].numSlots)
      assert.is_nil(char.Containers[-2])
      assert.are.equal(27, char.bagInfo.totalSlots)
    end)

    it("ScanBank scans the tabs, never records the built-in first tab's placeholder item, and skips -1", function()
      sizes = { [-1] = 12, [6] = 48, [7] = 6 }
      local char = DS:GetCurrentCharacter()
      char.Containers = { [6] = { items = {}, links = {}, bagItemID = 242709, bagLink = "old" } }
      DS:ScanBank()
      assert.are.equal(48, char.Containers[6].numSlots)
      assert.is_nil(char.Containers[6].bagItemID)
      assert.is_nil(char.Containers[6].bagLink)
      assert.are.equal(5571, char.Containers[7].bagItemID)
      assert.is_nil(char.Containers[-1]) -- the keyring belongs to ScanBags
      assert.are.equal(54, char.bankInfo.totalSlots)
    end)

    it("IterateEquippedBags skips a placeholder an older addon recorded in the built-in bank tab", function()
      local char = { Containers = {
        [6] = { items = {}, links = {}, bagItemID = 242709, bagLink = "|Hitem:242709:0|h[Character Bank Tab Bag (DNT)]|h" },
        [7] = { items = {}, links = {}, bagItemID = 5571, bagLink = "|Hitem:5571:0|h[Small Black Pouch]|h" },
      } }
      local seen = {}
      DS:IterateEquippedBags(char, function(bagID) seen[#seen + 1] = bagID end)
      assert.are.same({ 7 }, seen)
    end)
  end)

  -- spec/fixtures/holdings_v1.lua is the golden character these scans save. The site's tests
  -- (site/tests/test_altarmy.py) read that same file, so its reader must read back any change here.
  describe("holdings", function()
    it("writes the golden holdings: bags and bank, soulbound copies marked", function()
      local slots = {
        [0] = {
          [1] = { "|Hitem:2589::::::::30:::::|h[Linen Cloth]|h", 20, false },
          [2] = { "|Hitem:2140::::::::30:::::|h[Carving Knife]|h", 1, true },
          [4] = { "|Hitem:2589::::::::30:::::|h[Linen Cloth]|h", 5, false },
        },
        [-1] = { [1] = { "|Hitem:2770::::::::30:::::|h[Copper Ore]|h", 10, false } },
      }
      local sizes = { [0] = 4, [-1] = 2 }
      _G.UnitName = function() return "Holder" end
      _G.GetRealmName = function() return "Classic Beta PvE" end
      _G.ContainerIDToInventoryID = nil
      _G.GetInventoryItemLink = function() return nil end
      _G.GetInventoryItemID = function() return nil end
      _G.GetContainerNumSlots, _G.GetContainerItemLink, _G.GetContainerItemInfo = nil, nil, nil
      _G.GetContainerNumFreeSlots = nil
      _G.C_Container = {
        ContainerIDToInventoryID = function() return nil end,
        GetContainerNumSlots = function(bagID) return sizes[bagID] or 0 end,
        GetContainerItemLink = function(bagID, slot) return slots[bagID] and slots[bagID][slot] and slots[bagID][slot][1] end,
        GetContainerItemInfo = function(bagID, slot)
          local s = slots[bagID] and slots[bagID][slot]
          return s and { stackCount = s[2], isBound = s[3] }
        end,
        GetContainerNumFreeSlots = function() return 0 end,
      }
      _G.time = function() return 1 end
      local now = 1790725000
      _G.GetServerTime = function() return now end
      DS.IsBankOpen = function() return true end

      local char = DS:GetCurrentCharacter()
      char.Containers = {}
      DS:ScanBags()
      now = 1790726000
      DS:ScanBank()

      local env = {}
      local chunk = assert(loadfile("spec/fixtures/holdings_v1.lua"))
      setfenv(chunk, env)
      chunk()
      local golden = env.AltArmyTBC_Data.Characters["Classic Beta PvE"]["Player-4395-00000001"]
      local written = {}
      for bagID, bag in pairs(char.Containers) do
        if bag.numSlots and bag.numSlots > 0 then
          written[bagID] = { numSlots = bag.numSlots, links = bag.links, items = bag.items }
        end
      end
      assert.same(golden.Containers, written)
      assert.are.equal(golden.bagsScannedAt, char.bagsScannedAt)
      assert.are.equal(golden.bankScannedAt, char.bankScannedAt)
      _G.GetServerTime = nil
      _G.C_Container = nil
    end)
  end)
end)
