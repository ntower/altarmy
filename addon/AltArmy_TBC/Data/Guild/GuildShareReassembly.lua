-- AltArmy TBC — Guild data sharing: order-independent reassembly of AceComm multipart messages.
--
-- AceComm splits a message over 255 bytes into parts marked first (\001), next (\002) and last (\003), and puts
-- them back together assuming they arrive in order. On WoW Forever, whispers between guildmates on different
-- servers arrive in batches (several parts in one frame) whose order varies (seen 2026-11-07: a card's three
-- parts as next, last, first; a card and a recipe list interleaved), so AceComm glued the wrong pieces and about
-- 40% of multipart replies came out undecodable.
--
-- This receiver takes over CHAT_MSG_ADDON for the guild-share prefix. Single messages are delivered at once.
-- A sender's parts are collected per stream (distribution + sender) until SETTLE_SEC passes with no new part,
-- then solved under what the traces show and how the sender works:
--   - batches keep their order; only the parts within a batch (arrival times within BATCH_EPS) are shuffled
--   - a sender sends one message after another (ChatThrottleLib queues all our prefix's messages in one pipe),
--     so every part before a message's last batch belongs to that message, and every part is used
--   - where two parts join, the token across the join must be a valid AceSerializer token (JunctionOk)
--   - the whole message must deserialize
-- Deserializing alone is not enough: a join that falls inside two strings can drop a whole part and still
-- decode (a card missing professions), which the use-every-part rule rules out. A message whose last hasn't come
-- yet waits; parts at the head of a stream whose first never came are dropped; anything unsolved is dropped after
-- MAX_AGE_SEC.
--
-- Numbered parts: between clients that both have this, a whispered message over 255 bytes is sent in parts
-- that say where they go: "\005" .. id .. ":" .. i .. "/" .. n .. ":" .. data (SplitSequenced), so reassembly is
-- exact and a part truly lost is known. AceComm ignores control codes \005-\009, so a client without this drops
-- such parts silently; senders use them only towards peers that said they read them (GuildShareComm: `mp`).

if not AltArmy then return end

AltArmy.GuildShareReassembly = AltArmy.GuildShareReassembly or {}
local R = AltArmy.GuildShareReassembly

R.SETTLE_SEC = 0.3     -- quiet time on a stream before its parts are solved
R.BATCH_EPS = 0.25     -- parts arriving this close together are one batch (their order unknown)
R.MAX_AGE_SEC = 15     -- unsolved parts are dropped this long after they arrived
R.MAX_PARTS = 64       -- per stream; the oldest go first
R.BUDGET = 300         -- whole messages deserialized per solve
R.STEP_BUDGET = 5000   -- parts parsed per solve (each a few hundred bytes)
R.MAX_SUBSET = 10      -- nexts in one batch split between messages by trying subsets (else all to one)

local KINDS = { ["\001"] = "first", ["\002"] = "next", ["\003"] = "last" }
local ESCAPE = "\004"
local NUMBERED = "\005"
R.MAX_LEN = 255        -- an addon message's bytes
R.MAX_NUMBERED = 64    -- parts in one numbered message

--- The kind of a raw part and its text: "first", "next", "last", "single", or nil for a control code AceComm
--- reserves (ignored, as AceComm does).
function R.Classify(message)
    if type(message) ~= "string" or message == "" then return nil end
    local c = message:sub(1, 1)
    local kind = KINDS[c]
    if kind then return kind, message:sub(2) end
    if c == ESCAPE then return "single", message:sub(2) end
    if c == NUMBERED then return "numbered", message end
    if c:byte() >= 1 and c:byte() <= 9 then return nil end
    return "single", message
end

local function numberedHeader(id, i, n)
    return NUMBERED .. id .. ":" .. i .. "/" .. n .. ":"
end

--- Split `text` into numbered parts of at most MAX_LEN bytes under message id `id` (letters and digits).
function R.SplitSequenced(text, id)
    local n = 1
    while true do
        local room = R.MAX_LEN - #numberedHeader(id, n, n)
        if n * room >= #text then
            local out = {}
            for i = 1, n do
                out[i] = numberedHeader(id, i, n) .. text:sub((i - 1) * room + 1, i * room)
            end
            return out
        end
        n = n + 1
    end
end

--- A numbered part's id, place, count and data, or nil when malformed.
function R.ParseNumbered(message)
    if type(message) ~= "string" then return nil end
    local id, i, n, data = message:match("^\005(%w+):(%d+)/(%d+):(.*)$")
    i, n = tonumber(i), tonumber(n)
    if not id or not i or not n or n < 1 or i < 1 or i > n or n > R.MAX_NUMBERED then return nil end
    return id, i, n, data
end

-- AceSerializer tokens: "^" + a type and its payload, up to the next "^" (carets inside strings are escaped).
local EMPTY_PAYLOAD = { T = true, t = true, B = true, b = true, Z = true, ["^"] = true, ["1"] = true }
local NUMERIC_PAYLOAD = { N = true, F = true, f = true }

--- Whether a whole token ("^" + type + payload) is one AceSerializer writes.
function R.TokenOk(token)
    local t = token:sub(2, 2)
    if t == "" then return true end
    local payload = token:sub(3)
    if t == "S" then return true end
    if NUMERIC_PAYLOAD[t] then
        -- AceSerializer writes infinity as "1.#INF" / "-1.#INF" (or "inf" / "-inf").
        return tonumber(payload) ~= nil or payload == "1.#INF" or payload == "-1.#INF"
            or payload == "inf" or payload == "-inf"
    end
    if EMPTY_PAYLOAD[t] then return payload == "" end
    return false
end

--- Whether part `b` can follow part `a`: the token across the join is valid.
function R.JunctionOk(a, b)
    local caret = a:match(".*()%^")
    if not caret then return true end
    local stop = b:find("^", 1, true)
    if not stop then return true end
    return R.TokenOk(a:sub(caret) .. b:sub(1, stop - 1))
end

-- *** Incremental parse: the text so far must be a valid start of one of our messages ***
-- Besides each token being valid, every table's integer keys must run 1, 2, 3... in the order they appear: our
-- messages' lists (characters, professions, recipe ids) are arrays, which AceSerializer writes through pairs()
-- in index order. Recipe lists are nearly all numbers, so without this almost any order of their parts joins
-- into valid tokens and deserializes; with it a part out of place breaks the count within a few tokens.

--- A parse state at the start of a message.
function R.NewParse()
    return { stack = {}, pending = "" }
end

local function cloneParse(s)
    local stack = {}
    for i, t in ipairs(s.stack) do stack[i] = { key = t.key, nextIndex = t.nextIndex } end
    return { stack = stack, pending = s.pending }
end

-- One whole token; false when it can't be there.
local function step(stack, t, payload)
    if not R.TokenOk("^" .. t .. payload) then return false end
    if t == "1" or t == "^" or t == "f" then return true end  -- version, end, a float's exponent
    local top = stack[#stack]
    if t == "t" then
        if not top or not top.key then return false end
        stack[#stack] = nil
        local parent = stack[#stack]
        if parent then parent.key = true end
        return true
    end
    if top and top.key then
        if t == "T" then return false end  -- our messages never key by a table
        if t == "N" then
            local n = tonumber(payload)
            if n and n >= 1 and n == math.floor(n) then
                if n ~= top.nextIndex then return false end
                top.nextIndex = n + 1
            end
        end
        top.key = false
        return true
    end
    if t == "T" then
        stack[#stack + 1] = { key = true, nextIndex = 1 }
        return true
    end
    if top then top.key = true end
    return true
end

--- The parse state after `chunk` (the message's end when `final`), or nil when the text can't be one of ours.
function R.Feed(state, chunk, final)
    local s = cloneParse(state)
    local text = s.pending .. chunk
    local stop
    if final then
        stop = #text + 1
    else
        stop = text:match(".*()%^")
        if not stop then
            s.pending = text
            return s
        end
    end
    local body = text:sub(1, stop - 1)
    s.pending = text:sub(stop)
    if body ~= "" and body:sub(1, 1) ~= "^" then return nil end
    for t, payload in body:gmatch("%^(.)([^%^]*)") do
        if not step(s.stack, t, payload) then return nil end
    end
    if final and #s.stack ~= 0 then return nil end
    return s
end

local function copy(list)
    local out = {}
    for i, v in ipairs(list) do out[i] = v end
    return out
end

--- Solve a stream's parts ({ kind, text, seq, at }). Returns the messages (texts, in the order sent), the
--- indices to keep for later (a message still open, or what could not be solved yet), the indices to drop (the
--- rest of a message whose first never came) and the messages deserialized. `validate(text)` says whether a
--- text decodes.
function R.Solve(parts, validate, budget)
    budget = budget or R.BUDGET
    local order = {}
    for i in ipairs(parts) do order[#order + 1] = i end
    table.sort(order, function(a, b)
        local ta, tb = parts[a].at or 0, parts[b].at or 0
        if ta ~= tb then return ta < tb end
        return parts[a].seq < parts[b].seq
    end)
    local batch, b, start = {}, 0, nil
    for _, i in ipairs(order) do
        local at = parts[i].at or 0
        if not start or at - start > R.BATCH_EPS then
            b = b + 1
            start = at
        end
        batch[i] = b
    end

    local tries, steps = 0, 0
    local function spent() return tries >= budget or steps >= R.STEP_BUDGET end
    local result
    local best = { messages = {}, remaining = order, dropped = {} }

    -- Arrange f, the nexts of each group (in group order, any order within a group) and l; call onFound with
    -- the text and the parts used for each arrangement that decodes, until it returns true.
    local function arrange(f, groups, l, onFound)
        local seq, used = { f }, {}
        steps = steps + 1
        local startState = R.Feed(R.NewParse(), parts[f].text)
        if not startState then return false end
        local function rec(g, k, state)
            if spent() then return false end
            if g > #groups then
                steps = steps + 1
                if not R.Feed(state, parts[l].text, true) then return false end
                tries = tries + 1
                local buf = {}
                for i, pi in ipairs(seq) do buf[i] = parts[pi].text end
                buf[#buf + 1] = parts[l].text
                local text = table.concat(buf)
                if validate(text) then return onFound(text, seq) end
                return false
            end
            local group = groups[g]
            if k >= #group then return rec(g + 1, 0, state) end
            for _, ni in ipairs(group) do
                if not used[ni] then
                    steps = steps + 1
                    local nextState = R.Feed(state, parts[ni].text)
                    if nextState then
                        used[ni] = true
                        seq[#seq + 1] = ni
                        if rec(g, k + 1, nextState) then return true end
                        seq[#seq] = nil
                        used[ni] = nil
                    end
                    if spent() then return false end
                end
            end
            return false
        end
        return rec(1, 0, startState)
    end

    -- Subsets of `list`, largest first, each passed to fn until it returns true.
    local function subsets(list, fn)
        for size = #list, 0, -1 do
            local pick = {}
            local function rec(from)
                if #pick == size then return fn(copy(pick)) end
                for i = from, #list - (size - #pick) + 1 do
                    pick[#pick + 1] = list[i]
                    if rec(i + 1) then return true end
                    pick[#pick] = nil
                end
                return false
            end
            if rec(1) then return true end
            if spent() then return false end
        end
        return false
    end

    local build
    build = function(remaining, messages, dropped)
        if #messages > #best.messages then
            best = { messages = copy(messages), remaining = remaining, dropped = copy(dropped) }
        end
        if #remaining == 0 then
            result = { messages = copy(messages), remaining = {}, dropped = copy(dropped) }
            return true
        end
        local headBatch = batch[remaining[1]]
        local head, firsts = {}, {}
        for _, i in ipairs(remaining) do
            if batch[i] ~= headBatch then break end
            head[#head + 1] = i
            if parts[i].kind == "first" then firsts[#firsts + 1] = i end
        end
        if #firsts == 0 then
            -- The rest of a message whose first never came: drop it.
            local rest, d = {}, copy(dropped)
            for k, i in ipairs(remaining) do
                if k <= #head then d[#d + 1] = i else rest[#rest + 1] = i end
            end
            return build(rest, messages, d)
        end
        local firstCount, hasLast = 0, false
        for _, i in ipairs(remaining) do
            if parts[i].kind == "first" then firstCount = firstCount + 1 end
            if parts[i].kind == "last" then hasLast = true end
        end
        if not hasLast then
            -- A message still open (its last to come): keep it.
            if firstCount == 1 then
                result = { messages = copy(messages), remaining = remaining, dropped = copy(dropped) }
                return true
            end
            return false
        end
        for _, f in ipairs(firsts) do
            for _, l in ipairs(remaining) do
                if parts[l].kind == "last" then
                    local lastBatch = batch[l]
                    local byBatch, batches, closing, otherFirst, ok = {}, {}, {}, false, true
                    for _, i in ipairs(remaining) do
                        if i ~= f and i ~= l then
                            if batch[i] < lastBatch then
                                if parts[i].kind ~= "next" then
                                    ok = false
                                    break
                                end
                                if not byBatch[batch[i]] then
                                    byBatch[batch[i]] = {}
                                    batches[#batches + 1] = batch[i]
                                end
                                table.insert(byBatch[batch[i]], i)
                            elseif batch[i] == lastBatch then
                                if parts[i].kind == "next" then
                                    closing[#closing + 1] = i
                                elseif parts[i].kind == "first" then
                                    otherFirst = true
                                end
                            end
                        end
                    end
                    if ok then
                        local fixed = {}
                        for _, bi in ipairs(batches) do fixed[#fixed + 1] = byBatch[bi] end
                        local function try(subset)
                            local groups = copy(fixed)
                            if #subset > 0 then groups[#groups + 1] = subset end
                            return arrange(f, groups, l, function(text, seq)
                                local consumed = { [l] = true }
                                for _, pi in ipairs(seq) do consumed[pi] = true end
                                local rest = {}
                                for _, i in ipairs(remaining) do
                                    if not consumed[i] then rest[#rest + 1] = i end
                                end
                                messages[#messages + 1] = text
                                if build(rest, messages, dropped) then return true end
                                messages[#messages] = nil
                                return false
                            end)
                        end
                        local found
                        if otherFirst and #closing <= R.MAX_SUBSET then
                            found = subsets(closing, try)
                        else
                            -- No later message starts in this batch: its nexts are all this message's.
                            found = try(closing)
                        end
                        if found then return true end
                        if spent() then return false end
                    end
                end
            end
        end
        return false
    end

    local final = build(order, {}, {}) and result or best
    return final.messages, final.remaining, final.dropped, tries
end

--- A receiver. `opts`: validate(text) -> bool; deliver(text, distribution, sender); drop(parts, distribution,
--- sender) for parts given up on (optional); now() -> seconds; after(sec, fn) (a timer: C_Timer.After in game;
--- none in tests, which call Flush).
function R.New(opts)
    local obj = { streams = {}, seq = 0, numbered = {} }
    local now = opts.now or function() return (GetTime and GetTime()) or 0 end
    local after = opts.after

    local function schedule(key, stream, delay)
        if not after then return end
        local gen = stream.gen
        after(delay, function()
            if obj.streams[key] == stream and stream.gen == gen then obj:Flush(key) end
        end)
    end

    function obj:OnPart(message, distribution, sender)
        local kind, text = R.Classify(message)
        if not kind then return end
        if kind == "single" then
            opts.deliver(text, distribution, sender)
            return
        end
        local key = tostring(distribution) .. "\t" .. tostring(sender)
        if kind == "numbered" then
            self:OnNumbered(key, text, distribution, sender)
            return
        end
        local stream = self.streams[key]
        if not stream then
            stream = { parts = {}, gen = 0, distribution = distribution, sender = sender }
            self.streams[key] = stream
        end
        self.seq = self.seq + 1
        stream.parts[#stream.parts + 1] = { kind = kind, text = text, seq = self.seq, at = now() }
        while #stream.parts > R.MAX_PARTS do table.remove(stream.parts, 1) end
        stream.gen = stream.gen + 1
        schedule(key, stream, R.SETTLE_SEC)
    end

    -- The parts a numbered message got, for the drop callback.
    local function numberedParts(m)
        local out = {}
        for k = 1, m.n do
            if m.parts[k] then out[#out + 1] = { kind = "numbered", text = m.parts[k], index = k } end
        end
        return out
    end

    -- A numbered part: delivered with the rest of its message as soon as all are in, whatever their order.
    function obj:OnNumbered(key, message, distribution, sender)
        local id, i, n, data = R.ParseNumbered(message)
        if not id then return end
        local mkey = key .. "\t" .. id
        local m = self.numbered[mkey]
        if m and m.n ~= n then
            -- The id came round again: the old message never completed.
            self.numbered[mkey] = nil
            if opts.drop then opts.drop(numberedParts(m), distribution, sender) end
            m = nil
        end
        if not m then
            m = { n = n, parts = {}, count = 0, at = now(), distribution = distribution, sender = sender }
            self.numbered[mkey] = m
            if after then
                after(R.MAX_AGE_SEC, function()
                    if self.numbered[mkey] == m then
                        self.numbered[mkey] = nil
                        if opts.drop then opts.drop(numberedParts(m), distribution, sender) end
                    end
                end)
            end
        end
        if not m.parts[i] then
            m.parts[i] = data
            m.count = m.count + 1
        end
        if m.count == m.n then
            self.numbered[mkey] = nil
            opts.deliver(table.concat(m.parts, "", 1, m.n), distribution, sender)
        end
    end

    --- Drop numbered messages still incomplete after MAX_AGE_SEC (the timer's job in game; tests call this).
    function obj:ExpireNumbered()
        local t = now()
        local expired = {}
        for mkey, m in pairs(self.numbered) do
            if t - m.at >= R.MAX_AGE_SEC then expired[#expired + 1] = mkey end
        end
        for _, mkey in ipairs(expired) do
            local m = self.numbered[mkey]
            self.numbered[mkey] = nil
            if opts.drop then opts.drop(numberedParts(m), m.distribution, m.sender) end
        end
    end

    function obj:Flush(key)
        local stream = self.streams[key]
        if not stream then return end
        local messages, remaining, droppedIdx = R.Solve(stream.parts, opts.validate)
        local t = now()
        local keep, dropped = {}, {}
        for _, i in ipairs(droppedIdx) do dropped[#dropped + 1] = stream.parts[i] end
        for _, i in ipairs(remaining) do
            local p = stream.parts[i]
            if t - p.at >= R.MAX_AGE_SEC then
                dropped[#dropped + 1] = p
            else
                keep[#keep + 1] = p
            end
        end
        if #keep == 0 then
            self.streams[key] = nil
        else
            stream.parts = keep
            stream.gen = stream.gen + 1
            schedule(key, stream, R.MAX_AGE_SEC)
        end
        for _, text in ipairs(messages) do
            opts.deliver(text, stream.distribution, stream.sender)
        end
        if #dropped > 0 and opts.drop then
            opts.drop(dropped, stream.distribution, stream.sender)
        end
    end

    function obj:FlushAll()
        local keys = {}
        for key in pairs(self.streams) do keys[#keys + 1] = key end
        for _, key in ipairs(keys) do self:Flush(key) end
    end

    return obj
end
