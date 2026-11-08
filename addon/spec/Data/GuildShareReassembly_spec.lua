--[[
  Unit tests for GuildShareReassembly: AceComm multipart messages put back together whatever order their
  parts arrive in (WoW Forever delivers cross-server whispers in batches of varying order).
  Run from project root: npm test
]]

describe("GuildShareReassembly", function()
  local R, Ser
  local FIRST, NEXT, LAST = string.char(1), string.char(2), string.char(3)

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    if not _G.LibStub then dofile("AltArmy_TBC/Libs/LibStub/LibStub.lua") end
    dofile("AltArmy_TBC/Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
    Ser = {}
    LibStub("AceSerializer-3.0"):Embed(Ser)
    package.path = package.path .. ";AltArmy_TBC/Data/Guild/?.lua"
    require("GuildShareReassembly")
    R = AltArmy.GuildShareReassembly
  end)

  local function decodes(text)
    local ok, msgType = Ser:Deserialize(text)
    return ok == true and type(msgType) == "string"
  end

  --- A card-like message of about `profs` x 70 bytes.
  local function message(tag, profs)
    local list = {}
    for i = 1, profs do
      list[i] = { key = tag .. "prof" .. i, name = "Profession " .. i, rank = 10 * i, count = i, rv = 1000003 * i }
    end
    return Ser:Serialize("CC", { name = tag .. " Stormhoof", realm = "CAMWOW US2 Realm 3 PvE", profs = list })
  end

  --- AceComm's split: 254-byte chunks marked first, next..., last.
  local function split(text)
    if #text <= 255 then return { text } end
    local out = { FIRST .. text:sub(1, 254) }
    local pos = 255
    while pos + 254 <= #text do
      out[#out + 1] = NEXT .. text:sub(pos, pos + 253)
      pos = pos + 254
    end
    out[#out + 1] = LAST .. text:sub(pos)
    return out
  end

  local function receiver(clock)
    local got, dropped = {}, {}
    local r = R.New({
      validate = decodes,
      deliver = function(text, dist, sender) got[#got + 1] = { text = text, dist = dist, sender = sender } end,
      drop = function(parts) dropped[#dropped + 1] = parts end,
      now = function() return clock and clock.t or 0 end,
    })
    return r, got, dropped
  end

  local function feed(r, parts, order, sender)
    for _, i in ipairs(order) do r:OnPart(parts[i], "WHISPER", sender or "Kairu Stormhoof") end
  end

  it("delivers a single message at once", function()
    local r, got = receiver()
    local text = Ser:Serialize("P", { v = 2 })
    r:OnPart(text, "GUILD", "Kairu Stormhoof")
    assert.are.equal(1, #got)
    assert.are.equal(text, got[1].text)
  end)

  it("strips AceComm's escape and ignores reserved control codes", function()
    assert.are.same({ "single", "x" }, { R.Classify(string.char(4) .. "x") })
    assert.is_nil(R.Classify(string.char(6) .. "x"))
    assert.are.same({ "first", "abc" }, { R.Classify(FIRST .. "abc") })
  end)

  describe("numbered parts", function()
    it("splits into parts of at most 255 bytes that say where they go", function()
      local text = message("Long", 16)
      local parts = R.SplitSequenced(text, "a7")
      assert.is_true(#parts >= 5)
      local joined = {}
      for k, part in ipairs(parts) do
        assert.is_true(#part <= 255)
        local id, i, n, data = R.ParseNumbered(part)
        assert.are.same({ "a7", k, #parts }, { id, i, n })
        joined[i] = data
      end
      assert.are.equal(text, table.concat(joined))
      assert.are.equal(1, #R.SplitSequenced("short", "b0"))
    end)

    it("rejects malformed numbered parts", function()
      assert.is_nil(R.ParseNumbered(string.char(5) .. "a7:3/2:x"))
      assert.is_nil(R.ParseNumbered(string.char(5) .. "a7:0/2:x"))
      assert.is_nil(R.ParseNumbered(string.char(5) .. "a7-2/2:x"))
      assert.is_nil(R.ParseNumbered(string.char(5) .. "a7:1/999:x"))
    end)

    it("delivers a numbered message in any arrival order, once", function()
      local text = message("Long", 16)
      local parts = R.SplitSequenced(text, "k2")
      local r, got = receiver()
      for i = #parts, 1, -1 do r:OnPart(parts[i], "WHISPER", "Kairu") end
      r:OnPart(parts[1], "WHISPER", "Kairu")
      assert.are.equal(1, #got)
      assert.are.equal(text, got[1].text)
    end)

    it("keeps numbered messages apart by id and sender, beside AceComm's parts", function()
      local a, b, c = message("A", 6), message("B", 6), message("C", 6)
      local pa, pb, pc = R.SplitSequenced(a, "01"), R.SplitSequenced(b, "02"), split(c)
      local r, got = receiver()
      r:OnPart(pa[2], "WHISPER", "Kairu")
      r:OnPart(pc[3], "WHISPER", "Kairu")
      r:OnPart(pb[2], "WHISPER", "Kairu")
      r:OnPart(pa[1], "WHISPER", "Sylantz")
      r:OnPart(pc[1], "WHISPER", "Kairu")
      r:OnPart(pb[1], "WHISPER", "Kairu")
      r:OnPart(pc[2], "WHISPER", "Kairu")
      r:OnPart(pa[1], "WHISPER", "Kairu")
      for k = 3, #pa do r:OnPart(pa[k], "WHISPER", "Kairu") end
      for k = 3, #pb do r:OnPart(pb[k], "WHISPER", "Kairu") end
      r:FlushAll()
      local texts = {}
      for _, g in ipairs(got) do texts[g.text] = (texts[g.text] or 0) + 1 end
      assert.are.equal(3, #got)
      assert.are.same({ [a] = 1, [b] = 1, [c] = 1 }, texts)
    end)

    it("drops a numbered message still missing a part once it is too old", function()
      local clock = { t = 0 }
      local parts = R.SplitSequenced(message("Long", 16), "k3")
      local r, got, dropped = receiver(clock)
      for i = 2, #parts do r:OnPart(parts[i], "WHISPER", "Kairu") end
      r:ExpireNumbered()
      assert.are.equal(0, #dropped)
      clock.t = R.MAX_AGE_SEC
      r:ExpireNumbered()
      assert.are.equal(0, #got)
      assert.are.equal(1, #dropped)
      assert.are.equal(#parts - 1, #dropped[1])
    end)
  end)

  it("reassembles a three-part message in every arrival order", function()
    local text = message("Kairu", 6)
    local parts = split(text)
    assert.are.equal(3, #parts)
    local orders = { { 1, 2, 3 }, { 1, 3, 2 }, { 2, 1, 3 }, { 2, 3, 1 }, { 3, 1, 2 }, { 3, 2, 1 } }
    for _, order in ipairs(orders) do
      local r, got = receiver()
      feed(r, parts, order)
      r:FlushAll()
      assert.are.equal(1, #got)
      assert.are.equal(text, got[1].text)
    end
  end)

  it("reassembles a long message with several nexts out of order", function()
    local text = message("Long", 16)
    local parts = split(text)
    assert.is_true(#parts >= 5)
    local order = {}
    for i = #parts, 1, -1 do order[#order + 1] = i end
    local r, got = receiver()
    feed(r, parts, order)
    r:FlushAll()
    assert.are.equal(1, #got)
    assert.are.equal(text, got[1].text)
  end)

  it("separates two messages from one sender whose parts arrive interleaved", function()
    local a, b = message("Kairu", 6), message("Recipes", 7)
    local pa, pb = split(a), split(b)
    -- Seen in game: last, first, first, last, next ... (a card and a recipe list in one batch).
    local mixed = { pb[#pb], pa[1], pb[1], pa[3], pa[2] }
    for i = 2, #pb - 1 do mixed[#mixed + 1] = pb[i] end
    local r, got = receiver()
    for _, part in ipairs(mixed) do r:OnPart(part, "WHISPER", "Kairu Stormhoof") end
    r:FlushAll()
    local texts = {}
    for _, g in ipairs(got) do texts[g.text] = true end
    assert.are.equal(2, #got)
    assert.is_true(texts[a])
    assert.is_true(texts[b])
  end)

  it("keeps senders' streams apart", function()
    local a, b = message("Kairu", 6), message("Sylantz", 6)
    local pa, pb = split(a), split(b)
    local r, got = receiver()
    r:OnPart(pa[3], "WHISPER", "Kairu")
    r:OnPart(pb[2], "WHISPER", "Sylantz")
    r:OnPart(pa[1], "WHISPER", "Kairu")
    r:OnPart(pb[1], "WHISPER", "Sylantz")
    r:OnPart(pb[3], "WHISPER", "Sylantz")
    r:OnPart(pa[2], "WHISPER", "Kairu")
    r:FlushAll()
    assert.are.equal(2, #got)
    for _, g in ipairs(got) do
      assert.are.equal(g.sender == "Kairu" and a or b, g.text)
    end
  end)

  it("keeps a message whose last is still to come, then completes it from the next batch", function()
    local clock = { t = 0 }
    local text = message("Long", 16)
    local parts = split(text)
    local r, got, dropped = receiver(clock)
    -- Batch 1: the first and two nexts, shuffled; batch 2 a second later: the rest, shuffled.
    feed(r, parts, { 3, 1, 2 })
    r:FlushAll()
    assert.are.equal(0, #got)
    clock.t = 1
    local rest = {}
    for i = #parts, 4, -1 do rest[#rest + 1] = i end
    feed(r, parts, rest)
    r:FlushAll()
    assert.are.equal(1, #got)
    assert.are.equal(text, got[1].text)
    assert.are.equal(0, #dropped)
  end)

  it("drops the rest of a message whose first never came, and still delivers the next one", function()
    local clock = { t = 0 }
    local lost, text = split(message("Lost", 6)), message("Kairu", 6)
    local parts = split(text)
    local r, got, dropped = receiver(clock)
    r:OnPart(lost[3], "WHISPER", "Kairu Stormhoof")
    r:OnPart(lost[2], "WHISPER", "Kairu Stormhoof")
    clock.t = 1
    feed(r, parts, { 2, 3, 1 })
    r:FlushAll()
    assert.are.equal(1, #got)
    assert.are.equal(text, got[1].text)
    assert.are.equal(1, #dropped)
    assert.are.equal(2, #dropped[1])
  end)

  it("solves a long recipe list shuffled in one batch, well within budget", function()
    local ids = {}
    for i = 1, 300 do ids[i] = 2000 + i * 37 end
    local text = Ser:Serialize("RC", { v = 1, name = "Kairu Stormhoof", realm = "CAMWOW US2 Realm 3 PvE",
      profs = { { key = "alchemy", ids = ids } } })
    local parts = split(text)
    assert.is_true(#parts >= 10)
    -- A fixed shuffle: odd positions descending, then even ascending.
    local order = {}
    for i = #parts, 1, -1 do if i % 2 == 1 then order[#order + 1] = i end end
    for i = 1, #parts do if i % 2 == 0 then order[#order + 1] = i end end
    local list = {}
    for k, i in ipairs(order) do
      local kind, body = R.Classify(parts[i])
      list[k] = { kind = kind, text = body, seq = k, at = 0 }
    end
    local messages, left, dropped, tries = R.Solve(list, decodes)
    assert.are.equal(1, #messages)
    assert.are.equal(text, messages[1])
    assert.are.equal(0, #left + #dropped)
    assert.is_true(tries <= 5)
  end)

  describe("with the real protocol's messages", function()
    local P

    setup(function()
      package.path = package.path .. ";AltArmy_TBC/Data/Guild/?.lua"
      require("GuildShareProtocol")
      P = AltArmy.GuildShareProtocol
    end)

    local seed = 12345
    local function rand(n)
      seed = (seed * 1103515245 + 12345) % 2147483648
      return seed % n + 1
    end

    local NAMES = { "Kairu Stormhoof", "Sylantz Spiritbane", "Touchyfeely Hugs", "Nightcactus Darkthorn" }
    local PROFS = { "Alchemy", "Cooking", "First Aid", "Fishing", "Herbalism", "Leatherworking", "Skinning" }

    local function character(i)
      local profs = {}
      for p = 1, rand(5) do
        local recipes = {}
        for r = 1, rand(60) do recipes[1000 + r * rand(9)] = {} end
        profs[PROFS[(i + p) % #PROFS + 1]] = { rank = rand(300), Recipes = recipes }
      end
      return { name = NAMES[(i - 1) % #NAMES + 1], guid = "Player-6929-00" .. (100000 + i), classFile = "DRUID",
        faction = "Horde", level = rand(60), Professions = profs }
    end

    local function wire(msgType, payload)
      payload.from = "Player-6929-00DCB5DE"
      return Ser:Serialize(msgType, payload)
    end

    local function messages(i)
      local c = character(i)
      local realm = "CAMWOW US2 Realm 3 PvE"
      return {
        wire("PR", P.BuildPresence({ { name = c.name, realm = realm, char = c },
          { name = c.name .. "x", realm = realm, char = character(i + 7) } }, c.name, "Kai")),
        wire("CC", P.BuildCharCard(c.name, realm, c)),
        wire("RC", P.BuildRecipes(c.name, realm, c)),
      }
    end

    it("parses every message the protocol builds", function()
      for i = 1, 40 do
        for _, text in ipairs(messages(i)) do
          assert.truthy(R.Feed(R.NewParse(), text, true), text)
        end
      end
    end)

    it("recovers several messages whose parts arrive shuffled in one batch", function()
      for round = 1, 40 do
        local sent = messages(round)
        local pool = {}
        for _, text in ipairs(sent) do
          for _, part in ipairs(split(text)) do pool[#pool + 1] = part end
        end
        -- Messages from one sender go one after another: shuffle only within each message's batch, and put
        -- each message in a batch of its own or share one with the next.
        local r, got, dropped = receiver({ t = 0 })
        local clock = { t = 0 }
        r = R.New({
          validate = decodes,
          deliver = function(text) got[#got + 1] = text end,
          drop = function(p) dropped[#dropped + 1] = p end,
          now = function() return clock.t end,
        })
        local batchParts = {}
        local function flushBatch()
          for k = #batchParts, 2, -1 do
            local j = rand(k)
            batchParts[k], batchParts[j] = batchParts[j], batchParts[k]
          end
          for _, part in ipairs(batchParts) do r:OnPart(part, "WHISPER", "Kairu Stormhoof") end
          batchParts = {}
          clock.t = clock.t + 1
        end
        for _, text in ipairs(sent) do
          for _, part in ipairs(split(text)) do batchParts[#batchParts + 1] = part end
          if rand(2) == 1 then flushBatch() end
        end
        flushBatch()
        r:FlushAll()
        -- Every message, whole (two sharing a batch may come out in either order: nothing says which was sent first).
        assert.are.equal(#sent, #got)
        local want = {}
        for _, text in ipairs(sent) do want[text] = (want[text] or 0) + 1 end
        for _, text in ipairs(got) do
          assert.truthy(want[text], text)
          want[text] = want[text] - 1
        end
        assert.are.equal(0, #dropped)
      end
    end)
  end)

  it("checks the token across a join", function()
    assert.is_true(R.JunctionOk("^Sname^N12", "34^Sx"))
    assert.is_false(R.JunctionOk("^Sname^N12", "ab^Sx"))
    assert.is_true(R.JunctionOk("^Sname^SProf", "ession^N3"))
    assert.is_false(R.JunctionOk("^T^t", "x^N1"))
    assert.is_true(R.JunctionOk("^N3^", "N4^t"))
    assert.is_false(R.JunctionOk("^N3^", "Q4^t"))
  end)

  it("drops parts that solve nothing once they are too old", function()
    local clock = { t = 0 }
    local parts = split(message("Kairu", 6))
    local r, got, dropped = receiver(clock)
    feed(r, parts, { 1, 3 })
    r:FlushAll()
    clock.t = R.MAX_AGE_SEC + 1
    r:FlushAll()
    assert.are.equal(0, #got)
    assert.are.equal(1, #dropped)
    assert.are.equal(2, #dropped[1])
    assert.are.same({}, r.streams)
  end)

  it("never tries more arrangements than its budget", function()
    local parts = {}
    for i = 1, 10 do parts[#parts + 1] = { kind = "next", text = "x" .. i, seq = i } end
    parts[#parts + 1] = { kind = "first", text = "^1^Sbad", seq = 11 }
    parts[#parts + 1] = { kind = "last", text = "nope", seq = 12 }
    local messages, left, dropped, tries = R.Solve(parts, decodes, 50)
    assert.are.equal(0, #messages)
    assert.are.equal(12, #left + #dropped)
    assert.is_true(tries <= 50)
  end)
end)
