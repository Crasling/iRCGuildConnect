-- Real scope detection, public framing, cache exchange, and queued sends.
local clock, clients, wire, timers = 1000, {}, {}, {}
local secret = {}
local function later(delay, callback) timers[#timers + 1] = { at = clock + delay, callback = callback } end
local function advance(seconds)
    local finish = clock + seconds
    while true do
        local nextIndex
        for index, timer in ipairs(timers) do
            if timer.at <= finish and (not nextIndex or timer.at < timers[nextIndex].at) then nextIndex = index end
        end
        if not nextIndex then break end
        local timer = table.remove(timers, nextIndex)
        clock = timer.at
        timer.callback()
    end
    clock = finish
end
local function client(name, pvp, rp, hardcore)
    local addon, private, env, frames = {}, {}, {}, {}
    local state = { addon = addon, env = env, name = name, pvp = pvp, rp = rp, hardcore = hardcore }
    setmetatable(env, { __index = _G }); env._G = env
    env.iRCDB = { globalRaceGrid = { servers = { forever = { guildReports = { old = { guildName = "Old Mixed Cache" } } } } } }
    env.wipe = function(value) for key in pairs(value) do value[key] = nil end; return value end
    env.issecretvalue = function(value) return rawequal(value, secret) end
    env.WOW_PROJECT_ID = 18
    env.GetCurrentRegion = function() return 3 end
    env.GetTime = function() return clock end
    env.time = function() return 1800000000 + math.floor(clock) end
    env.GetBuildInfo = function() return "1.60.1", "70790", "", 16001 end
    env.GetGuildInfo = function() return "Home Guild", "Officer", 1 end
    env.GetChannelName = function() return 6 end
    env.GetRealmName = function() return "Forever" end
    env.Enum = { GameRule = { HardcoreRuleset = 1, PvPRuleset = 2, RPRuleset = 3 }, SendAddonMessageResult = { Success = 0 } }
    env.C_GameRules = {
        GetActiveGameMode = function() return 0 end,
        GetCurrentGameModeRecordID = function() return state.record or 10 end,
        IsGameRuleActive = function(id)
            if state.unreadable then return secret end
            if id == 1 then return state.hardcore end
            if id == 2 then return state.pvp end
            if id == 3 then return state.rp end
        end,
    }
    env.InCombatLockdown, env.UnitAffectingCombat = function() return false end, function() return false end
    env.CreateFrame = function()
        local frame = { RegisterEvent = function() end, SetScript = function(self, key, callback) self[key] = callback end }
        frames[#frames + 1] = frame
        return frame
    end
    env.LibStub = function(name) if name == "AceAddon-3.0" then return { NewAddon = function() return addon end } end end
    env.C_Timer = { After = later }
    env.geterrorhandler = function() return function(message) error(message) end end
    env.C_ChatInfo = {
        InChatMessagingLockdown = function() return state.locked == true end,
        SendAddonMessage = function(prefix, message, distribution, target)
            assert(#message <= 255, "scope metadata must fit the native addon-message limit")
            wire[#wire + 1] = { from = name, message = message, distribution = distribution }
            for _, peer in ipairs(clients) do
                if peer ~= state and (distribution == "GUILD" or target == peer.name) then
                    later(0.01, function() peer.frame.OnEvent(peer.frame, "CHAT_MSG_ADDON", prefix, message, distribution, name) end)
                end
            end
            return 0
        end,
    }
    env.SendChatMessage = function(message)
        assert(#message <= 255)
        wire[#wire + 1] = { from = name, message = message, distribution = "CHANNEL" }
        for _, peer in ipairs(clients) do
            if peer ~= state then later(0.01, function()
                peer.frame.OnEvent(peer.frame, "CHAT_MSG_CHANNEL", message, name, nil, nil, nil, nil, nil, nil, "iRCCommsV1")
            end) end
        end
    end
    assert(loadfile("iRC_Core.lua", "t", env))("iRC", private)
    function addon:GetSettings() return {} end
    function addon:GetPlayerName() return name end
    function addon:IsGuildConnectionActive() return true end
    function addon:IsGuildMemberName() return true end
    function addon:GetGuildRosterSnapshot() return {} end
    function addon:GetStartupTrafficDelay() return 0 end
    function addon:ContainsProfanity() return false end
    function addon:CheckForNewVersion() end
    function addon:DebugMsg() end
    function addon:Text(key) return key end
    assert(loadfile("iRC_RaceGrid.lua", "t", env))("iRC", private)
    state.frame, state.grid = frames[#frames], addon.RaceGrid
    function state.grid:BuildOwnGuildReports() return {} end
    function state.grid:ObserveGuildPreferredLanguage() return "" end
    function state.grid:GetLocalReport() return state.report end
    clients[#clients + 1] = state
    return state
end
local function report(state, guild)
    return { serverRuleset = state.addon:GetGuildDirectoryScope(), name = state.name, guid = "Player-1-" .. state.name,
        guildName = guild, race = "HUMAN", faction = "Alliance", members = 6, activePlayers = 6,
        activeMembers = 6, membersLevel60 = 0, activeLevel60 = 0, averageLevel = 15,
        timestamp = state.env.time(), classes = { DRUID = 6 }, rules = {}, guildDescription = "Public description",
        guildDescriptionTimestamp = state.env.time(), guildDescriptionEditedBy = "Editor", classBreakdownMode = "ALL" }
end
local pve, pvp, same = client("PvE Reporter", false, false, false), client("PvP Reporter", true, false, false), client("PvP Receiver", true, false, false)
local scopes = {}
for _, category in ipairs({ {false,false,false}, {true,false,false}, {false,false,true}, {true,true,false}, {false,true,false} }) do
    local state = client("Category Tester " .. #clients, category[1], category[2], category[3])
    local scope = assert(state.addon:GetGuildDirectoryScope())
    assert(not scopes[scope], "all five server rulesets have distinct keys")
    scopes[scope] = true
end
assert(#pvp.addon:GetGlobalRaceOverview() == 0 and pvp.env.iRCDB.globalRaceGrid.servers.forever.guildReports.old,
    "unlabelled old reports are preserved without assigning mixed data to a ruleset")
pve.report, pvp.report = report(pve, "PvE Guild"), report(pvp, "PvP Guild")
pvp.report.races = { HUMAN = 3, SKYBORNE = 2, UNKNOWN = 1 }
assert(pve.grid:BroadcastReport(true)); advance(2)
assert(#pvp.addon:GetGlobalRaceOverview() == 0, "public PvE traffic cannot enter a PvP cache")
assert(pvp.grid:BroadcastReport(true)); advance(2)
assert(same.addon:GetGlobalRaceOverview()[1].races.HUMAN == 3,
    "public guild reports include race counts in the expanded preview")
assert(#same.addon:GetGlobalRaceOverview() == 1 and same.addon:GetGlobalRaceOverview()[1].guildName == "PvP Guild",
    "matching clients still decode fragmented public reports")
assert(#pve.addon:GetGlobalRaceOverview() == 1 and pve.addon:GetGlobalRaceOverview()[1].guildName == "PvE Guild",
    "public PvP traffic cannot enter a PvE cache")
assert(not pve.grid:StoreGuildReport(pvp.report, true, true), "storage rejects a foreign tagged report")
assert(not same.grid:StoreGuildReport({ guildName = "Unknown" }, true, true), "received unlabelled reports are not adopted")
assert(pvp.grid:StoreGuildReport(pvp.report, true))
same.env.iRCDB.globalRaceGrid.servers["forever:" .. same.addon:GetGuildDirectoryScope()].guildReports = {}
assert(same.grid:RequestGuildCache()); advance(12)
assert(#same.addon:GetGlobalRaceOverview() == 1, "same-ruleset cached report offers and downloads still work")
assert(same.addon:GetGlobalRaceOverview()[1].races.SKYBORNE == 2,
    "cached guild previews retain the optional race breakdown")
assert(#pve.addon:GetGlobalRaceOverview() == 1 and pve.addon:GetGlobalRaceOverview()[1].guildName == "PvE Guild",
    "cache broadcasts cannot leak another ruleset's guilds")
local function upvalue(callback, wanted)
    for index = 1, 100 do
        local key, value = debug.getupvalue(callback, index)
        if key == wanted then return value end
        if not key then break end
    end
    error("missing helper: " .. wanted)
end
local foreign = report(pve, "Foreign Cache Payload")
local serializeReport = upvalue(pvp.grid.BroadcastReport, "serializeGuildReport")
local parseReport = upvalue(upvalue(pvp.frame.OnEvent, "handleMessage"), "parseGuildReport")
local function parsePayload(value)
    local fields = {}
    for field in (value .. "\t"):gmatch("(.-)\t") do fields[#fields + 1] = field end
    fields.serverRuleset = fields[#fields]:sub(2)
    fields[#fields] = nil
    return parseReport(fields)
end
assert(parsePayload(serializeReport(pvp.report, true)).races.UNKNOWN == 1)
local missingRaces = report(pvp, "Older Report")
assert(parsePayload(serializeReport(missingRaces, true)).races == nil, "reports without the optional race field still work")
for _, invalid in ipairs({ { HUMAN = 7 }, { HUMAN = 5 }, { HUMAN = -1, UNKNOWN = 7 }, { HUMAN = 5.5, UNKNOWN = 0.5 } }) do
    missingRaces.races = invalid
    assert(not parsePayload(serializeReport(missingRaces, true)), "invalid or inconsistent race populations are rejected")
end
local payload = upvalue(pve.grid.BroadcastReport, "serializeGuildReport")(foreign, true)
local guard = client("Cache Payload Guard", true, false, false)
assert(guard.grid:RequestGuildCache())
local requestId = wire[#wire].message:match("^CACHE_REQUEST\t8\t([^\t]+)")
assert(requestId)
local a, b = 1, 0
for index = 1, #payload do a = (a + payload:byte(index)) % 65521; b = (b + a) % 65521 end
local hash = string.format("%04x%04x", b, a)
local function receive(fields)
    guard.frame.OnEvent(guard.frame, "CHAT_MSG_ADDON", "iRCGridV1",
        table.concat(fields, "\t") .. "\t@" .. guard.addon:GetGuildDirectoryScope(), "GUILD", "Cache Relay")
end
receive({ "CACHE_OFFER", "8", requestId, guard.name, foreign.guildName, foreign.timestamp, hash, "0" })
advance(5.3)
local requestedForeign = false
for _, packet in ipairs(wire) do
    if packet.from == guard.name and packet.message:match("^CACHE_GET\t")
        and packet.message:find(foreign.guildName, 1, true) then requestedForeign = true end
end
assert(requestedForeign, "the guard fixture reaches payload validation after selecting the advertised offer")
local hex = payload:gsub(".", function(char) return string.format("%02x", char:byte()) end)
local total = math.ceil(#hex / 100)
for part = 1, total do
    guard.frame.OnEvent(guard.frame, "CHAT_MSG_ADDON", "iRCGridV1",
        table.concat({ "CACHE_DATA", "8", requestId, foreign.guildName, part, total, hash,
            hex:sub((part - 1) * 100 + 1, part * 100) }, "\t") .. "\t@" .. guard.addon:GetGuildDirectoryScope(),
        "WHISPER", "Cache Relay")
end
advance(2)
for _, value in ipairs(guard.addon:GetGlobalRaceOverview()) do
    assert(value.guildName ~= foreign.guildName, "matching outer packets cannot smuggle a foreign-ruleset cached payload")
end
local pvpScope = pvp.addon:GetGuildDirectoryScope()
local large = client(string.rep("n", 40) .. " " .. string.rep("x", 39), true, false, false)
large.report = report(large, string.rep("g", 80))
large.report.guid, large.report.guildContacts = string.rep("x", 80), string.rep("c", 140)
large.report.guildDescription, large.report.guildDescriptionEditedBy = string.rep("d", 160), string.rep("e", 80)
large.report.members, large.report.activePlayers, large.report.activeMembers = 10000, 10000, 10000
large.report.membersLevel60, large.report.activeLevel60, large.report.guildDeaths = 10000, 10000, 10000000
large.report.classes, large.report.classBreakdownClasses = { DRUID = 10000 }, { DRUID = 10000 }
large.report.guildPreferredLanguage = string.rep("l", 32)
for _, class in ipairs({ "DRUID", "ROGUE", "HUNTER", "WARRIOR", "MAGE", "PRIEST", "WARLOCK", "PALADIN", "SHAMAN" }) do
    large.report.classes[class], large.report.classBreakdownClasses[class] = 1111, 1111
end
assert(#upvalue(large.grid.BroadcastReport, "serializeGuildReport")(large.report, true) > 840,
    "the public framing fixture exceeds the former eight-part receive limit")
assert(large.grid:BroadcastReport(true)); advance(2)
local largeReceived = false
for _, value in ipairs(same.addon:GetGlobalRaceOverview()) do
    if value.guildName == large.report.guildName then largeReceived = true end
end
assert(largeReceived, "maximum-length public reports fit the bounded channel framing with their ruleset metadata")

-- Exercise the existing base-plus-details fallback with the optional races.
local fallback = client("Detail Reporter", true, false, false)
fallback.report = report(fallback, "Detail Guild")
fallback.report.races = { HUMAN = 3, SKYBORNE = 2, UNKNOWN = 1 }
local fallbackLimit = #upvalue(fallback.grid.BroadcastReport, "serializeGuildReport")(fallback.report, true) - 1
for index = 1, 100 do
    local key = debug.getupvalue(fallback.grid.BroadcastReport, index)
    if key == "MAX_CHANNEL_PAYLOAD" then debug.setupvalue(fallback.grid.BroadcastReport, index, fallbackLimit); break end
end
assert(fallback.grid:BroadcastReport(true)); advance(2)
local detailReceived
for _, value in ipairs(same.addon:GetGlobalRaceOverview()) do
    if value.guildName == "Detail Guild" then detailReceived = value end
end
assert(detailReceived and detailReceived.races and detailReceived.races.SKYBORNE == 2,
    "race data also survives the separate public detail packet")
pvp.record = 11
assert(pvp.addon:GetGuildDirectoryScope() ~= pvpScope and #pvp.addon:GetGlobalRaceOverview() == 0,
    "a different game-mode record cannot inherit the same category's cache")
pvp.record = nil
pvp.pvp = false
assert(#pvp.addon:GetGlobalRaceOverview() == 0, "switching to PvE hides the PvP cache")
assert(pvp.grid:StoreGuildReport(report(pvp, "Second PvE Guild"), true))
pvp.pvp = true
local restored = false
for _, value in ipairs(pvp.addon:GetGlobalRaceOverview()) do
    if value.guildName == "PvP Guild" then restored = true end
    assert(value.guildName ~= "Second PvE Guild")
end
assert(pvp.addon:GetGuildDirectoryScope() == pvpScope and restored, "returning to a ruleset restores its original cache")
local before = #wire
pvp.locked = true
assert(pvp.addon:SendAddonTraffic("iRCGridV1", "CACHE_REQUEST\t8\tabcd\t@" .. pvpScope, "GUILD"))
pvp.pvp, pvp.locked = false, false
advance(2)
assert(#wire == before, "a queued packet is discarded at the real send boundary after a ruleset switch")
before = #wire
pvp.unreadable = true
assert(not pvp.addon:GetGuildDirectoryScope() and #pvp.addon:GetGlobalRaceOverview() == 0)
assert(not pvp.grid:RequestGuildCache() and #wire == before, "secret ruleset values block sharing without falling back to PvE")
pvp.unreadable = false
assert(pvp.addon.GridWireVersion == "8" and pvp.addon.LayerWireVersion == "8" and pvp.addon.AdminWireVersion == "6",
    "only the guild-report protocol changes")
print("PASS: five native rulesets, public/cache isolation, preserved legacy data, ruleset switching, and stale/secret send guards")
