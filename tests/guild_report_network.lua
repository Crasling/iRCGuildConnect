-- Two isolated addon clients use the real transport queues, filters, and cache protocol.
function wipe(value) for key in pairs(value) do value[key] = nil end; return value end
local function scenario(mode, reportCount, duration)
    local now, timers, clients, errors, wire = 1000, {}, {}, {}, {}
    local droppedPacket = false
    local function later(delay, run) timers[#timers + 1] = { at = now + delay, run = run } end
    local function advance(seconds)
        local finish = now + seconds
        while true do
            table.sort(timers, function(a, b) return a.at < b.at end)
            if not timers[1] or timers[1].at > finish then break end
            local timer = table.remove(timers, 1)
            now = timer.at
            timer.run()
        end
        now = finish
        assert(#errors == 0, table.concat(errors, "\n"))
    end
    local function client(name)
        local env, addon, private, frames = {}, {}, {}, {}
        setmetatable(env, { __index = _G })
        env._G = env
        env.iRCDB, env.iRCCharDB = {}, {}
        local state = { env = env, addon = addon, combat = false, name = name }
        clients[#clients + 1] = state
        env.GetTime = function() return now end
        env.time = function() return 1800000000 + math.floor(now) end
        env.GetBuildInfo = function() return "1.60.1", "70374", "", 16001 end
        env.GetGuildInfo = function() return "Transport Guild", "Officer", 1 end
        env.UnitAffectingCombat = function() return state.combat end
        env.InCombatLockdown = function() return state.combat end
        env.issecretvalue = function() return false end
        env.CreateFrame = function()
            local frame = { RegisterEvent = function() end }
            function frame:SetScript(key, callback) self[key] = callback end
            frames[#frames + 1] = frame
            return frame
        end
        env.LibStub = function(library)
            if library == "AceAddon-3.0" then return { NewAddon = function() return addon end } end
        end
        env.geterrorhandler = function() return function(err) errors[#errors + 1] = name .. ": " .. tostring(err) end end
        env.C_Timer = { After = later }
        env.C_ChatInfo = { SendAddonMessage = function(prefix, message, distribution, target)
            wire[#wire + 1] = { from = name, at = now, message = message, target = target }
            if mode == "missing-packet" and not droppedPacket and message:match("^CACHE_DATA\t[^\t]+\t[^\t]+\t[^\t]+\t2\t") then
                droppedPacket = true
                return 0
            end
            for _, peer in ipairs(clients) do
                if peer ~= state and (distribution == "GUILD" or target == peer.name) then
                    later(0.01, function() peer.frame.OnEvent(peer.frame, "CHAT_MSG_ADDON", prefix, message, distribution, name) end)
                end
            end
            return 0
        end }
        env.WOW_PROJECT_ID = 18
        env.GetCurrentRegion = function() return 3 end
        assert(loadfile("iRC_Core.lua", "t", env))("iRC", private)
        function addon:GetSettings() return {} end
        function addon:GetPlayerName() return name end
        function addon:IsGuildConnectionActive() return true end
        function addon:IsGuildMemberName() return true end
        function addon:GetStartupTrafficDelay() return 2 end
        function addon:GetGuildDirectoryScope() return "s-18-3-10-0-pve" end
        function addon:ContainsProfanity() return false end
        function addon:CheckForNewVersion() end
        function addon:DebugMsg() end
        function addon:Text(key) return key end
        assert(loadfile("iRC_RaceGrid.lua", "t", env))("iRC", private)
        state.frame, state.grid = frames[#frames], addon.RaceGrid
        return state
    end
    local requester, sender = client("Requester One"), client("Sender One")
    local expected = reportCount or (mode == "paced-transfer" and 8 or 1)
    for index = 1, expected do
        assert(sender.grid:StoreGuildReport({
            name = mode == "maximum" and string.rep("n", 80) or "Original Reporter",
            guid = mode == "maximum" and string.rep("x", 80) or "Player-1-Report" .. index,
            guildName = mode == "maximum" and string.rep("g", 80)
                or "Shared Guild " .. (mode == "wide" and string.rep("g", 60) or "") .. index,
            guildContacts = (mode == "wide" or mode == "maximum") and string.rep("b", 140) or "",
            race = "HUMAN", faction = "Alliance", members = mode == "maximum" and 10000 or 6, averageLevel = 60,
            races = mode == "maximum" and {
                HUMAN = 837, DWARF = 833, NIGHTELF = 833, GNOME = 833, ORC = 833, SCOURGE = 833,
                TAUREN = 833, TROLL = 833, SKYBORNE = 833, DRAENEI = 833, BLOODELF = 833, UNKNOWN = 833,
            } or { HUMAN = 3, NIGHTELF = 2, UNKNOWN = 1 },
            membersLevel60 = mode == "maximum" and 10000 or 6, activeLevel60 = mode == "maximum" and 10000 or 6,
            activePlayers = mode == "maximum" and 10000 or 6, activeMembers = mode == "maximum" and 10000 or 6,
            guildDeaths = mode == "maximum" and 10000000 or 0, guildPreferredLanguage = mode == "maximum" and string.rep("l", 32) or "",
            timestamp = sender.env.time(), classes = mode == "maximum" and { DRUID = 1111, ROGUE = 1111,
                HUNTER = 1111, WARRIOR = 1111, MAGE = 1111, PRIEST = 1111, WARLOCK = 1111, PALADIN = 1111, SHAMAN = 1111 }
                or { DRUID = 6 }, addonVersion = "0.6.2",
            guildDescription = string.rep("a", 160), guildDescriptionTimestamp = sender.env.time(),
            guildDescriptionEditedBy = mode == "maximum" and string.rep("e", 80) or "Editor", rules = {}, rulesKnown = true, classBreakdownMode = "ALL",
        }, true))
    end
    local bothFighting = mode == "continuous-combat" or mode == "chain-pulls"
    local function setCombat(value)
        for _, state in ipairs(clients) do
            state.combat = value
            if value then state.addon:EnterLowTrafficMode() else state.addon:LeaveLowTrafficMode() end
        end
    end
    if bothFighting then
        setCombat(true)
        assert(not requester.grid:RequestGuildCache(), "combat starts the request through its paced queue")
    elseif mode == "initial-sender-combat" then
        sender.combat = true
        sender.addon:EnterLowTrafficMode()
        assert(requester.grid:RequestGuildCache())
    else
        assert(requester.grid:RequestGuildCache())
    end
    if mode == "receiver-combat" then
        advance(4.9)
        requester.combat = true
        requester.addon:EnterLowTrafficMode()
        advance(60)
        requester.combat = false
        requester.addon:LeaveLowTrafficMode()
    elseif mode == "sender-combat" then
        advance(4.9)
        sender.combat = true
        sender.addon:EnterLowTrafficMode()
        advance(60)
        sender.combat = false
        sender.addon:LeaveLowTrafficMode()
    end
    if mode == "chain-pulls" then
        for _ = 1, 140 do
            advance(0.3)
            setCombat(false)
            advance(0.01)
            setCombat(true)
        end
    else
        advance(duration or 30)
    end
    if mode == "missing-packet" then
        assert(not requester.grid:IsCacheUpdating(), "missing data still times out without progress")
        assert(requester.grid:RequestGuildCache(), "a failed transfer can be requested again")
        advance(30)
    end
    local store = requester.env.iRCDB.globalRaceGrid.servers["forever:" .. requester.addon:GetGuildDirectoryScope()]
    local count = 0
    for _, received in pairs(store.guildReports) do
        count = count + 1
        local sum = 0
        for _, value in pairs(received.races or {}) do sum = sum + value end
        assert(sum == received.members, "cached reports preserve every known and unknown race count")
    end
    local first, last, packets
    packets = 0
    for _, record in ipairs(wire) do
        if record.from == sender.name and record.message:match("^CACHE_DATA\t") then
            first, last, packets = first or record.at, record.at, packets + 1
        end
    end
    print(string.format("SCENARIO %s: received %d/%d guild reports, %d data packets sent at %.2f..%.2f", mode, count, expected, packets, first or 0, last or 0))
    assert(count == expected, "the requester must receive every report sent by the other client")
    if bothFighting then
        assert(requester.combat and sender.combat, "report delivery finishes without a final combat exit")
        assert(not requester.grid:IsCacheUpdating(), "combat does not leave a completed request stuck updating")
    end
end

scenario("normal")
scenario("initial-sender-combat")
scenario("sender-combat")
scenario("receiver-combat")
scenario("continuous-combat", 8, 40)
scenario("chain-pulls", 8)
scenario("paced-transfer", 8, 40)
scenario("missing-packet")
scenario("wide", 32, 240)
scenario("maximum", 1, 60)
print("PASS: independent clients, real traffic pacing, lost-packet recovery, and 32-report cache batches")
