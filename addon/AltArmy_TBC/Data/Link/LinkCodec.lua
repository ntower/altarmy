-- AltArmy TBC — Linked accounts' messages on the wire.
-- Pure (the libraries are passed in). A message (a table with `t`, its type) becomes a payload: AceSerializer,
-- then zlib (LibDeflate, whose Adler-32 checksum catches a damaged payload), then LibDeflate's encoding for
-- addon channels. A payload is sent as chunks of at most MAX_CHUNK bytes, "<msgId>|<seq>|<total>|<data>":
-- Battle.net game data arrives in any order (ChatThrottleLib's note), so the receiver puts chunks back
-- together by sequence number (C.NewReassembler), within limits: at most MAX_TOTAL chunks a message,
-- MAX_PARTIAL messages in flight per sender, a message not finished in TIMEOUT seconds is dropped.
-- A dropped message is not asked for again by chunk: the sync asks for the whole unit again.

AltArmy = AltArmy or {}
AltArmy.LinkCodec = AltArmy.LinkCodec or {}
local C = AltArmy.LinkCodec

C.MAX_CHUNK = 255
C.MAX_TOTAL = 800 -- chunks of one message (about 190 KB on the wire)
C.MAX_PARTIAL = 4
C.MAX_RAW = 2 * 1024 * 1024 -- bytes a message may inflate to
C.TIMEOUT = 90

--- The libraries: { serializer = AceSerializer-3.0, deflate = LibDeflate } (from LibStub in game).
function C.LiveLibs()
    local stub = rawget(_G, "LibStub")
    if not stub then
        return nil
    end
    local serializer = stub("AceSerializer-3.0", true)
    local deflate = stub("LibDeflate", true)
    if not serializer or not deflate then
        return nil
    end
    return { serializer = serializer, deflate = deflate }
end

--- A message as a payload string.
function C.Encode(msg, libs)
    local raw = libs.serializer:Serialize(msg)
    local packed = libs.deflate:CompressZlib(raw, { level = 5 })
    return libs.deflate:EncodeForWoWAddonChannel(packed)
end

--- The message in a payload; nil and why if it is not one.
function C.Decode(payload, libs)
    if type(payload) ~= "string" then
        return nil, "badPayload"
    end
    local packed = libs.deflate:DecodeForWoWAddonChannel(payload)
    if not packed then
        return nil, "badEncoding"
    end
    local okInflate, raw = pcall(libs.deflate.DecompressZlib, libs.deflate, packed)
    if not okInflate or type(raw) ~= "string" then
        return nil, "badZlib"
    end
    if #raw > C.MAX_RAW then
        return nil, "tooBig"
    end
    local okDecode, ok, msg = pcall(libs.serializer.Deserialize, libs.serializer, raw)
    if not okDecode or not ok or type(msg) ~= "table" or type(msg.t) ~= "string" then
        return nil, "badMessage"
    end
    return msg
end

--- A payload as chunks for message `msgId` (a short string without "|").
function C.Split(payload, msgId)
    local headLen = #msgId + 12 -- "|", seq and total up to 4 digits each, "|"s
    local size = C.MAX_CHUNK - headLen
    local total = math.max(1, math.ceil(#payload / size))
    local chunks = {}
    for seq = 1, total do
        chunks[seq] = msgId .. "|" .. seq .. "|" .. total .. "|" .. payload:sub((seq - 1) * size + 1, seq * size)
    end
    return chunks
end

--- The parts of one chunk: msgId, seq, total, data; nil if it is not one.
function C.ParseChunk(chunk)
    if type(chunk) ~= "string" or #chunk > C.MAX_CHUNK then
        return nil
    end
    local msgId, seq, total, data = chunk:match("^([%w%-]+)|(%d+)|(%d+)|(.*)$")
    seq, total = tonumber(seq), tonumber(total)
    if not msgId or not seq or not total or total < 1 or total > C.MAX_TOTAL or seq < 1 or seq > total then
        return nil
    end
    return msgId, seq, total, data
end

local Reassembler = {}
Reassembler.__index = Reassembler

--- Puts chunks back together, per sender. `r:Add(sender, chunk, now)` returns the whole payload when its
--- last chunk arrives, else nil (and why when the chunk was refused).
function C.NewReassembler()
    return setmetatable({ partial = {} }, Reassembler)
end

function Reassembler:Prune(now)
    for sender, msgs in pairs(self.partial) do
        local left = false
        for msgId, m in pairs(msgs) do
            if now - m.at > C.TIMEOUT then
                msgs[msgId] = nil
            else
                left = true
            end
        end
        if not left then
            self.partial[sender] = nil
        end
    end
end

function Reassembler:Add(sender, chunk, now)
    local msgId, seq, total, data = C.ParseChunk(chunk)
    if not msgId then
        return nil, "badChunk"
    end
    self:Prune(now)
    local msgs = self.partial[sender]
    if not msgs then
        msgs = {}
        self.partial[sender] = msgs
    end
    local m = msgs[msgId]
    if not m then
        local count = 0
        for _ in pairs(msgs) do count = count + 1 end
        if count >= C.MAX_PARTIAL then
            return nil, "tooManyPartial"
        end
        m = { total = total, parts = {}, have = 0, at = now }
        msgs[msgId] = m
    elseif m.total ~= total then
        msgs[msgId] = nil
        return nil, "badChunk"
    end
    m.at = now
    if not m.parts[seq] then
        m.parts[seq] = data
        m.have = m.have + 1
    end
    if m.have < m.total then
        return nil
    end
    msgs[msgId] = nil
    return table.concat(m.parts, "", 1, m.total)
end

return C
