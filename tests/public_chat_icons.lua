-- Run from the addon directory. Exercise the real public-icon queue without
-- sending chat or addon messages to another player.
local function fixture()
    local clock, timers, sent, confirmedPeers, unavailablePeers = 1000, {}, {}, {}, {}
    local addon = {}
    function GetTime() return clock end
    function time() return math.floor(clock) end
    function strsplit(separator, value)
        local parts = {}
        for part in (value .. separator):gmatch("(.-)" .. separator) do parts[#parts + 1] = part end
        return table.unpack(parts)
    end
    C_Timer = { After = function(delay, callback)
        timers[#timers + 1] = { at = clock + delay, callback = callback }
    end }
    function CreateFrame()
        return { RegisterEvent = function() end, SetScript = function() end }
    end
    function addon:IsForeverClient() return true end
    function addon:IsOfficialHardcoreRealm() return false end
    function addon:IsTestAdminName() return false end
    function addon:GetPlayerName() return "Local Player" end
    function addon:NormalizeName(name) return tostring(name or ""):lower():gsub("%-", " ") end
    function addon:IsRecentAddonPeer(name)
        local lastPacket = confirmedPeers[self:NormalizeName(name)]
        return lastPacket ~= nil and clock - lastPacket <= 30
    end
    function addon:IsAddonWhisperTargetUnavailable(name) return unavailablePeers[self:NormalizeName(name)] == true end
    function addon:SendAddonTraffic(prefix, payload, distribution, target)
        sent[#sent + 1] = { at = clock, prefix = prefix, payload = payload, distribution = distribution, target = target }
        return true
    end
    local sourceFile = assert(io.open("iRC_GuildAnnouncements.lua", "r"))
    local source = sourceFile:read("*a")
    sourceFile:close()
    -- This runner uses a newer Lua than WoW; isolate the icon protocol from
    -- unrelated Lua 5.1 milestone loops farther down the module.
    local protocolEnd = assert(source:find("\nlocal ICON_HELP =", 1, true))
    assert(load(source:sub(1, protocolEnd - 1), "@iRC_GuildAnnouncements.lua"))("iRC", { iRC = addon })
    local result = { icons = addon.GuildAnnouncements, sent = sent, addon = addon }
    function result:confirm(name, age) confirmedPeers[addon:NormalizeName(name)] = clock - (age or 0) end
    function result:unavailable(name, value) unavailablePeers[addon:NormalizeName(name)] = value ~= false end
    function result:advance(seconds)
        local finish = clock + seconds
        while true do
            local nextIndex, nextAt
            for index, timer in ipairs(timers) do
                if timer.at <= finish and (not nextAt or timer.at < nextAt) then nextIndex, nextAt = index, timer.at end
            end
            if not nextIndex then break end
            local timer = table.remove(timers, nextIndex)
            clock = timer.at
            timer.callback()
        end
        clock = finish
    end
    return result
end

local test = fixture()
for index = 1, 500 do test.icons:GetPublicChatIcon("Unknown Visitor " .. index) end
test:advance(60)
assert(#test.sent == 0, "a crowd of unknown chat names never creates icon whispers")

test = fixture()
test:confirm("Visitor Name")
test.icons:GetPublicChatIcon("Visitor Name")
test:advance(0.2)
assert(#test.sent == 1 and test.sent[1].distribution == "WHISPER", "a recently confirmed iRC peer receives one paced icon request")
test.icons:ReceiveIconWire("ICON_STATUS\t1\tnone", "WHISPER", "Visitor Name")
for _ = 1, 50 do
    assert(test.icons:GetPublicChatIcon("Visitor Name") == nil, "no badge remains a valid negative answer")
    test:advance(0.1)
end
test:advance(31)
test.icons:GetPublicChatIcon("Visitor Name")
test:advance(0.2)
assert(#test.sent == 1, "chatting without a badge never restarts requests after the old 30-second cache window")
test:advance(300)
test:confirm("Visitor Name")
test.icons:GetPublicChatIcon("Visitor Name")
test:advance(0.2)
assert(#test.sent == 2, "a later chat message may refresh an expired icon result")

test = fixture()
test:confirm("Known Visitor")
test.icons:GetPublicChatIcon("Known Visitor")
test:advance(0.2)
test.icons:ReceiveIconWire("ICON_STATUS\t1\tguildFound", "WHISPER", "Known Visitor")
test:advance(31)
local icon, kind = test.icons:GetPublicChatIcon("Known Visitor")
assert(icon and kind == "guildFound" and #test.sent == 1,
    "positive icons stay visible throughout the request cooldown")

test = fixture()
test:confirm("Silent Visitor")
test.icons:GetPublicChatIcon("Silent Visitor")
test:advance(0.2)
test:advance(299)
test:confirm("Silent Visitor")
test.icons:GetPublicChatIcon("Silent Visitor")
test:advance(0.2)
assert(#test.sent == 1, "an unanswered request does not repeatedly whisper a confirmed peer")
test:advance(1)
test.icons:GetPublicChatIcon("Silent Visitor")
test:advance(0.2)
assert(#test.sent == 2, "unanswered requests can be retried after five minutes")

test = fixture()
for index = 1, 8 do
    test:confirm("Queued Visitor " .. index)
    test.icons:GetPublicChatIcon("Queued Visitor " .. index)
end
test:advance(300.5)
assert(#test.sent == 8, "the fresh part of a request queue is sent normally")
test:confirm("Queued Visitor 8")
test.icons:GetPublicChatIcon("Queued Visitor 8")
test:advance(0.2)
assert(#test.sent == 8, "a delayed request keeps its cooldown after the original pending-response deadline")
test:advance(14)
test.icons:GetPublicChatIcon("Queued Visitor 8")
test:advance(0.2)
assert(#test.sent == 9, "per-name cooldown expires five minutes after the actual send")

test = fixture()
test:confirm("Local Player")
test.icons:GetPublicChatIcon("Local Player")
test.icons:GetPublicChatIcon("LOCAL-PLAYER")
test:advance(10)
assert(#test.sent == 0, "neither full-name form creates a self-whisper")

test = fixture()
for index = 1, 20 do
    test:confirm("Visitor " .. index)
    test.icons:GetPublicChatIcon("Visitor " .. index)
end
test:advance(60)
assert(#test.sent > 0 and #test.sent < 20, "a busy chat does not drain old authors into a long whisper backlog")
for index, packet in ipairs(test.sent) do
    assert(packet.at <= 1015, "queued requests expire before their author observation becomes stale")
    if index > 1 then assert(packet.at - test.sent[index - 1].at >= 2, "remaining icon requests retain global pacing") end
end
local expiredName = "Visitor 20"
local sentBeforeFreshPacket = #test.sent
test.icons:GetPublicChatIcon(expiredName)
test:advance(0.2)
assert(#test.sent == sentBeforeFreshPacket, "chat alone cannot renew expired iRC evidence")
test:confirm(expiredName)
test.icons:GetPublicChatIcon(expiredName)
test:advance(0.2)
assert(test.sent[#test.sent].target == expiredName, "fresh iRC evidence can replace a discarded stale request")

test = fixture()
test:confirm("First Peer")
test:confirm("Expiring Peer", 29)
test.icons:GetPublicChatIcon("First Peer")
test.icons:GetPublicChatIcon("Expiring Peer")
test:advance(3)
assert(#test.sent == 1 and test.sent[1].target == "First Peer",
    "a peer whose evidence expires while queued is never whispered")
test:confirm("Expiring Peer")
test.icons:GetPublicChatIcon("Expiring Peer")
test:advance(0.2)
assert(#test.sent == 2 and test.sent[2].target == "Expiring Peer",
    "discarding an unsent stale request does not leave a five-minute false cooldown")

test = fixture()
test:confirm("Offline Peer")
test.icons:GetPublicChatIcon("Offline Peer")
test:unavailable("Offline Peer")
test:advance(1)
assert(#test.sent == 0, "an offline reply received while the icon request waits discards the request")
test:unavailable("Offline Peer", false)
test:confirm("Offline Peer")
test.icons:GetPublicChatIcon("Offline Peer")
test:advance(0.2)
assert(#test.sent == 1, "new online evidence can retry a discarded unsent request")

test = fixture()
test:confirm("Known Peer")
test.addon.IsRecentAddonPeer = nil
test.icons:GetPublicChatIcon("Known Peer")
test:advance(1)
assert(#test.sent == 0, "a missing peer-evidence helper never falls back to blind whispers")

print("PASS: confirmed-peer icon requests, unknown crowds, send-time expiry, offline guards, caching, cooldown, and paced queue recovery")
