-- Two independent clients exchange real protocol packets through the core
-- queues. Timers, guild/group delivery and friend status checks are simulated.
local function scenario(mode)
    local clock, timers, clients, packets, dropped = 1000, {}, {}, {}, false
    local function later(delay, callback) timers[#timers + 1] = { at = clock + delay, run = callback } end
    local function advance(seconds)
        local finish = clock + seconds
        while true do
            local first
            for index, timer in ipairs(timers) do
                if timer.at <= finish and (not first or timer.at < timers[first].at) then first = index end
            end
            if not first then break end
            local timer = table.remove(timers, first)
            clock = timer.at
            timer.run()
        end
        clock = finish
    end
    local function client(name, guild, group)
        local env, addon, private = {}, {}, {}
        setmetatable(env, { __index = _G }); env._G = env
        env.iRCDB, env.iRCCharDB = {}, {}
        env.GetTime = function() return clock end
        env.GetServerTime = function() return 1800000000 + math.floor(clock) end
        env.time = env.GetServerTime
        env.GetBuildInfo = function() return "1.60.1", "70374", "", 16001 end
        env.issecretvalue = function() return false end
        env.C_Timer = { After = later }
        local frames = {}
        env.CreateFrame = function()
            local frame = { RegisterEvent = function() end, SetScript = function(self, event, run) self[event] = run end }
            frames[#frames + 1] = frame
            return frame
        end
        env.LibStub = function(library) if library == "AceAddon-3.0" then return { NewAddon = function() return addon end } end end
        local state = { name = name, guild = guild, group = group, addon = addon, ready = {}, notes = {}, notifications = 0 }
        clients[#clients + 1] = state
        env.C_ChatInfo = { SendAddonMessage = function(prefix, message, distribution, target)
            assert(#message <= 255, "every registry packet fits the real transport limit")
            packets[#packets + 1] = { from = name, message = message, distribution = distribution, target = target, at = clock }
            assert(not (distribution == "WHISPER" and message:match("^LAYER_STATE")), "no periodic state whispers")
            if mode == "lost-part" and not dropped and message:match("^LAYER_BOOK\t") then dropped = true; return 0 end
            for _, peer in ipairs(clients) do
                local deliver = distribution == "GUILD" and guild and peer.guild == guild
                    or (distribution == "PARTY" or distribution == "RAID") and group and peer.group == group
                    or distribution == "WHISPER" and target == peer.name
                if peer ~= state and deliver then
                    local deliveryDelay = mode == "delayed-friends" and distribution == "WHISPER" and 85 or 0.02
                    if mode == "reordered" and message:match("^LAYER_BOOK\t") then
                        local part = tonumber(message:match("^LAYER_BOOK\t[^\t]+\t[^\t]+\t[^\t]+\t[^\t]+\t(%d+)"))
                        deliveryDelay = deliveryDelay + (3 - part % 3) * 0.08
                    end
                    later(deliveryDelay, function()
                        peer.raceFrame.OnEvent(peer.raceFrame, "CHAT_MSG_ADDON", prefix, message, distribution, name)
                    end)
                end
            end
            return 0
        end }
        assert(loadfile("iRC_Core.lua", "t", env))("iRC", private)
        function addon:GetPlayerName() return name end
        function addon:GetGuildKey() return guild end
        function addon:GetSettings() return {} end
        function addon:GetGuildRosterSnapshot()
            local roster = {}
            for _, peer in ipairs(clients) do
                if guild and peer.guild == guild then roster[#roster + 1] = { name = peer.name } end
            end
            return roster
        end
        function addon:DebugMsg(message) state.notes[#state.notes + 1] = message end
        assert(loadfile("iRC_LayerRegistry.lua", "t", env))("iRC", private)
        assert(loadfile("iRC_LayerSync.lua", "t", env))("iRC", private)
        addon.GuildMap = {
            GetLayerGroupDistribution = function() return group and (mode == "raid" and "RAID" or "PARTY") or nil end,
            OnLayerRegistryMerged = function() state.notifications = state.notifications + 1 end,
            RefreshLocalLayerEvidence = function() end,
            IsLayerGroupMember = function(_, sender)
                for _, peer in ipairs(clients) do
                    if group and peer.group == group and peer.name == sender then return true end
                end
                return false
            end,
        }
        addon.LayerPeers = {
            GetCandidates = function()
                if mode == "bridge" then
                    if name ~= "Alpha One" then return {} end
                    return { { name = "Beta Two", guid = "Player-1-Beta" } }
                end
                if mode ~= "friends" and mode ~= "friend-star" and mode ~= "offline-friend" and mode ~= "missing-friend" and mode ~= "delayed-friends" then return {} end
                local result = {}
                for _, peer in ipairs(clients) do if peer ~= state then result[#result + 1] = { name = peer.name, guid = "Player-1-" .. peer.name } end end
                return result
            end,
            Preflight = function(_, target, _, callback)
                later(0.05, function() state.ready[target] = mode ~= "offline-friend"; callback(state.ready[target]) end)
                return true
            end,
            IsReady = function(_, target) return state.ready[target] == true end,
            IsKnownFriend = function(_, sender)
                if mode == "bridge" then
                    return name == "Alpha One" and sender == "Beta Two" or name == "Beta Two" and sender == "Alpha One"
                end
                if mode == "friends" or mode == "friend-star" or mode == "missing-friend" or mode == "delayed-friends" then
                    for _, peer in ipairs(clients) do if peer ~= state and peer.name == sender then return true end end
                end
                return false
            end,
        }
        assert(loadfile("iRC_RaceGrid.lua", "t", env))("iRC", private)
        state.raceFrame = frames[#frames]
        return state
    end
    local sharedGuild = (mode == "guild" or mode == "concurrent" or mode == "wide" or mode == "maximum" or mode == "reordered" or mode == "lost-part") and "Shared Guild" or nil
    local sharedGroup = (mode == "party" or mode == "raid") and "Shared Group" or nil
    local a = client("Alpha One", mode == "bridge" and "Guild A" or sharedGuild, sharedGroup)
    local b = client("Beta Two", mode == "bridge" and "Guild B" or sharedGuild, mode == "bridge" and "Group BC" or sharedGroup)
    local c = mode == "bridge" and client("Gamma Three", "Guild C", "Group BC")
        or mode == "friend-star" and client("Gamma Three") or nil
    local d = mode == "friend-star" and client("Delta Four") or nil
    local aBook, bBook = a.addon.LayerRegistry, b.addon.LayerRegistry
    if mode ~= "missing-friend" and mode ~= "concurrent" then aBook:Claim(200, 4621, 1415, 1, "alpha", 1800000900, 1800000990) end
    if mode ~= "concurrent" then bBook:Claim(100, 4621, 1415, 1, "beta", 1800000800, 1800000990) end
    if mode ~= "missing-friend" and mode ~= "concurrent" then bBook:Claim(200, 4621, 1415, 2, "beta", 1800000950, 1800000990) end
    if mode == "wide" or mode == "reordered" or mode == "lost-part" then
        for rawId = 300, 350 do bBook:Claim(rawId, 4621, 1415, 1, "beta", 1800000900, 1800000990) end
    end
    if mode == "maximum" then
        for rawId = 300, 396 do bBook:Claim(rawId, 4621, 1415, 1, string.rep("beta", 16), 1800000900, 1800000990) end
        assert(#bBook:Export(4621, 1415) == 99, "the largest supported book is exercised through the actual transport")
    end
    if c then
        c.addon.LayerRegistry:Claim(50, 4621, 1415, 1, "gamma", 1800000700, 1800000990)
        c.addon.LayerRegistry:Claim(200, 4621, 1415, 3, "gamma", 1800000990, 1800000990)
    end
    if d then
        d.addon.LayerRegistry:Claim(25, 4621, 1415, 1, "delta", 1800000600, 1800000990)
        d.addon.LayerRegistry:Claim(200, 4621, 1415, 4, "delta", 1800000990, 1800000990)
    end
    local layer = { zoneUID = 200, serverId = 4621, mapId = 1415 }
    assert(a.addon.LayerSync:Request(layer) == (mode ~= "solo"), "a lookup uses only available audiences")
    if mode == "concurrent" then
        local other = { zoneUID = 100, serverId = 4621, mapId = 1415 }
        assert(b.addon.LayerSync:Request(other))
        advance(2)
        aBook:Claim(200, 4621, 1415, 1, "alpha", 1800001002, 1800001002)
        bBook:Claim(100, 4621, 1415, 1, "beta", 1800001002, 1800001002)
        assert(a.addon.LayerSync:Publish(layer) and b.addon.LayerSync:Publish(other), "concurrent local creations are shared in their original lookup")
    end
    if mode == "missing-friend" then
        advance(2)
        assert(aBook:GetNumber(200, 4621, 1415) == nil, "a missing reply never invents a claim remotely")
        aBook:Claim(200, 4621, 1415, 1, "alpha", 1800001002, 1800001002)
        assert(a.addon.LayerSync:Publish(layer), "the created row is returned to the friend who answered missing")
    end
    advance(mode == "delayed-friends" and 280 or mode == "maximum" and 90 or 15)
    if mode == "lost-part" then
        assert(a.notifications == 0, "an incomplete snapshot never partially updates or confirms a registry")
        assert(a.addon.LayerSync:Request(layer), "a new explicit lookup can recover a lost snapshot")
        advance(25)
    end
    if mode == "offline-friend" or mode == "solo" then
        assert(#packets == 0, "no outgoing whisper is used when a friend is offline or no audience exists")
    else
        assert(aBook:GetNumber(200, 4621, 1415) == bBook:GetNumber(200, 4621, 1415), "same raw ID has the same short number on both clients")
        assert(aBook:GetNumber(100, 4621, 1415) == bBook:GetNumber(100, 4621, 1415), "other IDs remain coherent after collision resolution")
        local first, second = aBook:Export(4621, 1415), bBook:Export(4621, 1415)
        assert(#first == #second and first[2].owner == second[2].owner, "the requester returns missing claim origins to its peer")
        assert(a.notifications > 0 and b.notifications > 0, "registry updates reach both clients")
        if c then
            assert(c.addon.LayerRegistry:GetNumber(200, 4621, 1415) == aBook:GetNumber(200, 4621, 1415),
                "a friend lookup carries shared numbering through another guild's party")
            assert(aBook:GetNumber(50, 4621, 1415) == c.addon.LayerRegistry:GetNumber(50, 4621, 1415),
                "claims missing from the original lookup return across the same friend exchange")
        end
        if d then
            for _, peer in ipairs({ b, c, d }) do
                for _, raw in ipairs({ 25, 50, 100, 200 }) do
                    assert(peer.addon.LayerRegistry:GetNumber(raw, 4621, 1415) == aBook:GetNumber(raw, 4621, 1415),
                        "all three friends receive the union even when they are not friends with each other")
                end
            end
        end
    end
    local count = #packets
    advance(180)
    assert(#packets == count, "no lookup or state traffic repeats on a timer")
    return a, b, packets, advance
end

for _, mode in ipairs({ "guild", "party", "raid", "friends", "friend-star", "missing-friend", "delayed-friends",
    "concurrent", "wide", "maximum", "reordered", "lost-part", "bridge", "offline-friend", "solo" }) do scenario(mode) end

local a, _, packets, advance = scenario("friends")
local count = #packets
assert(not a.addon.LayerSync:Receive("LAYER_BOOK\t7\tqbad\t4621\t1415\t1\t1\t123\tinvalid", "WHISPER", "Unsolicited Stranger"),
    "unsolicited private books cannot modify the registry")
assert(not a.addon:SendAddonTraffic("iRCLayerV1", "LAYER_QUERY\t7\tqbad\t4621\t1415\t200", "WHISPER", "Unsolicited Stranger"),
    "the transport refuses an uncorrelated background query")
advance(2)
assert(#packets == count, "invalid or unsolicited packets trigger no response")
print("PASS: independent guild, party, raid and friend clients share registry claims; offline/solo stays silent; no periodic traffic")
