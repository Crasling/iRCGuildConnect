-- Exercise real outgoing queues against WoW's numeric send-result codes.
local function client(results)
    local env, addon, private = {}, {}, {}
    local now, timers, attempts, delivered, traces = 100, {}, {}, {}, {}
    local locked, guild, nextResult = false, "test guild", 1
    local secret = {}
    setmetatable(env, { __index = _G })
    env._G, env.iRCDB, env.iRCCharDB = env, {}, {}
    env.GetTime = function() return now end
    env.GetBuildInfo = function() return "1.60.1", "70374", "", 16001 end
    env.issecretvalue = function(value) return value == secret end
    env.CreateFrame = function()
        return { RegisterEvent = function() end, SetScript = function(self, key, callback) self[key] = callback end }
    end
    env.ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
    env.LibStub = function(name)
        if name == "AceAddon-3.0" then return { NewAddon = function() return addon end } end
    end
    env.C_Timer = { After = function(delay, run) timers[#timers + 1] = { at = now + delay, run = run } end }
    env.Enum = { SendAddonMessageResult = {
        Success = 0, InvalidPrefix = 1, AddonMessageThrottle = 3,
        ChannelThrottle = 8, AddOnMessageLockdown = 11, TargetOffline = 12,
    } }
    env.C_ChatInfo = {
        InChatMessagingLockdown = function() return locked end,
        SendAddonMessage = function(prefix, message, distribution, target)
            local result = results[nextResult]
            nextResult = nextResult + 1
            if result == nil then result = 0 end
            attempts[#attempts + 1] = { prefix = prefix, message = message, distribution = distribution,
                target = target, at = now, result = result }
            if result == "error" then error("mock send failure") end
            if result == "secret" then return secret end
            if result == 0 or result == true then delivered[#delivered + 1] = message end
            return result
        end,
    }
    assert(loadfile("iRC_Core.lua", "t", env))("iRC", private)
    function addon:GetGuildKey() return guild end
    function addon:DebugMsg() end
    addon.Diagnostics = { Trace = function(_, ...) traces[#traces + 1] = { ... } end }
    local state = { addon = addon, env = env, secret = secret, attempts = attempts, delivered = delivered, traces = traces }
    function state:advance(seconds)
        local finish = now + seconds
        while true do
            table.sort(timers, function(a, b) return a.at < b.at end)
            if not timers[1] or timers[1].at > finish then break end
            local timer = table.remove(timers, 1)
            now = timer.at
            timer.run()
        end
        now = finish
    end
    function state:send(message) return addon:SendAddonTraffic(addon.Prefix, message, "GUILD") end
    function state:whisper(message, target, prefix) return addon:SendAddonTraffic(prefix or addon.Prefix, message, "WHISPER", target) end
    function state:event(event, ...) addon.Frame.OnEvent(addon.Frame, event, ...) end
    function state:lock(value) locked = value end
    function state:changeGuild() guild = "another guild" end
    function state:queued() return addon:GetPerformanceQueueStatus().outgoing end
    return state
end

local position = "MAP_POS\t1\t1415\t2500\t7500"
local newerPosition = "MAP_POS\t1\t1415\t3500\t7500"
for _, code in ipairs({ 3, 8, 11 }) do
    local state = client({ code, 0 })
    state:send(position)
    state:advance(2)
    assert(#state.delivered == 1 and #state.attempts == 2,
        "temporary send failure " .. code .. " must retry rather than count as delivery")
    assert(state:queued() == 0, "a successful retry releases its queue entry")
    assert(state.attempts[2].at - state.attempts[1].at >= 0.5, "retries stay paced")
end

for _, result in ipairs({ 0, true }) do
    local state = client({ result })
    assert(state:send(position) == true, "successful API results have one boolean transport contract")
    state:advance(2)
    assert(#state.delivered == 1 and #state.attempts == 1, "successful sends are never repeated")
end

for _, result in ipairs({ 1, false, "secret", "error" }) do
    local state = client({ result })
    assert(state:send(position) == false, "permanent or unreadable failures are not successful sends")
    state:advance(2)
    assert(#state.delivered == 0 and #state.attempts == 1 and state:queued() == 0)
end

local state = client({ 3, 0 })
state:lock(true)
assert(state:send(position))
state:advance(1)
assert(#state.attempts == 0, "the API is not called during known chat lockdown")
state:lock(false)
state:advance(0.5)
assert(state:queued() == 1 and #state.delivered == 0, "a queued temporary failure retains the packet")
assert(state:send(newerPosition))
state:advance(2)
assert(#state.delivered == 1 and state.delivered[1] == newerPosition,
    "a pending map retry uses the newest coalesced position")

local failures = {}
for index = 1, 200 do failures[index] = 3 end
state = client(failures)
state:send("RULES_REQUEST\t10\t0")
state:advance(35)
assert(state:queued() == 0 and #state.attempts < 100, "transient failures have a finite retry budget")

state = client({ 3, 0 })
state:send(position)
state:changeGuild()
state:advance(2)
assert(#state.delivered == 0 and state:queued() == 0, "a retry cannot leak into another guild")

state = client({ 1, 0 })
state:lock(true)
state:send("RULES_REQUEST\t10\t0")
state:send(position)
state:lock(false)
state:advance(2)
assert(#state.delivered == 1 and state.delivered[1] == position,
    "one permanent failure does not stall later packets")

state = client({ 0 })
state:lock(true)
state:send(position)
state:advance(12)
assert(state:queued() == 0 and #state.attempts == 0,
    "an expired position leaves the queue even while chat stays locked")

state = client({ 12, 0 })
assert(not state:whisper("LAYER_REQUEST\t6\t1", "Offline Person", "iRCLayerV1"))
assert(not state:whisper("ICON_REQ\t1", "Offline-Person", "iRCIconV1"),
    "a server offline response blocks other automatic routes and both Forever name forms")
assert(state:whisper("HELLO\t10", "Online Person") and #state.attempts == 2,
    "one unavailable target does not block another player")
state:advance(301)
assert(state:whisper("ICON_REQ\t1", "Offline Person", "iRCIconV1"), "offline cooldown expires")

state = client({ 0 })
state:whisper("LAYER_STATE\t6\t1", "Departed Person", "iRCLayerV1")
state:event("CHAT_MSG_SYSTEM", "No player named 'Departed Person' is currently playing.")
assert(not state:whisper("ICON_REQ\t1", "Departed Person", "iRCIconV1") and #state.attempts == 1,
    "asynchronous offline errors stop later automatic attempts")
state:event("CHAT_MSG_ADDON", "iRCConnV1", state.secret, "GUILD", "Departed Person")
assert(state.addon:IsAddonWhisperTargetUnavailable("Departed Person"), "secret addon events cannot change recipient state")
state:event("CHAT_MSG_ADDON", "UnrelatedAddon", "online", "GUILD", "Departed Person")
assert(state.addon:IsAddonWhisperTargetUnavailable("Departed Person"), "other addon prefixes cannot clear an offline cooldown")
state:event("CHAT_MSG_ADDON", "iRCConnV1", "HELLO\t10", "GUILD", "Departed-Person")
assert(state:whisper("HELLO\t10", "Departed Person"), "a new iRC packet immediately restores the recipient")
state:event("CHAT_MSG_SYSTEM", "No player named 'Never Contacted' is currently playing.")
assert(not state.addon:IsAddonWhisperTargetUnavailable("Never Contacted"), "manual whisper errors without an iRC attempt are ignored")
state:event("CHAT_MSG_SYSTEM", state.secret)

state = client({ 0 })
state:whisper("HELLO\t10", "Returning Person")
state:advance(1)
state:event("CHAT_MSG_ADDON", "iRCConnV1", "HELLO\t10", "GUILD", "Returning Person")
state:event("CHAT_MSG_SYSTEM", "No player named 'Returning Person' is currently playing.")
assert(not state.addon:IsAddonWhisperTargetUnavailable("Returning Person"),
    "a delayed offline error cannot override a newer live packet")

state = client({ 12, 0 })
state:lock(true)
state:whisper("ICON_REQ\t1", "Gone Person", "iRCIconV1")
state:whisper("LAYER_ASSIGN\t6\t1", "Gone Person", "iRCLayerV1")
state:whisper("HELLO\t10", "Other Person")
state:lock(false)
state:advance(2)
assert(#state.attempts == 2 and state.attempts[2].target == "Other Person" and state:queued() == 0,
    "queued packets for an offline target are discarded while other recipients continue")

state = client({ 0 })
state:lock(true)
state:whisper("LAYER_REQUEST\t6\t1", "Stale Recipient", "iRCLayerV1")
state:advance(6)
state:lock(false)
state:advance(1)
assert(#state.attempts == 0 and state:queued() == 0, "old layer lookups expire rather than contacting stale recipients")

state = client({ 12, 0 })
state.addon.GameTocVersion = 120000
state:whisper("ICON_REQ\t1", "Same-RealmOne", "iRCIconV1")
assert(state:whisper("ICON_REQ\t1", "Same-RealmTwo", "iRCIconV1"), "retail realm names have independent offline states")
print("PASS: numeric send results, paced retries, positions, finite failures, secret guards, guild changes, offline recipients, and recovery")
