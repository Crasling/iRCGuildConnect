-- Run from the addon directory. Exercise the real public-icon queue without
-- sending chat or addon messages to another player.
local function fixture()
    local clock, timers, sent = 1000, {}, {}
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
    local result = { icons = addon.GuildAnnouncements, sent = sent }
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
test.icons:GetPublicChatIcon("Visitor Name")
test:advance(0.2)
assert(#test.sent == 1 and test.sent[1].distribution == "WHISPER", "an unknown chat author receives one paced icon request")
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
test.icons:GetPublicChatIcon("Visitor Name")
test:advance(0.2)
assert(#test.sent == 2, "a later chat message may refresh an expired icon result")

test = fixture()
test.icons:GetPublicChatIcon("Known Visitor")
test:advance(0.2)
test.icons:ReceiveIconWire("ICON_STATUS\t1\tguildFound", "WHISPER", "Known Visitor")
test:advance(31)
local icon, kind = test.icons:GetPublicChatIcon("Known Visitor")
assert(icon and kind == "guildFound" and #test.sent == 1,
    "positive icons stay visible throughout the request cooldown")

test = fixture()
test.icons:GetPublicChatIcon("Silent Visitor")
test:advance(0.2)
test:advance(299)
test.icons:GetPublicChatIcon("Silent Visitor")
test:advance(0.2)
assert(#test.sent == 1, "an unanswered request does not repeatedly whisper a non-iRC author")
test:advance(1)
test.icons:GetPublicChatIcon("Silent Visitor")
test:advance(0.2)
assert(#test.sent == 2, "unanswered requests can be retried after five minutes")

test = fixture()
for index = 1, 8 do test.icons:GetPublicChatIcon("Queued Visitor " .. index) end
test:advance(300.5)
assert(#test.sent == 8, "the fresh part of a request queue is sent normally")
test.icons:GetPublicChatIcon("Queued Visitor 8")
test:advance(0.2)
assert(#test.sent == 8, "a delayed request keeps its cooldown after the original pending-response deadline")
test:advance(14)
test.icons:GetPublicChatIcon("Queued Visitor 8")
test:advance(0.2)
assert(#test.sent == 9, "per-name cooldown expires five minutes after the actual send")

test = fixture()
test.icons:GetPublicChatIcon("Local Player")
test.icons:GetPublicChatIcon("LOCAL-PLAYER")
test:advance(10)
assert(#test.sent == 0, "neither full-name form creates a self-whisper")

test = fixture()
for index = 1, 20 do test.icons:GetPublicChatIcon("Visitor " .. index) end
test:advance(60)
assert(#test.sent > 0 and #test.sent < 20, "a busy chat does not drain old authors into a long whisper backlog")
for index, packet in ipairs(test.sent) do
    assert(packet.at <= 1015, "queued requests expire before their author observation becomes stale")
    if index > 1 then assert(packet.at - test.sent[index - 1].at >= 2, "remaining icon requests retain global pacing") end
end
local expiredName = "Visitor 20"
test.icons:GetPublicChatIcon(expiredName)
test:advance(0.2)
assert(test.sent[#test.sent].target == expiredName, "a fresh chat observation may replace a discarded stale request")
print("PASS: negative and positive icon caching, per-name cooldown, self-whisper prevention, and short-lived paced queues")
