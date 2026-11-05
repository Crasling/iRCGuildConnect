-- Exercise channel changes against the real layer sender. A display index
-- belonging to General must never become a source of addon-whisper targets.
local now, sent, frames, rosterReads = 1000, {}, {}, {}
local guildKey, guildRoster = nil, { { name = "Guild Mate" } }
local secret, metadataMode, channelId = {}, nil, 6
local channels = {
    [1] = { name = "General", members = { "Unrelated Player" } },
    [2] = { name = "iRCCommsV1", members = { "Self Name", "Peer One", "PEER-ONE", "Peer Two" } },
}
local env, addon, private = {}, {}, {}
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
function addon:AcceptIncomingAddonTraffic() return true end
function addon:DebugMsg() end
function addon:Text(key) return key end
function addon:SendAddonTraffic(prefix, message, distribution, target)
    assert(prefix == "iRCLayerV1" and (distribution == "WHISPER" or distribution == "GUILD"), "the layer prefix is preserved")
    sent[#sent + 1] = { target = target, distribution = distribution, message = message }
    return true
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
    assert(result == (#expected > 0), "send availability follows the verified iRC roster")
    assert(#sent == #expected, "send to every unique current peer, excluding ourselves")
    for index, name in ipairs(expected) do assert(sent[index].target == name, "the intended iRC peer receives the packet") end
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
-- every listed character. Only lookup bootstrap may use a bounded sample.
env.C_Timer = nil
channels[4].members = { "Self Name", "Guild Mate" }
for index = 1, 498 do channels[4].members[#channels[4].members + 1] = "Peer " .. index end
frame.OnEvent(frame, "CHANNEL_ROSTER_UPDATE", 4, 500)
guildKey = "test guild"
sent = {}
assert(grid:BroadcastLayerState(layer))
assert(#sent == 1 and sent[1].distribution == "GUILD", "one guild packet replaces a 500-member whisper fan-out")
assert(sent[1].message:match("^LAYER_STATE\t6\t"), "raw layer state keeps its existing format")
sent = {}
assert(grid:BroadcastLayerTransition(1415))
assert(#sent == 1 and sent[1].distribution == "GUILD", "transitions do not probe unknown channel members")

layer.zoneUID, layer.layerSwapId = 987, "4621-987"
sent = {}
assert(grid:RequestLayerAssignment(layer) and #sent == 3, "a new layer lookup asks at most three of 500 members")
for _, packet in ipairs(sent) do assert(packet.distribution == "WHISPER" and packet.message:match("^LAYER_REQUEST\t6\t")) end
assert(not grid:RequestLayerAssignment(layer) and #sent == 3, "repeated same-route calls cannot start a whisper loop")

local receivedStates, receivedTransitions = {}, {}
addon.GuildMap = {
    ReceiveLayerState = function(_, parts, sender) receivedStates[#receivedStates + 1] = sender; return true end,
    ReceiveLayerTransition = function(_, parts, sender) receivedTransitions[#receivedTransitions + 1] = sender; return true end,
    ReceiveLayerAssignment = function() return true end,
    GetAssignedLayerNumber = function() return 4 end,
}
local function receive(kind, sender, distribution, mapId)
    local payload = table.concat({ kind, "6", "123", "4621", "0", tostring(mapId or 1415), "4", "", "4621-123" }, "\t")
    frame.OnEvent(frame, "CHAT_MSG_ADDON", "iRCLayerV1", payload, distribution or "WHISPER", sender)
end
receive("LAYER_STATE", "Guild Mate", "GUILD")
assert(receivedStates[#receivedStates] == "Guild Mate", "guild raw identities arrive without needing public-channel discovery")
local statesBefore = #receivedStates
receive("LAYER_STATE", "Peer 1", "GUILD")
assert(#receivedStates == statesBefore, "a guild-distribution layer packet still requires actual guild membership")
for index = 1, 5 do receive("LAYER_STATE", "Peer " .. index) end
receive("LAYER_STATE", "Peer 6", "WHISPER", 9999)
local unavailable = "peer 1"
function addon:IsAddonWhisperTargetUnavailable(name) return self:NormalizeName(name) == unavailable end
sent = {}
assert(grid:BroadcastLayerState(layer))
assert(#sent == 4 and sent[1].distribution == "GUILD", "state reaches the guild and at most three confirmed same-zone peers")
for index = 2, #sent do
    assert(sent[index].target ~= "Guild Mate" and sent[index].target ~= "Peer 1" and sent[index].target ~= "Peer 6",
        "guild, offline-paused, and other-zone recipients do not add background whispers")
end

local reply = table.concat({ "LAYER_REQUEST", "6", "123", "4621", "0", "1415", "4621-123" }, "\t")
sent = {}
frame.OnEvent(frame, "CHAT_MSG_ADDON", "iRCLayerV1", reply, "WHISPER", "Peer 2")
frame.OnEvent(frame, "CHAT_MSG_ADDON", "iRCLayerV1", reply, "WHISPER", "Peer 2")
assert(#sent == 1 and sent[1].message:match("^LAYER_ASSIGN\t6\t"), "old clients receive a valid assignment reply with duplicate-response pacing")

-- Guild layer delivery works even while the hidden channel is unavailable.
channelId = 0
env.JoinChannelByName = nil
sent = {}
assert(grid:IsLayerChannelReady() and grid:BroadcastLayerState(layer))
assert(#sent == 1 and sent[1].distribution == "GUILD", "guild sharing does not wait for the public channel")
guildKey = nil
assert(not grid:IsLayerChannelReady())

print("PASS: verified channel indexes, bounded 500-member discovery, guild raw layer state, trusted same-zone peers, old replies, and offline guards")
