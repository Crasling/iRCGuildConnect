local function key(instance, server, map) return tostring(server) .. "-" .. tostring(instance) .. "-" .. tostring(map) end
-- Exercise shared replies with a large audience. A queue deliberately delays
-- bulk chunks so responders must yield before a full snapshot has arrived.
local function run(count, queryCount, concurrent, interrupted, useChannel)
    local audience, channelTarget = useChannel and "CHANNEL" or "GUILD", useChannel and "6" or nil
    local clock, timers, clients, packets, snapshots = 1000, {}, {}, 0, 0
    local interruptedSender
    local function later(delay, callback)
        timers[#timers + 1] = { at = clock + delay, run = callback }
    end
    local function advance(duration)
        local finish, steps = clock + duration, 0
        while true do
            local first
            for index, timer in ipairs(timers) do
                if timer.at <= finish and (not first or timer.at < timers[first].at) then first = index end
            end
            if not first then break end
            local timer = table.remove(timers, first)
            clock, steps = timer.at, steps + 1
            assert(steps < 50000, "a bounded exchange must settle rather than continually rescheduling")
            timer.run()
        end
        clock = finish
    end
    for index = 1, count do
        local addon, private, env = {}, {}, {}
        private.iRC = addon
        setmetatable(env, { __index = _G })
        env.GetTime = function() return clock end
        env.GetServerTime = function() return 1800000000 + math.floor(clock) end
        env.C_Timer = { After = later }
        function addon:IsSecretValue() return false end
        function addon:HasSecretValues() return false end
        function addon:IsForeverClient() return true end
        function addon:NormalizeName(name) return (name or ""):lower() end
        function addon:GetPlayerName() return "Player " .. index end
        function addon:GetGuildKey() return not useChannel and "guild" or nil end
        function addon:GetGuildDirectoryScope() return "s-18-3-10-0-pve" end
        function addon:IsGuildDirectoryPacketCurrent(message) return message:match("\t@([%w%-]+)$") == self:GetGuildDirectoryScope() end
        env.GetChannelName = function(name) assert(name == "iRCCommsV1"); return useChannel and 6 or 0 end
        function addon:DebugMsg() end
        local normal, bulk, scheduled = {}, {}, false
        local function drain()
            local queue = #normal > 0 and normal or bulk
            local packet = table.remove(queue, 1)
            if packet and addon.LayerSync:AllowsPacket("LAYER_BOOK", packet, audience, channelTarget) then
                packets = packets + 1
                if packet:match("^LAYER_BOOK\t[^\t]+\t[^\t]+\t[^\t]+\t[^\t]+\t1\t") then snapshots = snapshots + 1 end
                addon.LayerSync:OnPacketSent("LAYER_BOOK", packet, audience, channelTarget)
                local part, total = packet:match("^LAYER_BOOK\t[^\t]+\t[^\t]+\t[^\t]+\t[^\t]+\t(%d+)\t(%d+)")
                if interrupted and not interruptedSender then interruptedSender = addon:GetPlayerName() end
                local lost = interrupted and interruptedSender == addon:GetPlayerName() and part == total
                later(0.02, function()
                    if lost then return end
                    for _, peer in ipairs(clients) do
                        if peer ~= addon then assert(peer.LayerSync:Receive(packet, audience, addon:GetPlayerName(), channelTarget)) end
                    end
                end)
            end
            scheduled = #normal + #bulk > 0
            if scheduled then later(0.04, drain) end
        end
        function addon:SendAddonTraffic(_, message, distribution, target)
            assert(distribution == audience, "crowded sharing stays on its original broadcast audience")
            assert(#message <= 255, "scoped channel packets fit the addon-message limit")
            local kind = message:match("^([A-Z_]+)")
            assert(self.LayerSync:AllowsPacket(kind, message, distribution, target))
            if kind == "LAYER_QUERY" then
                packets = packets + 1
                later(0.02, function()
                    for _, peer in ipairs(clients) do
                        if peer ~= addon then assert(peer.LayerSync:Receive(message, distribution, addon:GetPlayerName(), channelTarget)) end
                    end
                end)
            else
                local queue = message:match("^LAYER_BOOK\t[^\t]+\t[^\t]+\t[^\t]+\t[^\t]+\t1\t") and normal or bulk
                queue[#queue + 1] = message
                if not scheduled then scheduled = true; later(0.04, drain) end
            end
            return true
        end
        assert(loadfile("iRC_LayerRegistry.lua", "t", env))("iRC", private)
        assert(loadfile("iRC_LayerSync.lua", "t", env))("iRC", private)
        clients[#clients + 1] = addon
        -- Every responder knows the same claims but has a different sighting
        -- timestamp. Those timestamps must not trigger return snapshots.
        if index > 1 and not concurrent then
            for rawId = 100, 108 do
                addon.LayerRegistry:Claim(key(rawId, 4621, 1415), 4621, 1415, 1, "origin", 1800000800,
                    1800000900 + index % 90)
            end
        end
    end
    local layer = { serverId = 4621, mapId = 1415, instanceId = 100, zoneUID = 2 }
    if concurrent then
        for _, client in ipairs(clients) do assert(client.LayerSync:Request(layer)) end
        advance(2)
        for _, client in ipairs(clients) do
            client.LayerRegistry:Claim(key(100, 4621, 1415), 4621, 1415, 1, client:GetPlayerName(), 1800001002, 1800001002)
            assert(client.LayerSync:Publish(layer))
        end
    else
        for _ = 1, queryCount do assert(clients[1].LayerSync:Request(layer)) end
    end
    advance(20)
    local expected = clients[1].LayerRegistry:GetNumber(key(100, 4621, 1415), 4621, 1415)
    assert(expected ~= nil, "the requester receives the shared book")
    for _, client in ipairs(clients) do
        assert(client.LayerRegistry:GetNumber(key(100, 4621, 1415), 4621, 1415) == expected, "all clients retain the same numbering")
        assert(client.LayerRegistry:Export(4621, 1415)[1].owner == clients[1].LayerRegistry:Export(4621, 1415)[1].owner,
            "simultaneous creators converge on the same original claim")
    end
    assert(snapshots <= 40, "a crowded audience must suppress redundant snapshots, got " .. snapshots)
    assert(packets <= (concurrent and count * 3 or queryCount + 50), "observations alone must not generate a guild-wide reply storm, got " .. packets)
    local settled = packets
    advance(180)
    assert(packets == settled, "an idle guild produces no repeated layer traffic")
    print("PASS: " .. count .. " clients, " .. queryCount .. " lookup(s), " .. snapshots .. " snapshot(s), " .. packets .. " packets")
end

run(1000, 1)
run(2, 60)
run(20, 1, true)
run(3, 1, false, true)
run(1000, 1, false, false, true)
run(2, 60, false, false, true)
