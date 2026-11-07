local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

-- Layer books move only when a layer is set or another client asks for one.
-- Relayed observations retain their original age and claim identity.
local Sync = {}
iRC.LayerSync = Sync
local PREFIX, VERSION = "iRCLayerV1", tostring(iRC.LayerWireVersion or "8")
local LIFETIME, CHUNK_SIZE, MAX_PARTS = 300, 120, 192
local requests, replies, transfers, sentBooks, reconciliations, relays = {}, {}, {}, {}, {}, {}
local sequence = 0
local lastVerificationAt
local CHANNEL_NAME = "iRCCommsV1"
local channelRejected = false
local function now() return GetTime and GetTime() or 0 end
local function key(name)
    if iRC:IsSecretValue(name) or type(name) ~= "string" then return "" end
    return iRC:IsForeverClient() and iRC:NormalizeName(name) or name:lower()
end
local function fields(value)
    local result = {}
    for field in (value .. "\t"):gmatch("([^\t]*)\t") do result[#result + 1] = field end
    return result
end
local function integer(value, minimum, maximum)
    local result = tonumber(value)
    if result and result == result and result >= minimum and result <= maximum and result == math.floor(result) then return result end
end
local function hex(value)
    return (value:gsub(".", function(character) return string.format("%02x", string.byte(character)) end))
end
local function unhex(value)
    if #value % 2 ~= 0 or #value > 256 or value:find("[^%x]") then return nil end
    return (value:gsub("..", function(pair) return string.char(tonumber(pair, 16)) end))
end
local function checksum(value)
    local hash = 5381
    for index = 1, #value do hash = (hash * 33 + value:byte(index)) % 2147483647 end
    return string.format("%x", hash)
end
local function encode(rows, omitObservation)
    local encoded = {}
    for _, row in ipairs(rows) do
        encoded[#encoded + 1] = table.concat({ row.identityKey, row.preferredNumber,
            row.createdAt, omitObservation and 0 or row.observedAt, hex(row.owner) }, ",")
    end
    return table.concat(encoded, ";")
end
local function decode(value)
    local rows = {}
    if #value > CHUNK_SIZE * MAX_PARTS then return nil end
    for line in value:gmatch("[^;]+") do
        local id, preferred, created, observed, owner = line:match("^([%d%-]+),(%d+),([%d%.]+),([%d%.]+),(%x+)$")
        owner = owner and unhex(owner)
        if not owner or #rows >= 99 then return nil end
        rows[#rows + 1] = { identityKey = id, preferredNumber = tonumber(preferred),
            createdAt = tonumber(created), observedAt = tonumber(observed), owner = owner }
    end
    return rows
end
local function clean()
    local clock = now()
    for _, records in ipairs({ requests, replies, transfers, sentBooks, reconciliations, relays }) do
        local count, oldest, oldestAt = 0, nil, math.huge
        for id, record in pairs(records) do
            if record.expiresAt <= clock then records[id] = nil
            else
                count = count + 1
                if record.expiresAt < oldestAt then oldest, oldestAt = id, record.expiresAt end
            end
        end
        if count >= 64 and oldest then records[oldest] = nil end
    end
end
local function nonce(update)
    sequence = sequence + 1
    return (update and "u" or "q") .. checksum(key(iRC:GetPlayerName()))
        .. string.format("%x%x", math.floor(now() * 1000) % 0xffffff, sequence % 0xffff)
end
local function channelId()
    if type(GetChannelName) ~= "function" then return nil end
    local ok, id = pcall(GetChannelName, CHANNEL_NAME)
    if not ok or iRC:IsSecretValue(id) or type(id) ~= "number" or id <= 0 or id ~= math.floor(id) then return nil end
    return tostring(id)
end

function Sync:GetChannelTarget()
    if channelRejected or not iRC.GetGuildDirectoryScope or not iRC:GetGuildDirectoryScope() then return nil end
    return channelId()
