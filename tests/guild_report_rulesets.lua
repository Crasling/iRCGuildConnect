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
        timestamp = state.env.time(), classes = { DRUID = 6 }, rules = {}, rulesKnown = true, guildDescription = "Public description",
        guildDescriptionTimestamp = state.env.time(), guildDescriptionEditedBy = "Editor", classBreakdownMode = "ALL" }
end
local function findGuild(state, name)
    for _, value in ipairs(state.addon:GetGlobalRaceOverview()) do if value.guildName == name then return value end end
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
assert(findGuild(pvp, "PvE Guild").serverRuleset == pve.addon:GetGuildDirectoryScope(), "public reports retain their origin across server rulesets")
assert(pvp.grid:BroadcastReport(true)); advance(2)
assert(findGuild(same, "PvP Guild").races.HUMAN == 3,
    "public guild reports include race counts in the expanded preview")
assert(#same.addon:GetGlobalRaceOverview() == 2 and findGuild(same, "PvP Guild"),
    "matching clients still decode fragmented public reports")
assert(#pve.addon:GetGlobalRaceOverview() == 2 and findGuild(pve, "PvP Guild"),
    "the directory includes reports from every visible server ruleset")
assert(pve.grid:StoreGuildReport(pvp.report, true, true), "storage preserves a foreign report's own server ruleset")
assert(not same.grid:StoreGuildReport({ guildName = "Unknown" }, true, true), "received unlabelled reports are not adopted")
assert(pvp.grid:StoreGuildReport(pvp.report, true))
same.env.iRCDB.globalRaceGrid.servers["forever:" .. same.addon:GetGuildDirectoryScope()].guildReports = {}
assert(same.grid:RequestGuildCache()); advance(12)
assert(#same.addon:GetGlobalRaceOverview() == 2, "cached report downloads preserve guilds from both server rulesets")
assert(findGuild(same, "PvP Guild").races.SKYBORNE == 2,
    "cached guild previews retain the optional race breakdown")
assert(#pve.addon:GetGlobalRaceOverview() == 2, "public cache discovery keeps existing reports")
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
advance(15)
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
assert(pvp.addon:GetGuildDirectoryScope() ~= pvpScope and findGuild(pvp, "PvP Guild"),
    "changing the current server context does not hide public guild reports")
pvp.record = nil
pvp.pvp = false
assert(findGuild(pvp, "PvP Guild"), "switching to PvE keeps the PvP origin on its cached guilds")
assert(pvp.grid:StoreGuildReport(report(pvp, "Second PvE Guild"), true))
pvp.pvp = true
local restored = false
for _, value in ipairs(pvp.addon:GetGlobalRaceOverview()) do
    if value.guildName == "PvP Guild" then restored = true end
end
assert(pvp.addon:GetGuildDirectoryScope() == pvpScope and restored, "returning to a ruleset restores its original cache")
assert(findGuild(pvp, "Second PvE Guild"), "all public ruleset caches remain browsable")
local before = #wire
pvp.locked = true
assert(pvp.addon:SendAddonTraffic("iRCGridV1", "CACHE_REQUEST\t8\tabcd\t@" .. pvpScope, "GUILD"))
pvp.pvp, pvp.locked = false, false
advance(2)
assert(#wire == before, "a queued packet is discarded at the real send boundary after a ruleset switch")
before = #wire
pvp.unreadable = true
assert(not pvp.addon:GetGuildDirectoryScope() and findGuild(pvp, "PvP Guild"),
    "known report origins remain readable when the current character's ruleset is temporarily unavailable")
assert(pvp.grid:StoreGuildReport(report(pve, "Reported PvE Origin"), true, true),
    "receiving a known origin does not depend on the current character's unavailable game-mode APIs")
assert(not pvp.grid:RequestGuildCache() and #wire == before, "secret ruleset values block sharing without falling back to PvE")
pvp.unreadable = false
assert(pvp.addon.GridWireVersion == "8" and pvp.addon.LayerWireVersion == "8" and pvp.addon.AdminWireVersion == "6",
    "only the guild-report protocol changes")
print("PASS: five server origins, cross-ruleset public reports, origin validation, preserved caches, and stale/secret send guards")

-- A relay's own realm and rules never become the origin of cached reports.
clients, timers, wire = {}, {}, {}
local relay = client("Directory Relay", false, false, false)
local receiver = client("Directory Receiver", true, false, false)
local originPvP = receiver.addon:GetGuildDirectoryScope()
local originPvE = relay.addon:GetGuildDirectoryScope()
local expected = {}
for index, origin in ipairs({ originPvE, originPvP, originPvP }) do
    local snapshot = report(relay, "Same Guild Name")
    snapshot.serverRuleset, snapshot.serverName = origin, "Realm " .. index
    snapshot.guid = "Player-" .. index .. "-Origin"
    snapshot.rules = { guildFoundOnly = index >= 2 }
    snapshot.races = { HUMAN = 6 }
    assert(relay.grid:StoreGuildReport(snapshot, true, true))
    expected[relay.grid:GetReportIdentity(snapshot)] = true
end
local long = report(relay, string.rep("g", 80))
long.serverName, long.serverRuleset = string.rep("r", 80), originPvP
long.races = { HUMAN = 6 }
assert(relay.grid:StoreGuildReport(long, true, true))
expected[relay.grid:GetReportIdentity(long)] = true
assert(receiver.grid:RequestGuildCache()); advance(45)
local received = receiver.addon:GetGlobalRaceOverview()
assert(#received == 3, "Forever internal realm labels merge while different server rulesets remain separate")
for _, snapshot in ipairs(received) do
    assert(expected[receiver.grid:GetReportIdentity(snapshot)], "cache relays must preserve the exact origin identity")
    if snapshot.serverName == "Realm 2" then
        assert(snapshot.serverRuleset == originPvP and snapshot.rules.guildFoundOnly,
            "server PvP and the Guild-Found challenge stay independent")
    end
end
assert(receiver.addon:GetGuildDirectoryRulesetLabel(originPvP) == "PvP")
assert(relay.addon:GetGuildDirectoryRulesetLabel(originPvE) == "PvE")
local function countData()
    local count = 0
    for _, packet in ipairs(wire) do if packet.message:match("^CACHE_DATA\t") then count = count + 1 end end
    return count
end
local dataCount = countData()
assert(receiver.grid:RequestGuildCache()); advance(30)
assert(countData() == dataCount, "refreshing known foreign reports does not download them again")

-- A maximum-size public base must retain its realm even if details are lost.
relay.report = long
relay.report.name = relay.name
relay.pvp = true
assert(relay.grid:BroadcastReport(true)); advance(2)
assert(#receiver.addon:GetGlobalRaceOverview() == 3, "public refreshes merge by origin rather than creating a second realm-less entry")
local wrongGame = report(relay, "Wrong Game")
wrongGame.serverRuleset = originPvE:gsub("s%-18%-", "s-1-")
assert(not receiver.grid:StoreGuildReport(wrongGame, true, true), "other game projects are not accepted as server rulesets")
wrongGame.serverRuleset = originPvE:gsub("s%-18%-3%-", "s-18-1-")
assert(not receiver.grid:StoreGuildReport(wrongGame, true, true), "other regions remain outside the directory")
print("PASS: mixed-origin cache transfers, separate same-named guilds, bounded long-name packets, independent challenge tags, and no repeated downloads")

-- 0.7.7 reports omit the optional realm field. Match the complete old
-- snapshot rather than guessing a realm from a shared guild name.
clients, timers, wire = { receiver }, {}, {}
function receiver.addon:IsForeverClient() return false end
local known = report(receiver, "Older Peer Guild")
known.serverName = "Known Realm"
assert(receiver.grid:StoreGuildReport(known, true, true))
local serialize = upvalue(receiver.grid.BroadcastReport, "serializeGuildReport")
local checksum = upvalue(receiver.grid.RequestGuildCache, "payloadChecksum")
local function offerFromOlderPeer(snapshot, relayed)
    assert(receiver.grid:RequestGuildCache())
    local id = assert(wire[#wire].message:match("^CACHE_REQUEST\t8\t([^\t]+)"))
    local oldPayload = serialize(snapshot, true):gsub("\t[^\t]*(\t@[%w%-]+)$", "%1")
    if relayed then oldPayload = oldPayload:gsub("(\t@[%w%-]+)$", "\t%1") end
    local fields = { "CACHE_OFFER", "8", id, receiver.name, snapshot.guildName,
        snapshot.timestamp, checksum(oldPayload), "0" }
    if relayed then
        fields[#fields + 1] = originPvP
        fields[#fields + 1] = "#" .. checksum(receiver.grid:GetReportIdentity({ guildName = snapshot.guildName, serverRuleset = originPvP }))
    end
    fields[#fields + 1] = "@" .. originPvP
    receiver.frame.OnEvent(receiver.frame, "CHAT_MSG_ADDON", "iRCGridV1",
        table.concat(fields, "\t"), "GUILD", "Older Peer")
    advance(8)
    return id
end
local oldRequest = offerFromOlderPeer(known)
for _, packet in ipairs(wire) do
    assert(not packet.message:find("CACHE_GET\t8\t" .. oldRequest .. "\t", 1, true),
        "an unchanged 0.7.7 snapshot is not downloaded again when a realm-labelled copy is already saved")
end
local relayedRequest = offerFromOlderPeer(known, true)
for _, packet in ipairs(wire) do
    assert(not packet.message:find("CACHE_GET\t8\t" .. relayedRequest .. "\t", 1, true),
        "a newer relay of the same realm-less snapshot also avoids a repeated download")
end
local distinct = report(receiver, known.guildName)
distinct.timestamp, distinct.guid = known.timestamp, "Player-Other-Realm"
local distinctRequest = offerFromOlderPeer(distinct)
local requested
for _, packet in ipairs(wire) do
    if packet.message:find("CACHE_GET\t8\t" .. distinctRequest .. "\t", 1, true) then requested = true end
end
assert(requested, "the same guild name and timestamp alone cannot suppress a different snapshot")
assert(findGuild(receiver, known.guildName).serverName == "Known Realm", "comparison never rewrites the saved origin")
print("PASS: older-peer refreshes recognize identical snapshots without merging guild origins")

-- Real realm names still distinguish guilds on clients that use them.
clients, timers, wire = {}, {}, {}
local realms = client("Realm Reporter", false, false, false)
function realms.addon:IsForeverClient() return false end
for _, realm in ipairs({ "First Realm", "Second Realm" }) do
    local snapshot = report(realms, "Matching Name")
    snapshot.serverName = realm
    assert(realms.grid:StoreGuildReport(snapshot, true, true))
end
assert(#realms.addon:GetGlobalRaceOverview() == 2, "distinct real realms are not combined")

clients, timers, wire = {}, {}, {}
local repair = client("Local Reporter", false, false, false)
local knownRules = report(repair, "Home Guild")
knownRules.name, knownRules.guid = "Informed Member", "Player-1-Informed"
knownRules.serverName, knownRules.timestamp = "CAMWOW EU4 Realm 6 PvE", repair.env.time() - 20
knownRules.rules = { guildFoundOnly = true }
assert(repair.grid:StoreGuildReport(knownRules, true, true))
local store = repair.env.iRCDB.globalRaceGrid.servers["forever:" .. repair.addon:GetGuildDirectoryScope()]
store.guildReports["home guild@camwow eu4 realm 6 pve"] = knownRules
store.guildReports["home guild"] = nil
local bootstrap = report(repair, "Home Guild")
bootstrap.name, bootstrap.guid = "Uninformed Member", "Player-1-Uninformed"
bootstrap.serverName, bootstrap.timestamp = "CAMWOW EU4 Realm 7 PvE", repair.env.time() - 10
bootstrap.rulesKnown, bootstrap.rules = false, {}
local serializer = upvalue(repair.grid.BroadcastReport, "serializeGuildReport")
local parsedBootstrap = assert(parsePayload(serializer(bootstrap, true)))
assert(parsedBootstrap.rulesKnown == false and parsedBootstrap.rules == nil)
assert(parsePayload(serializer(parsedBootstrap, true)).rulesKnown == false,
    "an unknown-rules report retains its marker through cache relaying")
store.guildReports["home guild@camwow eu4 realm 7 pve"] = parsedBootstrap
local directory = repair.addon:GetGlobalRaceOverview()
assert(#directory == 1 and directory[1].timestamp == bootstrap.timestamp,
    "old realm-labelled duplicates collapse to the newest stats without deleting the cache")
assert(directory[1].rulesKnown and directory[1].rules.guildFoundOnly,
    "a bootstrap report cannot erase the previous Guild-Found tag")
assert(store.guildReports["home guild@camwow eu4 realm 6 pve"], "older cached entries are preserved")
local own = report(repair, "Home Guild")
own.serverName, own.rulesKnown, own.rules = "Forever", false, {}
function repair.grid:BuildOwnGuildReports() return { own } end
directory = repair.addon:GetGuildDirectoryOverview("NAME")
assert(#directory == 1 and directory[1] == own and own.rules.guildFoundOnly,
    "the live own-guild report replaces its cached aliases and keeps known challenge rules")
local confirmedChange = report(repair, "Home Guild")
confirmedChange.timestamp, confirmedChange.serverName = own.timestamp + 1, "CAMWOW EU4 Realm 8 PvE"
assert(repair.grid:StoreGuildReport(confirmedChange, true, true))
directory = repair.addon:GetGuildDirectoryOverview("NAME")
assert(#directory == 1 and directory[1].rules.guildFoundOnly ~= true,
    "a later known-rules report can genuinely remove Guild-Found")

local classKnown = report(repair, "Class Guild")
classKnown.rules = { classLock = true, guildClass = "MAGE" }
assert(repair.grid:StoreGuildReport(classKnown, true, true))
local classBootstrap = report(repair, "Class Guild")
classBootstrap.name, classBootstrap.guid = "Uninformed Member", "Player-1-Uninformed"
classBootstrap.timestamp, classBootstrap.rulesKnown, classBootstrap.rules = classKnown.timestamp + 1, false, {}
assert(repair.grid:StoreGuildReport(classBootstrap, true, true))
local details = { "GUILD_CLASS_BREAKDOWN", "8", classBootstrap.timestamp, "ALL", 1, 60,
    6, 0, 0, 0, 0, 0, 0, 0, 0, "NORMAL", "0", "", "", "", "", "@" .. repair.addon:GetGuildDirectoryScope() }
repair.frame.OnEvent(repair.frame, "CHAT_MSG_ADDON", "iRCGridV1", table.concat(details, "\t"), "GUILD", classBootstrap.name)
local restoredClass = findGuild(repair, "Class Guild")
assert(restoredClass.rules.classLock and restoredClass.rules.guildClass == "MAGE",
    "bootstrap detail packets cannot overwrite inherited Class-Locked rules")
print("PASS: Forever duplicate repair, live own-guild replacement, preserved challenge tags, unknown-rules relays and confirmed rule changes")
