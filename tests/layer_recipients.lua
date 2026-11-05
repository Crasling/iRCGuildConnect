-- Exercise channel changes against the real layer sender. A display index
-- belonging to General must never become a source of addon-whisper targets.
local now, sent, frames, rosterReads, recentPeers = 1000, {}, {}, {}, {}
local guildKey, guildRoster = nil, { { name = "Guild Mate" } }
local guildDeliveryAccepted = true
local secret, metadataMode, channelId = {}, nil, 6
local channels = {
    [1] = { name = "General", members = { "Unrelated Player" } },
    [2] = { name = "iRCCommsV1", members = { "Self Name", "Peer One", "PEER-ONE", "Peer Two" } },
}
local env, addon, private = {}, { LayerWireVersion = "8" }, {}
setmetatable(env, { __index = _G })
env._G = env
env.GetTime = function() return now end
env.time = function() return 1800000000 + math.floor(now) end
env.GetChannelName = function() return channelId end
env.GetChannelList = function() return 1, "General", false end
local function channelInfo(index)
    if metadataMode == "error" then error("channel metadata unavailable") end
    if metadataMode == "secret" then return secret end
    if metadataMode == "missing" then return nil end
    return channels[index] and channels[index].name
end
env.GetChannelDisplayInfo = channelInfo
env.C_ChatInfo = { GetChannelRosterInfo = function(displayIndex, rosterIndex)
    local channel = assert(channels[displayIndex], "the roster index belongs to a known channel")
    assert(channel.name:lower() == "irccommsv1", "never inspect an unrelated channel's roster")
    rosterReads[#rosterReads + 1] = displayIndex
    return channel.members[rosterIndex]
end }
env.CreateFrame = function()
    local frame = { RegisterEvent = function() end }
    function frame:SetScript(key, callback) self[key] = callback end
    frames[#frames + 1] = frame
    return frame
end
private.iRC = addon
function addon:IsSecretValue(value) return value == secret end
function addon:GetPlayerName() return "Self Name" end
function addon:NormalizeName(name) return tostring(name or ""):lower():gsub("-", " ") end
function addon:GetSettings() return {} end
function addon:IsTestAdmin() return true end
function addon:GetGuildKey() return guildKey end
function addon:GetGuildRosterSnapshot() return guildRoster end
function addon:HasSecretValues(...) for index = 1, select("#", ...) do if select(index, ...) == secret then return true end end return false end
function addon:AcceptIncomingAddonTraffic(_, _, _, sender)
    recentPeers[self:NormalizeName(sender)] = now
    return true
end
function addon:IsRecentAddonPeer(name)
    local seenAt = recentPeers[self:NormalizeName(name)]
    return seenAt ~= nil and now - seenAt <= 30
end
function addon:DebugMsg() end
function addon:Text(key) return key end
function addon:SendAddonTraffic(prefix, message, distribution, target)
    assert(prefix == "iRCLayerV1" and (distribution == "WHISPER" or distribution == "GUILD" or distribution == "PARTY" or distribution == "RAID"), "the layer prefix is preserved")
    sent[#sent + 1] = { target = target, distribution = distribution, message = message }
    return distribution ~= "GUILD" or guildDeliveryAccepted
end
assert(loadfile("iRC_RaceGrid.lua", "t", env))("iRC", private)
local grid, frame = addon.RaceGrid, frames[#frames]
local layer = { zoneUID = 123, serverId = 4621, instanceId = 0, mapId = 1415, number = 1,
    layerSwapId = "4621-123" }
local function broadcast(expected)
    sent = {}
    layer.zoneUID = layer.zoneUID + 1
    layer.layerSwapId = "4621-" .. layer.zoneUID
    local result = grid:RequestLayerAssignment(layer)
    assert(not result and #sent == 0, "roster names alone never trigger discovery whispers")
    for _, name in ipairs(expected) do assert(grid:IsKnownChannelMember(name), "membership still follows the verified iRC roster") end
end

broadcast({ "Peer One", "Peer Two" })
assert(grid:IsKnownChannelMember("Peer One"), "initial channel membership is available")

-- No channel event is needed to catch an index that moved after caching.
channels[2] = { name = "Trade", members = { "Wrong Channel Member" } }
channels[3] = { name = "iRCCommsV1", members = { "Moved Peer" } }
broadcast({ "Moved Peer" })
assert(not grid:IsKnownChannelMember("Peer One") and grid:IsKnownChannelMember("Moved Peer"),
    "index movement replaces cached membership immediately")

-- UI changes and roster events invalidate the five-second membership cache.
channels[3].members = { "UI Updated Peer" }
frame.OnEvent(frame, "CHANNEL_UI_UPDATE")
assert(not grid:IsKnownChannelMember("Moved Peer") and grid:IsKnownChannelMember("UI Updated Peer"))
channels[3].members = { "Roster Updated Peer" }
frame.OnEvent(frame, "CHANNEL_ROSTER_UPDATE", 3, 1)
assert(not grid:IsKnownChannelMember("UI Updated Peer") and grid:IsKnownChannelMember("Roster Updated Peer"))

for _, mode in ipairs({ "secret", "error", "missing" }) do
    local readsBefore = #rosterReads
    metadataMode = mode
    broadcast({})
    assert(not grid:IsKnownChannelMember("Roster Updated Peer"), "unreadable metadata cannot retain stale membership")
    assert(#rosterReads == readsBefore, "unverified channel metadata never reaches the roster API")
end
metadataMode = nil
env.GetChannelDisplayInfo = nil
broadcast({})
assert(not grid:IsKnownChannelMember("Roster Updated Peer"), "a missing metadata API fails closed")
env.GetChannelDisplayInfo = channelInfo

channels[3] = nil
broadcast({})
assert(not grid:IsKnownChannelMember("Roster Updated Peer"), "a departed channel clears membership")
channels[4] = { name = "iRCCommsV1", members = { "Restored Peer" } }
broadcast({ "Restored Peer" })
assert(grid:IsKnownChannelMember("Restored Peer"), "discovery recovers when iRCComms returns at another index")

-- A rejoin can happen before CHANNEL_UI_UPDATE arrives. Cached recipients
-- must still be discarded before the channel is joined again.
env.C_Timer = { After = function(_, callback) callback() end }
grid.BroadcastReport = function() return false end
grid:ScheduleChannelJoin(0)
local joined = 0
env.JoinChannelByName = function(name)
    assert(name == "iRCCommsV1")
    joined, channelId = joined + 1, 6
end
channelId = 0
channels[4].members = { "Rejoined Peer" }
assert(not grid:IsKnownChannelMember("Restored Peer"), "a disconnected channel cannot authenticate cached peers")
grid:EnsureChannel()
assert(joined == 1 and grid:IsKnownChannelMember("Rejoined Peer"), "rejoining discovers the current channel roster")
broadcast({ "Rejoined Peer" })

-- A large channel must not turn routine state updates into a whisper to
-- every listed character. Unknown names must not receive bootstrap probes.
env.C_Timer = nil
channels[4].members = { "Self Name", "Guild Mate" }
for index = 1, 498 do channels[4].members[#channels[4].members + 1] = "Peer " .. index end
frame.OnEvent(frame, "CHANNEL_ROSTER_UPDATE", 4, 500)
guildKey = "test guild"
sent = {}
assert(grid:BroadcastLayerState(layer))
assert(#sent == 1 and sent[1].distribution == "GUILD", "one guild packet replaces a 500-member whisper fan-out")
assert(sent[1].message:match("^LAYER_STATE\t8\t"), "the new estimated layer protocol is versioned separately")
sent = {}
assert(grid:BroadcastLayerTransition(1415))
assert(#sent == 1 and sent[1].distribution == "GUILD", "transitions do not probe unknown channel members")

layer.zoneUID, layer.layerSwapId = 987, "4621-987"
sent = {}
assert(not grid:RequestLayerAssignment(layer) and #sent == 0, "none of 500 unknown channel members receives a layer probe")
assert(not grid:RequestLayerAssignment(layer) and #sent == 0, "repeated unknown lookups remain silent")

local receivedStates, receivedTransitions = {}, {}
addon.GuildMap = {
    ReceiveLayerState = function(_, parts, sender) receivedStates[#receivedStates + 1] = sender; return true end,
    ReceiveLayerTransition = function(_, parts, sender) receivedTransitions[#receivedTransitions + 1] = sender; return true end,
    ReceiveLayerAssignment = function() return true end,
    GetAssignedLayerNumber = function() return 4 end,
}
local function receive(kind, sender, distribution, mapId)
    local payload = table.concat({ kind, "8", "123", "4621", "0", tostring(mapId or 1415), "4", "", "4621-123" }, "\t")
    frame.OnEvent(frame, "CHAT_MSG_ADDON", "iRCLayerV1", payload, distribution or "WHISPER", sender)
end
receive("LAYER_STATE", "Guild Mate", "GUILD")
assert(receivedStates[#receivedStates] == "Guild Mate", "guild raw identities arrive without needing public-channel discovery")
local statesBefore = #receivedStates
receive("LAYER_STATE", "Peer 1", "GUILD")
assert(#receivedStates == statesBefore, "a guild-distribution layer packet still requires actual guild membership")
for index = 1, 498 do receive("LAYER_STATE", "Peer " .. index) end
receive("LAYER_STATE", "Peer 6", "WHISPER", 9999)
local unavailable = "peer 1"
function addon:IsAddonWhisperTargetUnavailable(name) return self:NormalizeName(name) == unavailable end
sent = {}
assert(grid:BroadcastLayerState(layer))
assert(#sent == 1 and sent[1].distribution == "GUILD", "even confirmed peers in a 500-member channel receive no routine state whispers")
sent = {}
assert(grid:BroadcastLayerTransition(1415) and #sent == 1 and sent[1].distribution == "GUILD",
    "even fresh same-zone peers receive no transition whispers")
guildDeliveryAccepted = false
sent = {}
assert(not grid:BroadcastLayerState(layer) and #sent == 1 and sent[1].distribution == "GUILD",
    "a rejected guild state send cannot fall back to peer whispers")
sent = {}
assert(not grid:BroadcastLayerTransition(1415) and #sent == 1 and sent[1].distribution == "GUILD",
    "a rejected guild transition send cannot fall back to peer whispers")
guildDeliveryAccepted = true
local lookups, registryMessages = 0, 0
addon.LayerSync = {
    Request = function(_, candidate) assert(candidate.zoneUID == layer.zoneUID); lookups = lookups + 1; return true end,
    Publish = function() return false end,
    IsExpectedReply = function() return false end,
    IsMessage = function(_, kind) return kind == "LAYER_QUERY" or kind == "LAYER_BOOK" or kind == "LAYER_MISSING" end,
    Receive = function() registryMessages = registryMessages + 1; return true end,
}
sent = {}
assert(grid:RequestLayerAssignment(layer) and lookups == 1 and #sent == 0,
    "the layer sender delegates one verification to the registry protocol without sampling channel names")
local query = table.concat({ "LAYER_QUERY", "8", "qabc", "4621", "1415", "4621-0-1415" }, "\t")
frame.OnEvent(frame, "CHAT_MSG_ADDON", "iRCLayerV1", query, "GUILD", "Guild Mate")
assert(registryMessages == 1, "trusted registry queries reach the dedicated protocol")
frame.OnEvent(frame, "CHAT_MSG_ADDON", "iRCLayerV1", query, "GUILD", "Peer 2")
assert(registryMessages == 1, "another channel member cannot impersonate guild transport")
frame.OnEvent(frame, "CHAT_MSG_ADDON", "iRCLayerV1", "LAYER_REQUEST\t6\t123\t4621\t0\t1415\t4621-123", "WHISPER", "Peer 2")
assert(#sent == 0, "old numeric-vote requests never restart direct whisper responses")

local groupDistribution
function addon.GuildMap:GetLayerGroupDistribution() return groupDistribution end
function addon.GuildMap:IsLayerGroupMember(name) return name == "Group Peer" end
groupDistribution = "PARTY"
sent = {}
assert(grid:BroadcastLayerState(layer) and #sent == 2 and sent[1].distribution == "GUILD" and sent[2].distribution == "PARTY",
    "group state uses shared transport without member-by-member whispers")
receive("LAYER_STATE", "Group Peer", "PARTY")
assert(receivedStates[#receivedStates] == "Group Peer", "a cross-guild group member's raw state is trusted")
local groupStates = #receivedStates
receive("LAYER_STATE", "Peer 2", "PARTY")
assert(#receivedStates == groupStates, "channel membership alone cannot impersonate a group sender")
groupDistribution = "RAID"
sent = {}
assert(grid:BroadcastLayerTransition(1415) and #sent == 2 and sent[2].distribution == "RAID", "raid transitions use shared transport")
groupDistribution = nil
addon.LayerSync = nil

-- Guild layer delivery works even while the hidden channel is unavailable.
channelId = 0
env.JoinChannelByName = nil
sent = {}
assert(grid:IsLayerChannelReady() and grid:BroadcastLayerState(layer))
assert(#sent == 1 and sent[1].distribution == "GUILD", "guild sharing does not wait for the public channel")
guildKey = nil
assert(not grid:IsLayerChannelReady())
channelId = 6
sent = {}
assert(not grid:BroadcastLayerState(layer) and not grid:BroadcastLayerTransition(1415) and #sent == 0,
    "having peers but no guild never turns routine layer sharing into whispers")

print("PASS: shared guild/group transports, no whisper fanout, validated channel metadata, registry delegation, and sender trust")
