-- Run from the addon directory. All unit data, clocks, and transports are mocked.
local root = ""
local now, combat, lockdown, identitySecret = 100, false, false, false
local guidReads, requests, broadcasts, transitions = 0, {}, {}, 0
local guids, timers, frames = {}, {}, {}
local ready = true
local secretValue = {}
local settings = { showLayerPanel = true }
local addon = { LayerWireVersion = "6", Prefix = "iRCConnV1" }

function issecretvalue(value) return value == secretValue end
function GetTime() return now end
function time() return 1800000000 + now end
function UnitAffectingCombat()
    if combat == "error" then error("combat state unavailable") end
    if combat == "secret" then return secretValue end
    return combat
end
function InCombatLockdown() return lockdown end
function strsplit(separator, value)
    local fields = {}
    for field in value:gmatch("[^" .. separator .. "]+") do fields[#fields + 1] = field end
    return table.unpack(fields)
end
function UnitPlayerControlled() return false end
function UnitGUID(unit)
    guidReads = guidReads + 1
    return guids[unit]
end
C_Secrets = { ShouldUnitIdentityBeSecret = function() return identitySecret end }
C_Map = {
    GetBestMapForUnit = function() return 1415 end,
    GetMapInfo = function() return { mapType = 3 } end,
}
function CreateFrame()
    local frame = { scripts = {} }
    function frame:RegisterEvent() end
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    frames[#frames + 1] = frame
    return frame
end
C_Timer = { After = function(delay, callback)
    timers[#timers + 1] = { at = now + delay, callback = callback }
end }
function GetBuildInfo() return "1.60.1", "70374", "", 16001 end
function LibStub(name)
    if name == "AceAddon-3.0" then return { NewAddon = function() return addon end } end
end
local private = {}
assert(loadfile(root .. "iRC_Core.lua"))("iRC", private)

function addon:GetSettings() return settings end
function addon:IsForeverClient() return true end
function addon:IsSecretValue(value) return issecretvalue(value) end
function addon:NormalizeName(name) return (name or ""):lower() end
function addon:GetGuildKey() return "test guild" end
function addon:DebugMsg() end
addon.RaceGrid = {
    IsLayerChannelReady = function() return ready end,
    RequestLayerAssignment = function(_, candidate)
        requests[#requests + 1] = candidate.layerSwapId
        return true
    end,
    BroadcastLayerState = function(_, layer)
        broadcasts[#broadcasts + 1] = layer.layerSwapId
        return true
    end,
    BroadcastLayerTransition = function()
        transitions = transitions + 1
        return true
    end,
}

assert(loadfile(root .. "iRC_GuildMap.lua"))("iRC", { iRC = addon })
local map, events = addon.GuildMap, frames[#frames]

local function advance(seconds)
    local target = now + seconds
    while true do
        local first
        for index, timer in ipairs(timers) do
            if timer.at <= target and (not first or timer.at < timers[first].at) then first = index end
        end
        if not first then break end
        local timer = table.remove(timers, first)
        now = timer.at
        timer.callback()
    end
    now = target
end
local function observe(route, npc)
    guids.target = "Creature-0-4621-1-" .. route .. "-100-" .. npc
    return map:ObserveLocalLayer("target", "target")
end
local function evidence(route)
    assert(not observe(route, 1), "one NPC must not confirm a layer")
    assert(not observe(route, 2), "two NPCs must not confirm a layer")
    assert(observe(route, 3), "three public NPCs must start layer assignment outside combat")
end

evidence(111)
assert(#requests == 1 and requests[1] == "4621-111", "confirmed evidence requests a layer assignment")
assert(not map:GetLocalLayer(), "wait for the assignment lookup before showing a layer")
advance(2)
local layer = assert(map:GetLocalLayer(), "finish assigning the detected layer outside combat")
assert(layer.zoneUID == 111 and layer.number == 1, "the detected raw route receives a display number")
assert(layer.provisional == true, "an unanswered bounded lookup remains a local estimate")
assert(#broadcasts == 1, "the detected layer is shared")
assert(map:BroadcastLocalLayer(true), "layer sharing is allowed outside combat")

local function assertBlocked(value, locked)
    combat, lockdown = value, locked or false
    local readsBefore, sendsBefore = guidReads, #broadcasts
    assert(not observe(222, 1), "combat or unknown combat state must block observation")
    assert(guidReads == readsBefore, "blocked scans must not read unit GUIDs")
    assert(not map:BroadcastLocalLayer(true), "blocked state must not share a layer")
    assert(#broadcasts == sendsBefore, "blocked state must not reach the layer transport")
end
assertBlocked(true)
assertBlocked(false, true)
assertBlocked("secret")
assertBlocked("error")
combat, lockdown = false, false
local combatHelper = addon.IsCombatTrafficBlocked
addon.IsCombatTrafficBlocked = nil
local readsBefore = guidReads
assert(not observe(222, 1) and guidReads == readsBefore, "a missing combat helper blocks safely")
addon.IsCombatTrafficBlocked = combatHelper

map:ClearLocalLayer()
evidence(222)
combat = true
advance(2)
assert(not map:GetLocalLayer(), "an assignment that reaches combat must wait")
combat = false
events.scripts.OnEvent(events, "PLAYER_REGEN_ENABLED")
assert(map:GetLocalLayer().zoneUID == 222, "pending assignment resumes after combat")

map:ClearLocalLayer()
ready = false
local requestsBefore = #requests
evidence(333)
assert(#requests == requestsBefore and not map:GetLocalLayer(), "wait while the layer channel is unavailable")
ready = true
advance(3)
assert(map:GetLocalLayer().zoneUID == 333, "channel readiness resumes assignment and sharing")

map:ClearLocalLayer()
requestsBefore = #requests
assert(not observe(444, 1) and not observe(444, 1) and not observe(444, 1), "repeated NPCs are one vote")
assert(#requests == requestsBefore, "one repeated NPC cannot trigger assignment")
assert(not observe(444, 2) and observe(444, 3), "two additional unique NPCs complete the evidence")
advance(2)
assert(map:GetLocalLayer().zoneUID == 444, "unique evidence still completes normally")

identitySecret = true
readsBefore = guidReads
assert(not observe(555, 1) and guidReads == readsBefore, "secret unit identity is skipped before UnitGUID")
identitySecret = false
settings.showLayerPanel = false
assert(not observe(555, 1), "the layer setting still disables local observation")
settings.showLayerPanel = true

events.scripts.OnEvent(events, "SHARD_TRANSFER")
assert(transitions == 1 and not map:GetLocalLayer(), "a shard transfer clears the old layer and is shared")
combat = true
events.scripts.OnEvent(events, "SHARD_TRANSFER")
assert(transitions == 1, "a combat-time transfer announcement waits")
combat = false
events.scripts.OnEvent(events, "PLAYER_REGEN_ENABLED")
assert(transitions == 2, "the deferred transfer announcement resumes after combat")

map.UpdatePins = function() end
assert(map:ReceiveLayerState({ "LAYER_STATE", "6", "111", "4621", "0", "1415", "4", "", "4621-111" }, "Guild Peer One"))
assert(map:ReceiveLayerState({ "LAYER_STATE", "6", "111", "4621", "99", "1415", "7", "", "4621-111" }, "Guild Peer Two"))
local firstPeer, secondPeer = assert(map:GetUserLayer("Guild Peer One")), assert(map:GetUserLayer("Guild Peer Two"))
assert(firstPeer.number == secondPeer.number and firstPeer.zoneUID == secondPeer.zoneUID,
    "raw guild identities keep the same layer together despite different reported numbers and NPC instances")

print("PASS: local detection, bounded-lookup fallback, raw guild normalization, sharing, combat/secret guards, channel readiness, unique NPC votes, and transfers")
