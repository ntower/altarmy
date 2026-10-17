--[[ Unit tests for Link/LinkCodec.lua — run: npm test ]]

describe("LinkCodec", function()
  local C, libs

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    if not _G.LibStub then
      dofile("AltArmy_TBC/Libs/LibStub/LibStub.lua")
    end
    dofile("AltArmy_TBC/Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
    dofile("AltArmy_TBC/Libs/LibDeflate/LibDeflate.lua")
    require("LinkCodec")
    C = AltArmy.LinkCodec
    libs = C.LiveLibs()
    assert.truthy(libs)
  end)

  local function bigMessage()
    local items = {}
    for i = 1, 400 do
      items[i] = { itemID = 1000 + i, count = i % 20, link = "|cnIQ1:|Hitem:" .. (1000 + i) .. "::::|h[Thing " .. i .. "]|h|r" }
    end
    return { t = "DATA", g = "Player-1-A", r = "Realm", u = { containers = { Containers = { { items = items } } } } }
  end

  it("round-trips a message", function()
    local msg = bigMessage()
    assert.are.same(msg, C.Decode(C.Encode(msg, libs), libs))
  end)

  it("splits into chunks of at most 255 bytes and puts them back in any order", function()
    local payload = C.Encode(bigMessage(), libs)
    local chunks = C.Split(payload, "ab1")
    assert.is_true(#chunks > 3)
    for _, ch in ipairs(chunks) do
      assert.is_true(#ch <= C.MAX_CHUNK)
    end
    local r = C.NewReassembler()
    local order = {}
    for i = #chunks, 1, -1 do order[#order + 1] = chunks[i] end
    table.insert(order, 2, chunks[1]) -- a duplicate
    local got
    for _, ch in ipairs(order) do
      got = r:Add(7, ch, 100) or got
    end
    assert.are.equal(payload, got)
  end)

  it("keeps senders and messages apart", function()
    local a = C.Split(C.Encode({ t = "A" }, libs) .. string.rep("x", 600), "m1")
    local b = C.Split(C.Encode({ t = "B" }, libs) .. string.rep("y", 600), "m1")
    local r = C.NewReassembler()
    for i = 1, #a - 1 do r:Add(1, a[i], 0) end
    for i = 1, #b - 1 do r:Add(2, b[i], 0) end
    assert.truthy(r:Add(1, a[#a], 0):find("x", 1, true))
    assert.truthy(r:Add(2, b[#b], 0):find("y", 1, true))
  end)

  it("drops a message not finished in time, and caps messages in flight", function()
    local r = C.NewReassembler()
    local chunks = C.Split(string.rep("z", 1000), "slow")
    r:Add(1, chunks[1], 0)
    assert.is_nil(r:Add(1, chunks[2], C.TIMEOUT + 1)) -- the first part was dropped, so not done
    for i = 1, C.MAX_PARTIAL - 1 do
      r:Add(3, C.Split(string.rep("q", 1000), "p" .. i)[1], 0)
    end
    r:Add(3, C.Split(string.rep("q", 1000), "last")[1], 0)
    assert.are.same({ nil, "tooManyPartial" }, { r:Add(3, C.Split(string.rep("q", 1000), "over")[1], 0) })
  end)

  it("refuses chunks that aren't, and payloads that are damaged", function()
    local r = C.NewReassembler()
    assert.are.same({ nil, "badChunk" }, { r:Add(1, "nonsense", 0) })
    assert.are.same({ nil, "badChunk" }, { r:Add(1, "id|5|2|x", 0) })
    assert.are.same({ nil, "badChunk" }, { r:Add(1, "id|1|" .. (C.MAX_TOTAL + 1) .. "|x", 0) })
    local payload = C.Encode({ t = "HELLO", acct = "abc" }, libs)
    local damaged = payload:sub(1, 5) .. string.char((payload:byte(6) % 200) + 1) .. payload:sub(7)
    assert.is_nil(C.Decode(damaged, libs))
    assert.is_nil(C.Decode("", libs))
    assert.is_nil(C.Decode(C.Encode({ x = 1 }, libs), libs)) -- no type
  end)
end)
