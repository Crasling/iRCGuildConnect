-- On-demand native friend checks never send chat or addon whispers.
local function fixture(options)
    options = options or {}
    local env, addon, private = {}, {}, {}
    setmetatable(env, { __index = _G })
    env._G = env
    local clock, timers, frames, requests, reads = 1000, {}, {}, {}, 0
    local secret = {}
    local friends = options.friends or {
        { name = "Far Friend", guid = "Player-1-A", connected = true, area = "Far Zone" },
        { name = "Near Friend", guid = "Player-1-B", connected = true, area = "Current Zone" },
        { name = "Other Friend", guid = "Player-1-C", connected = true, area = "Other Zone" },
        { name = "Fourth Friend", guid = "Player-1-D", connected = true, area = "Other Zone" },
    }
    local blocked, recent, grouped = false, {}, {}
    env.GetTime = function() return clock end
    env.C_Timer = { After = function(delay, run) timers[#timers + 1] = { at = clock + delay, run = run } end }
    env.C_EventUtils = { IsEventValid = function() return options.eventValid ~= false end }
    env.C_FriendList = {
        GetNumFriends = function() reads = reads + 1; return #friends end,
        GetFriendInfoByIndex = function(index) reads = reads + 1; return friends[index] end,
    }
    env.C_Map = { GetMapInfo = function() return { name = "Current Zone" } end }
    env.C_ChatInfo = {
        SendAddonMessage = function() error("friend discovery must not send an addon message") end,
        RequestCanLocalWhisperTarget = options.noRequestAPI and nil or function(guid)
            requests[#requests + 1] = guid
            if options.requestError then error("native check unavailable") end
        end,
    }
    -- Lua's and/or idiom would replace an intentional nil with the function.
    if options.noRequestAPI then env.C_ChatInfo.RequestCanLocalWhisperTarget = nil end
    env.SendChatMessage = function() error("friend discovery must not send chat") end
    env.CreateFrame = function()
        local frame = { events = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:SetScript(key, callback) self[key] = callback end
        frames[#frames + 1] = frame
        return frame
    end
    function addon:IsSecretValue(value) return value == secret end
    function addon:IsForeverClient() return true end
    function addon:NormalizeName(name) return name:lower():gsub("%-", " ") end
    function addon:GetPlayerName() return "Local Player" end
    function addon:IsCombatTrafficBlocked() return blocked end
    function addon:IsRecentAddonPeer(name) return recent[self:NormalizeName(name)] == true end
    addon.GuildMap = { IsLayerGroupMember = function(_, name) return grouped[addon:NormalizeName(name)] == true end }
    addon.RaceGrid = { IsOwnGuildMember = function(_, name) return options.guildFriend == name end }
    private.iRC = addon
    assert(loadfile("iRC_LayerPeers.lua", "t", env))("iRC", private)
    local state = { peers = addon.LayerPeers, env = env, addon = addon, secret = secret, requests = requests, friends = friends }
    function state:advance(seconds)
        local finish = clock + seconds
        while true do
            table.sort(timers, function(a, b) return a.at < b.at end)
            if not timers[1] or timers[1].at > finish then break end
            local timer = table.remove(timers, 1)
            clock = timer.at
            timer.run()
        end
        clock = finish
    end
    function state:event(event, ...) local frame = frames[1]; frame.OnEvent(frame, event, ...) end
    function state:reply(guid, status) self:event("CAN_LOCAL_WHISPER_TARGET_RESPONSE", guid, status) end
    function state:timers() return #timers end
    function state:reads() return reads end
    function state:combat(value) blocked = value end
    function state:recent(name) recent[addon:NormalizeName(name)] = true end
    function state:grouped(name) grouped[addon:NormalizeName(name)] = true end
    return state
end

local test = fixture()
assert(#test.requests == 0 and test:timers() == 0 and test:reads() == 0,
    "loading the friend helper performs no reads, checks, or scheduled work")
local candidates = test.peers:GetCandidates(1415, 50)
assert(#candidates == 3 and candidates[1].name == "Near Friend", "online friends in this zone lead the bounded candidate list")
assert(test:timers() == 0 and #test.requests == 0 and not test.peers:IsReady("Near Friend"),
    "candidate selection and ready-cache queries do not start checks")
test:recent("Other Friend")
assert(test.peers:Observe("Other Friend", "Player-1-C", 4621, 1415))
assert(test.peers:GetCandidates(1415)[1].name == "Other Friend", "confirmed same-zone friend traffic is preferred")
assert(not test.peers:Observe("Unknown Person", "Player-1-C", 4621, 1415), "wire observations cannot create a trusted name/GUID association")
test:grouped("Near Friend")
candidates = test.peers:GetCandidates(1415)
for _, candidate in ipairs(candidates) do assert(candidate.name ~= "Near Friend", "group members already have shared group delivery") end

local guildTest = fixture({ guildFriend = "Near Friend" })
for _, candidate in ipairs(guildTest.peers:GetCandidates(1415)) do
    assert(candidate.name ~= "Near Friend", "guild friends already have shared guild delivery")
end

local answers = {}
assert(test.peers:Preflight("Other-Friend", "Player-1-C", function(allowed) answers[#answers + 1] = allowed end))
assert(test.peers:Preflight("Other Friend", "Player-1-C", function(allowed) answers[#answers + 1] = allowed end))
assert(#test.requests == 1 and test:timers() == 1, "simultaneous checks for the same trusted friend share one native request")
test:reply("Player-1-C", 0)
assert(#answers == 2 and answers[1] and answers[2] and test.peers:IsReady("OTHER-FRIEND"),
    "a successful native response briefly authorizes the trusted friend")
assert(test.peers:Preflight("Other Friend", "Player-1-C", function(allowed) assert(allowed) end) and #test.requests == 1,
    "the three-second result cache prevents duplicate requests")
test:advance(3.1)
assert(not test.peers:IsReady("Other Friend"), "a stale online response cannot authorize a later send")
assert(test.peers:Preflight("Other Friend", "Player-1-C", function(allowed) answers[#answers + 1] = allowed end))
test:reply("Player-1-C", 2)
assert(not answers[#answers] and not test.peers:IsReady("Other Friend"), "offline responses never authorize a whisper")
local requestCount = #test.requests
assert(not test.peers:Preflight("Other Friend", "Player-1-C", function(allowed) assert(not allowed) end)
    and #test.requests == requestCount, "recent negative results also avoid repeated native checks")

test = fixture()
test.peers:GetCandidates(1415)
local completed = 0
for index = 1, 4 do
    local friend = test.friends[index]
    local started = test.peers:Preflight(friend.name, friend.guid, function(allowed) assert(not allowed); completed = completed + 1 end)
    assert(started == (index <= 3), "at most three distinct native checks may be pending")
end
assert(#test.requests == 3 and completed == 1)
test:advance(2.1)
assert(completed == 4 and not test.peers:IsReady("Near Friend"), "missing responses finish once without polling")
test:reply("Player-1-A", 0)
assert(not test.peers:IsReady("Far Friend"), "late replies after a timeout cannot authorize an old lookup")
assert(not test.peers:Preflight("Far Friend", "Player-1-A", function(allowed) assert(not allowed) end))
test:advance(5.1)
assert(test.peers:Preflight("Far Friend", "Player-1-A", function(allowed) assert(allowed) end), "a later requested lookup can retry after the timeout cooldown")
test:reply("Player-1-A", 1)
assert(test.peers:IsReady("Far Friend"), "the supported guild-whisper status is also accepted")

test = fixture()
test.peers:GetCandidates(1415)
test:advance(29.5)
local accepted
assert(test.peers:Preflight("Near Friend", "Player-1-B", function(allowed) accepted = allowed end))
test:advance(1)
test:reply("Player-1-B", 0)
assert(accepted == false and not test.peers:IsReady("Near Friend"), "a response cannot revive an expired trusted friend snapshot")

test = fixture()
test.peers:GetCandidates(1415)
assert(test.peers:Preflight("Near Friend", "Player-1-B", function(allowed) accepted = allowed end))
test:event("FRIENDLIST_UPDATE")
assert(accepted == false and not test.peers:IsReady("Near Friend"))
test:reply("Player-1-B", 0)
assert(not test.peers:IsReady("Near Friend"), "friend-list changes invalidate pending associations without reading or sending")
test.peers:GetCandidates(1415)
assert(test.peers:Preflight("Near Friend", "Player-1-B", function(allowed) accepted = allowed end))
test:reply(test.secret, 0)
test:reply("Player-1-B", test.secret)
assert(not test.peers:IsReady("Near Friend"), "secret event values are ignored before indexing or comparing")
test:reply("Player-1-B", 3)
assert(accepted == false, "wrong-faction targets are rejected")
assert(not test.peers:Preflight("Unknown Person", "Player-1-B", function(allowed) assert(not allowed) end),
    "a GUID copied from received payloads cannot authorize another name")

for _, options in ipairs({ { noRequestAPI = true }, { eventValid = false }, { requestError = true } }) do
    test = fixture(options)
    test.peers:GetCandidates(1415)
    local answer
    assert(not test.peers:Preflight("Near Friend", "Player-1-B", function(allowed) answer = allowed end))
    assert(answer == false and not test.peers:IsReady("Near Friend"), "missing or failing native checks fail closed")
end

test = fixture()
test:combat(true)
assert(#test.peers:GetCandidates(1415) == 0 and test:reads() == 0, "combat blocks friend roster reads")
test:combat(test.secret)
assert(#test.peers:GetCandidates(1415) == 0 and test:reads() == 0, "a secret combat result fails closed")
test:combat(false)
test.env.C_FriendList.GetNumFriends = function() return test.secret end
assert(#test.peers:GetCandidates(1415) == 0, "secret friend counts are never iterated")
test.env.C_FriendList = nil
assert(#test.peers:GetCandidates(1415) == 0, "an unavailable friend API has no fallback discovery traffic")
test = fixture({ friends = {
    { name = "Secret Connection", guid = "Player-1-A", connected = true },
} })
test.friends[1].connected = test.secret
assert(#test.peers:GetCandidates(1415) == 0, "secret friend fields are skipped")
assert(test:timers() == 0 and #test.requests == 0, "passive helper use never starts background work")
print("PASS: on-demand trusted friend candidates, silent bounded preflights, cache expiry, timeout recovery, and secret guards")