end

function Sync:IsChannelTarget(target)
    if iRC:IsSecretValue(target) or target == nil then return false end
    local id = channelId()
    return id ~= nil and tostring(target) == id
end

function Sync:OnChannelSendResult(sent, result, kind)
    local codes = Enum and Enum.SendAddonMessageResult or {}
    if sent and kind == "LAYER_QUERY" then
        iRC:DebugMsg("Layer query accepted by the addon-channel API on iRCCommsV1; server ruleset=" .. tostring(iRC:GetGuildDirectoryScope()) .. ".", 3)
    end
    if not sent and result == (codes.InvalidChatType or 4) and not channelRejected then
        channelRejected = true
        iRC:DebugMsg("Layer query on iRCCommsV1 was rejected by this client's addon-channel API; using guild/group/friends for this session.", 3)
    end
end

local function channels()
    local result = {}
    if Sync:GetChannelTarget() then result[#result + 1] = "CHANNEL" end
    if iRC.GetGuildKey and iRC:GetGuildKey() ~= nil then result[#result + 1] = "GUILD" end
    if iRC.GuildMap and iRC.GuildMap.GetLayerGroupDistribution then
        local distribution = iRC.GuildMap:GetLayerGroupDistribution()
        if distribution == "PARTY" or distribution == "RAID" then result[#result + 1] = distribution end
    end
    return result
end
local function send(message, distribution, target)
    if distribution == "CHANNEL" then
        target = target or Sync:GetChannelTarget()
        local scope = iRC:GetGuildDirectoryScope()
        if not target or not scope then return false end
        message = message .. "\t@" .. scope
    end
    if #message > 255 then return false end
    return iRC:SendAddonTraffic(PREFIX, message, distribution, target) == true
end
local function fingerprint(rows)
    -- A more recent sighting does not change the shared numbering. Comparing
    -- claim identity here prevents a guild from echoing the same book back.
    return checksum(encode(rows, true))
end
local function responderRank(name)
    local normalized = key(name)
    return string.format("%03d:%s", tonumber(checksum(normalized), 16) % 900, normalized)
end
local function transferKey(id, sender, serverId, mapId)
    return id .. ":" .. key(sender) .. ":" .. serverId .. ":" .. mapId
end
local function notify(serverId, mapId, rows)
    local confirmed = {}
    for _, row in ipairs(rows) do confirmed[row.identityKey] = true end
    if iRC.GuildMap and iRC.GuildMap.OnLayerRegistryMerged then iRC.GuildMap:OnLayerRegistryMerged(serverId, mapId, confirmed) end
end
local answer
local function sendBook(id, serverId, mapId, distribution, target, response)
    local chunkSize = CHUNK_SIZE
    if distribution == "CHANNEL" then
        target = Sync:GetChannelTarget()
        local scope = iRC:GetGuildDirectoryScope()
        if not target or not scope then return false end
        local header = table.concat({ "LAYER_BOOK", VERSION, id, serverId, mapId, MAX_PARTS, MAX_PARTS, "ffffffff", "" }, "\t")
        chunkSize = math.min(chunkSize, 255 - #header - #scope - 2)
        if chunkSize < 1 then return false end
    end
    local rows = iRC.LayerRegistry:Export(serverId, mapId)
    if iRC.GuildMap and iRC.GuildMap.OnLayerRegistryMerged then iRC.GuildMap:OnLayerRegistryMerged(serverId, mapId, false) end
    local wire, identity = encode(rows), fingerprint(rows)
    if wire == "" then return false end
    local hash, total = checksum(wire), math.ceil(#wire / chunkSize)
    if total > MAX_PARTS then
        iRC:DebugMsg("Layer registry is too large to share for map " .. mapId .. ".", 2)
        return false
    end
    local contextKey = transferKey(id, target or "", serverId, mapId) .. ":" .. distribution
    local previous = sentBooks[contextKey]
    if previous and previous.hash == hash and not previous.cancelled and previous.expiresAt > now() then return false end
    if distribution ~= "WHISPER" and response then
        for _, outgoing in pairs(sentBooks) do
            if outgoing.serverId == serverId and outgoing.mapId == mapId and outgoing.distribution == distribution
                and outgoing.identity == identity and not outgoing.complete and not outgoing.cancelled
                and outgoing.expiresAt > now() then
                -- One broadcast can answer several overlapping requests. Wait
                -- for it rather than adding another full snapshot to the queue.
                if C_Timer and C_Timer.After then C_Timer.After(1, function() answer(response) end) end
                return false
            end
        end
    end
    sentBooks[contextKey] = { hash = hash, identity = identity, response = response, serverId = serverId,
        mapId = mapId, distribution = distribution, sentParts = {}, total = total, expiresAt = now() + LIFETIME }
    local sent = false
    for part = 1, total do
        local packet = table.concat({ "LAYER_BOOK", VERSION, id, serverId, mapId, part, total, hash,
            wire:sub((part - 1) * chunkSize + 1, part * chunkSize) }, "\t")
        if send(packet, distribution, target) then sent = true end
    end
    return sent
end

function Sync:IsMessage(kind)
    return kind == "LAYER_QUERY" or kind == "LAYER_BOOK" or kind == "LAYER_MISSING"
end

function Sync:IsExpectedReply(message, sender)
    if type(message) ~= "string" then return false end
    local parts = fields(message)
    local request = requests[parts[3]]
    local response = replies[transferKey(parts[3] or "", sender, parts[4] or "", parts[5] or "")]
    local expected = request ~= nil and request.expiresAt > now() and request.peers[key(sender)] == true
        and tonumber(parts[4]) == request.serverId and tonumber(parts[5]) == request.mapId
    return (expected or response ~= nil and response.expiresAt > now())
        and (parts[1] == "LAYER_BOOK" or parts[1] == "LAYER_MISSING")
end

function Sync:AllowsPacket(kind, message, distribution, target)
    if distribution == "CHANNEL" and (not self:GetChannelTarget() or not self:IsChannelTarget(target)
        or not iRC:IsGuildDirectoryPacketCurrent(message)) then return false end
    local parts = fields(message)
    if parts[2] ~= VERSION then return false end
    local id, targetKey = parts[3], key(target)
    if kind == "LAYER_QUERY" then
        local request = requests[id]
        return request ~= nil and request.expiresAt > now()
            and (not iRC.GuildMap or not iRC.GuildMap.IsLayerLookupCurrent or iRC.GuildMap:IsLayerLookupCurrent(request))
            and (distribution ~= "WHISPER"
            or request.peers[targetKey] == true
                and (iRC:IsRecentAddonPeer(target) or iRC.LayerPeers and iRC.LayerPeers:IsReady(target)))
    end
    local response = sentBooks[transferKey(id or "", target or "", parts[4] or "", parts[5] or "") .. ":" .. distribution]
    return response ~= nil and response.expiresAt > now()
        and not response.cancelled
        and not (response.response and response.response.covered)
        and (kind == "LAYER_MISSING" or kind == "LAYER_BOOK" and response.hash == parts[8])
end

function Sync:OnPacketSent(kind, message, distribution, target)
    if kind ~= "LAYER_BOOK" then return end
    local parts = fields(message)
    local outgoing = sentBooks[transferKey(parts[3], target or "", parts[4], parts[5]) .. ":" .. distribution]
    if not outgoing or outgoing.hash ~= parts[8] then return end
    outgoing.startedAt = outgoing.startedAt or now()
    outgoing.sentParts[tonumber(parts[6])] = true
    local count = 0
    for _ in pairs(outgoing.sentParts) do count = count + 1 end
    outgoing.complete = count == outgoing.total
    if outgoing.complete and distribution ~= "WHISPER" then
        local currentIdentity = fingerprint(iRC.LayerRegistry:Export(outgoing.serverId, outgoing.mapId))
        if currentIdentity == outgoing.identity then
            for _, response in pairs(replies) do
                if response.serverId == outgoing.serverId and response.mapId == outgoing.mapId
                    and response.distribution == distribution and response.createdAt <= outgoing.startedAt
                    and iRC.LayerRegistry:GetNumber(response.identityKey, outgoing.serverId, outgoing.mapId) then
                    response.covered = true
                end
            end
        end
    end
end

function Sync:Request(layer)
    if type(layer) ~= "table" or not iRC.LayerRegistry then return false end
    local serverId, mapId = integer(layer.serverId, 0, 2147483647), integer(layer.mapId, 1, 2147483647)
    local identityKey = iRC.LayerRegistry:MakeKey(layer.serverId, layer.instanceId, layer.mapId)
    if not serverId or not mapId or not identityKey then return false end
    clean()
    local id = nonce(false)
    local request = { serverId = serverId, mapId = mapId, identityKey = identityKey, peers = {}, peerNames = {}, responders = {},
        serverRuleset = iRC.GetGuildDirectoryScope and iRC:GetGuildDirectoryScope(), startedAt = now(), expiresAt = now() + LIFETIME }
    requests[id] = request
    local payload = table.concat({ "LAYER_QUERY", VERSION, id, serverId, mapId, identityKey }, "\t")
    request.payload = payload
    local sent = false
    for _, distribution in ipairs(channels()) do
        if distribution == "CHANNEL" then request.channelAsked = true end
        if send(payload, distribution) then sent = true end
    end
    if iRC.LayerPeers then
        for _, peer in ipairs(iRC.LayerPeers:GetCandidates(mapId, 3)) do
            local peerName = peer.name
            request.peers[key(peerName)] = true
            request.peerNames[key(peerName)] = peerName
            iRC.LayerPeers:Preflight(peerName, peer.guid, function(ready)
                if ready and requests[id] == request and request.expiresAt > now() then send(payload, "WHISPER", peerName) end
            end)
        end
    end
    iRC:DebugMsg("Estimated layer lookup started for " .. identityKey .. ".", 3)
    return sent or next(request.peers) ~= nil
end

function Sync:OnChannelReady()
    if not self:GetChannelTarget() then return end
    -- Login restores the channel after early NPC observations. Send the
    -- outstanding question once when it joins, without starting a poll.
    local latest
    for _, request in pairs(requests) do
        if not request.channelAsked and request.serverRuleset == iRC:GetGuildDirectoryScope()
            and now() - request.startedAt <= 30 and request.expiresAt > now()
            and (not iRC.GuildMap or not iRC.GuildMap.IsLayerLookupCurrent or iRC.GuildMap:IsLayerLookupCurrent(request))
            and (not latest or request.startedAt > latest.startedAt) then latest = request end
    end
    if latest then
        latest.channelAsked = true
        send(latest.payload, "CHANNEL")
    end
end

function Sync:Publish(layer)
    if type(layer) ~= "table" or not iRC.LayerRegistry then return false end
    clean()
    local id, latest, sent = nil, -1, false
    for requestId, request in pairs(requests) do
        if request.serverId == layer.serverId and request.mapId == layer.mapId
            and request.identityKey == iRC.LayerRegistry:MakeKey(layer.serverId, layer.instanceId, layer.mapId)
            and request.startedAt >= latest then id, latest = requestId, request.startedAt end
    end
    id = id or nonce(true)
    for _, distribution in ipairs(channels()) do
        if sendBook(id, layer.serverId, layer.mapId, distribution) then sent = true end
    end
    -- A friend who answered "missing" also receives the newly created row.
    -- Only responders in this still-active lookup may get a private update.
    for requestId, request in pairs(requests) do
        if request.serverId == layer.serverId and request.mapId == layer.mapId
            and request.identityKey == iRC.LayerRegistry:MakeKey(layer.serverId, layer.instanceId, layer.mapId) then
            for peerKey in pairs(request.responders) do
                if sendBook(requestId, layer.serverId, layer.mapId, "WHISPER", request.peerNames[peerKey]) then sent = true end
            end
        end
    end
    return sent
end

answer = function(context)
    if replies[context.key] ~= context or context.expiresAt <= now() or context.covered then return end
    if context.serverRuleset and context.serverRuleset ~= iRC:GetGuildDirectoryScope() then return end
    if context.receivingUntil and context.receivingUntil > now() then
        if C_Timer and C_Timer.After then C_Timer.After(context.receivingUntil - now(), function() answer(context) end) end
        return
    end
    if not iRC.LayerRegistry:GetNumber(context.identityKey, context.serverId, context.mapId) then
        if context.distribution == "WHISPER" then
            local contextKey = transferKey(context.id, context.sender, context.serverId, context.mapId) .. ":WHISPER"
            sentBooks[contextKey] = { expiresAt = now() + LIFETIME }
            send(table.concat({ "LAYER_MISSING", VERSION, context.id, context.serverId, context.mapId, context.identityKey }, "\t"), "WHISPER", context.sender)
        end
        return
    end
    sendBook(context.id, context.serverId, context.mapId, context.distribution,
        context.distribution == "WHISPER" and context.sender or nil, context)
end

local function scheduleAnswer(context)
    local delay = context.distribution == "WHISPER" and 0
        or (0.15 + (tonumber(checksum(key(iRC:GetPlayerName())), 16) % 900) / 1000)
    if C_Timer and C_Timer.After then C_Timer.After(delay, function() answer(context) end) else answer(context) end
end

function Sync:Receive(message, distribution, sender, channelTarget)
    if iRC:HasSecretValues(message, distribution, sender) or type(message) ~= "string" or not iRC.LayerRegistry then return false end
    if distribution == "CHANNEL" then
        if not self:IsChannelTarget(channelTarget) or not iRC:IsGuildDirectoryPacketCurrent(message) then return false end
        message = message:gsub("\t@[%w%-]+$", "")
    end
    local parts = fields(message)
    if parts[2] ~= VERSION or not self:IsMessage(parts[1]) then return false end
    local id = parts[3]
    local serverId, mapId = integer(parts[4], 0, 2147483647), integer(parts[5], 1, 2147483647)
    if not id or not id:match("^[qu]%x+$") or #id > 24 or not serverId or not mapId then return false end
    clean()
    if parts[1] == "LAYER_QUERY" then
        local identityKey = parts[6]
        if not iRC.LayerRegistry:IsKey(identityKey, serverId, mapId) or id:sub(1, 1) ~= "q" then return false end
        local contextKey = transferKey(id, sender, serverId, mapId)
        if replies[contextKey] then return true end
        if iRC.GuildMap and iRC.GuildMap.RefreshLocalLayerEvidence
            and iRC.IsCombatTrafficBlocked and not iRC:IsCombatTrafficBlocked()
            and (not lastVerificationAt or now() - lastVerificationAt >= 15) then
            lastVerificationAt = now()
            iRC.GuildMap:RefreshLocalLayerEvidence()
        end
        local context = { key = contextKey, id = id, sender = sender, distribution = distribution,
            serverRuleset = distribution == "CHANNEL" and iRC:GetGuildDirectoryScope() or nil,
            serverId = serverId, mapId = mapId, identityKey = identityKey, createdAt = now(), expiresAt = now() + LIFETIME }
        replies[contextKey] = context
        scheduleAnswer(context)
        return true
    end
    local request = requests[id]
    if distribution == "WHISPER" and not self:IsExpectedReply(message, sender) then return false end
    if parts[1] == "LAYER_MISSING" then
        if not request or parts[6] ~= request.identityKey then return false end
        if distribution == "WHISPER" then
            request.responders[key(sender)] = true
            if iRC.LayerRegistry:GetNumber(request.identityKey, serverId, mapId) then sendBook(id, serverId, mapId, "WHISPER", sender) end
        end
        return true
    end
    local part, total = integer(parts[6], 1, MAX_PARTS), integer(parts[7], 1, MAX_PARTS)
    local hash, chunk = parts[8], parts[9]
    if not part or not total or part > total or not hash or not hash:match("^%x+$") or #hash > 8
        or not chunk or #chunk > CHUNK_SIZE or #parts ~= 9 then return false end
    local contextKey = transferKey(id, sender, serverId, mapId) .. ":" .. hash
    local transfer = transfers[contextKey]
    if not transfer then
        transfer = { parts = {}, total = total, hash = hash, received = 0, expiresAt = now() + LIFETIME }
        transfers[contextKey] = transfer
    end
    if transfer.total ~= total or transfer.hash ~= hash then transfers[contextKey] = nil; return false end
    for _, response in pairs(replies) do
        if response.serverId == serverId and response.mapId == mapId
            and (distribution ~= "WHISPER" and response.distribution == distribution
                or distribution == "WHISPER" and response.distribution == "WHISPER" and response.id == id and key(response.sender) == key(sender)) then
            response.receivingUntil = now() + 2
        end
    end
    if distribution ~= "WHISPER" and responderRank(sender) < responderRank(iRC:GetPlayerName()) then
        for _, outgoing in pairs(sentBooks) do
            if outgoing.response and outgoing.serverId == serverId and outgoing.mapId == mapId
                and outgoing.distribution == distribution and not outgoing.complete and not outgoing.cancelled then
                outgoing.cancelled = true
                local response = outgoing.response
                if (response.restarts or 0) < 2 and not response.recoveryQueued and C_Timer and C_Timer.After then
                    response.restarts = (response.restarts or 0) + 1
                    response.recoveryQueued = true
                    -- Yield while another snapshot is progressing, but do
                    -- not leave the request unanswered if that sender stops.
                    -- This retries the same reply at most twice, never a new
                    -- lookup or a fresh set of whisper recipients.
                    local delay = 2.15 + (tonumber(checksum(key(iRC:GetPlayerName())), 16) % 900) / 1000
                    C_Timer.After(delay, function()
                        response.recoveryQueued = nil
                        answer(response)
                    end)
                end
            end
        end
    end
    if transfer.parts[part] then return transfer.parts[part] == chunk end
    transfer.parts[part], transfer.received = chunk, transfer.received + 1
    if transfer.received ~= total then return true end
    local wire = table.concat(transfer.parts)
    transfers[contextKey] = nil
    if checksum(wire) ~= hash then return false end
    local rows = decode(wire)
    if not rows or #rows == 0 or not iRC.LayerRegistry:ValidateRows(rows, mapId) then return false end
    if request and distribution == "WHISPER" then request.responders[key(sender)] = true end
    local previousIdentity = fingerprint(iRC.LayerRegistry:Export(serverId, mapId))
    iRC.LayerRegistry:Merge(serverId, mapId, rows)
    notify(serverId, mapId, rows)
    local receivedIdentity = fingerprint(rows)
    local mergedHash = fingerprint(iRC.LayerRegistry:Export(serverId, mapId))
    local claimsChanged = previousIdentity ~= mergedHash
    local exchange = request ~= nil
    for _, response in pairs(replies) do
        if response.serverId == serverId and response.mapId == mapId
            and (distribution ~= "WHISPER" and response.distribution == distribution
                or distribution == "WHISPER" and response.distribution == "WHISPER" and response.id == id and key(response.sender) == key(sender)) then
            response.receivingUntil = nil
            response.covered = mergedHash == receivedIdentity and iRC.LayerRegistry:GetNumber(response.identityKey, serverId, mapId) ~= nil
            exchange = true
        end
    end
    -- Return any claims the answering client was missing. This is part of the
    -- same bounded lookup, not a periodic gossip loop.
    if mergedHash ~= receivedIdentity and (exchange or distribution ~= "WHISPER") then
        local updateKey = id .. ":" .. serverId .. ":" .. mapId .. ":" .. distribution
            .. (distribution == "WHISPER" and ":" .. key(sender) or "")
        local update = reconciliations[updateKey] or { count = 0, expiresAt = now() + LIFETIME }
        reconciliations[updateKey] = update
        if update.count < 2 and update.hash ~= mergedHash then
            update.count, update.hash = update.count + 1, mergedHash
            if distribution == "WHISPER" then
                sendBook(id, serverId, mapId, distribution, sender)
            else
                -- Returning a missing claim is a shared reply too. Apply the
                -- same suppression as a query response so every guild member
                -- does not broadcast the identical correction at once.
                local responseKey = "merge:" .. id .. ":" .. serverId .. ":" .. mapId .. ":" .. distribution
                local response = { key = responseKey, id = id, sender = sender, distribution = distribution,
                    serverRuleset = distribution == "CHANNEL" and iRC:GetGuildDirectoryScope() or nil,
                    serverId = serverId, mapId = mapId, identityKey = rows[1].identityKey, createdAt = now(), expiresAt = now() + LIFETIME }
                replies[responseKey] = response
                scheduleAnswer(response)
            end
        end
    end
    -- A friend or another group can bring a new claim into this guild. Carry
    -- that same update across the existing broadcast audiences once, without
    -- starting another query or whispering the membership roster.
    if claimsChanged then
        for _, audience in ipairs(channels()) do
            if audience ~= distribution then
                local relayKey = serverId .. ":" .. mapId .. ":" .. mergedHash .. ":" .. audience
                if not relays[relayKey] then
                    relays[relayKey] = { expiresAt = now() + LIFETIME }
                    sendBook(id, serverId, mapId, audience)
                end
            end
        end
        for _, response in pairs(replies) do
            if response.distribution == "WHISPER" and response.serverId == serverId and response.mapId == mapId
                and response.expiresAt > now() and (distribution ~= "WHISPER" or key(response.sender) ~= key(sender))
                and not response.updateQueued then
                response.covered, response.updateQueued = false, true
                local function update()
                    response.updateQueued = nil
                    answer(response)
                end
                if C_Timer and C_Timer.After then C_Timer.After(0.2, update) else update() end
            end
        end
        -- Several friends may answer the same lookup with different pieces
        -- of the book. Return the union to earlier responders too, using only
        -- the original request and only friends who actually answered it.
        for requestId, active in pairs(requests) do
            if active.serverId == serverId and active.mapId == mapId and active.expiresAt > now() then
                active.updateQueued = active.updateQueued or {}
                for peerKey in pairs(active.responders) do
                    if peerKey ~= key(sender) and not active.updateQueued[peerKey] then
                        active.updateQueued[peerKey] = true
                        local function updateFriend()
                            active.updateQueued[peerKey] = nil
                            if requests[requestId] == active and active.expiresAt > now() then
                                sendBook(requestId, serverId, mapId, "WHISPER", active.peerNames[peerKey])
                            end
                        end
                        if C_Timer and C_Timer.After then C_Timer.After(0.2, updateFriend) else updateFriend() end
                    end
                end
            end
        end
    end
    iRC:DebugMsg("Estimated layer registry received from " .. tostring(sender)
        .. (distribution == "CHANNEL" and " via iRCCommsV1 [" .. tostring(iRC:GetGuildDirectoryScope()) .. "]" or "")
        .. ": " .. #rows .. " world references for map " .. mapId .. ".", 3)
    return true
end
