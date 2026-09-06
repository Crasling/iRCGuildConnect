-- Run from the addon directory with a Lua interpreter; no game or network writes.
local nativeCachePath = ... -- Optional read-only integration test against WoW saved variables.
local now, epoch, rank, level, sf, money = 1000, 1800000000, 0, 60, true, 10000
local sent, chat, timers, frames, loaded = {}, {}, {}, {}, {}
local hardwareClick = false
local function click(callback)
    hardwareClick = true
    callback()
    hardwareClick = false
end
local rows = {
    { name = "Tester", race = "Troll", class = "MAGE", level = 60, hardcorePoints = 100 },
    { name = "Peer", race = "Troll", class = "WARRIOR", level = 30, hardcorePoints = 50, profile = { hardcorePoints = 50, lastSeen = epoch + now } },
    { name = "Master", race = "Troll", class = "PRIEST", level = 60, hardcorePoints = 200, profile = { hardcorePoints = 200, lastSeen = epoch + now } },
}
local members = { tester = true, peer = true, master = true }
function time() return epoch + math.floor(now) end
function GetTime() return now end
function GetMoney() return money end
function GetBuildInfo() return "1.15.9", "1", "", 11509 end
function UnitLevel() return level end
function UnitRace() return "Troll", "Troll" end
function UnitName() return "Tester" end
function GetUnitName() return "Tester-Soulseeker" end
function UnitGUID() return "Player-1-Tester" end
function GetRealmName() return "Soulseeker" end
function GetGuildInfo() return "Darkspear Tribe", "Rank", rank end
function UnitBuff(_, index) if sf and index == 1 then return "Self Found", nil, nil, nil, nil, nil, nil, nil, nil, 431567 end end
function GetChannelName(name) return name == "RaceLockedDataBus" and 4 or (name == "RaceLockedForkEUDataBus" and 5 or 6) end
function JoinChannelByName() end
function SendChatMessage(...)
    if select(2, ...) == "CHANNEL" then assert(hardwareClick, "protected CHANNEL send outside hardware click") end
    chat[#chat + 1] = { ... }
end
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() end,
    SendAddonMessage = function(...) sent[#sent + 1] = { ... } end,
}
C_AddOns = { IsAddOnLoaded = function(name) return loaded[name] or false end }
C_Timer = {
    After = function(delay, callback) timers[#timers + 1] = { at = now + delay, callback = callback } end,
    NewTicker = function() return { Cancel = function() end } end,
}
local function advance(seconds)
    local target = now + seconds
    while true do
        table.sort(timers, function(a, b) return a.at < b.at end)
        if not timers[1] or timers[1].at > target then break end
        local timer = table.remove(timers, 1)
        now = timer.at
        timer.callback()
    end
    now = target
end
function CreateFrame()
    local frame = { RegisterEvent = function() end, SetScript = function(self, event, func) self[event] = func end }
    frames[#frames + 1] = frame
    return frame
end
local addon = {}
function LibStub(name)
    if name == "AceAddon-3.0" then return { NewAddon = function() return addon end } end
end
local private = {}
assert(loadfile("iRacelockConnection_Core.lua"))("iRacelockConnection", private)
assert(loadfile("iRacelockConnection_Localization_enUS.lua"))("iRacelockConnection", private)
local iRC = private.iRC
iRCDB, iRCCharDB = {}, {}
assert(iRC:IsGuildMaster(), "real rank 0 must be recognized")
rank = 1; assert(iRC:IsGuildAdmin() and not iRC:IsGuildMaster()); rank = 0
function iRC:IsGuildMemberName(name) return members[self:NormalizeName(name)] == true end
function iRC:IsGuildMasterName(name) return self:NormalizeName(name) == "master" end
function iRC:GetHardcoreAchievementPoints() return 100 end
function iRC:GetGuildRosterRows() return rows end
function iRC:GetLocalProfile() return { name = "Tester-Soulseeker", guid = "Player-1-Tester", race = "Troll", class = "MAGE", level = level, points = 999, hardcorePoints = 100 } end
function iRC:FindConnectionProfile() return nil end
function iRC:DebugMsg() end
function iRC:Print() end
local db = iRC:GetConnection()
db.active = true
assert(loadfile("iRacelockConnection_Compatibility.lua"))("iRacelockConnection", private)
local compatFrame = frames[#frames]
assert(loadfile("iRacelockConnection_RaceLockedSync.lua"))("iRacelockConnection", private)
local syncFrame, sync = frames[#frames], iRC.RaceLockedSync
assert(loadfile("iRacelockConnection_RaceGrid.lua"))("iRacelockConnection", private)
local gridFrame, grid = frames[#frames], iRC.RaceGrid
sync:ValidateMoney()
sync:Broadcast()
assert(sync:GetStatus("Tester").verified and sync:GetStatus("Tester").clean)
sync:ReceiveRoster("S:Peer,1,1,0", "Peer")
assert(sync:GetStatus("Peer").verified)
sync:ReceiveRoster("S:Peer,0,0,0", "Master")
assert(sync:GetStatus("Peer").verified, "reject forged self-report")
sync:ReceiveRoster("G:Peer,0,0," .. time(), "Peer")
assert(sync:GetStatus("Peer").verified, "reject non-GM direct override")
local stamp = time()
sync:ReceiveRoster("G:Peer,1,0," .. stamp, "Master")
assert(sync:GetStatus("Peer").clean == false, "false override survives decoding")
sync:ReceiveRoster("O:Peer,1,1," .. (stamp - 1), "Tester")
assert(sync:GetStatus("Peer").clean == false, "old relay cannot replace newer decision")
advance(2)
sync:ReceiveRoster("G:Peer,-,-," .. time(), "Master")
assert(sync:GetStatus("Peer").clean == true, "reset returns to raw status")
advance(2)
sync:ReceiveRoster("O:Peer,1,1," .. time(), "Tester")
assert(not sync:GetStatus("Peer").directOverride, "relays retain unconfirmed origin")
advance(2)
sync:ReceiveRoster("S:Peer,1,0," .. time(), "Peer")
assert(sync:GetStatus("Peer").clean == false, "new discrepancy beats older clean override")
local beforeRelay = #sent
advance(5)
assert(#sent > beforeRelay and sent[#sent][2]:sub(1, 2) == "O:", "missing badge gets delayed relay")
advance(1)
sync:ReceiveRoster("G:Peer,1,1," .. time(), "Master")
assert(iRC:GetGuildFoundTradeStatus("Peer") == true)
iRCCharDB.guildFoundHistory.moneyDiscrepancyAt = time() + 1
sf = false
assert(iRC:GetGuildFoundTradeStatus("Peer") == false, "own discrepancy blocks trading")
iRCCharDB.guildFoundHistory.moneyDiscrepancyAt = nil
iRC:RequestRaceLockedTradeVerification("Peer-Soulseeker")
assert(sent[#sent][3] == "WHISPER" and sent[#sent][4] == "Peer-Soulseeker", "whisper keeps recipient")
assert(sync:RecordDeath("Peer"))
assert(not sync:RecordDeath("Peer"), "same-client duplicate death ignored")
assert(db.raceDeaths.TROLL == 1)
local before = #sent
loaded.RaceLocked = true
advance(6); sync:Broadcast()
assert(#sent == before, "original addon owns outgoing protocol when coinstalled")
loaded.RaceLocked = false
db.active = false
before = #sent
sync:Broadcast(); sync:ReceiveRoster("S:Peer,0,0,0", "Peer")
assert(#sent == before and db.guildFoundRoster.peer.verified == true, "inactive guild does not sync")
db.active = true

local report = {
    race = "TROLL", guildName = "Darkspear Tribe", members = 3, averageLevel = 50,
    points = 300, classes = { MAGE = 1, WARRIOR = 1, PRIEST = 1 },
    classAverageLevels = { MAGE = 60, WARRIOR = 30, PRIEST = 60 },
    guildDeaths = 7, membersLevel60 = 2, timestamp = time(),
}
local originalWire = assert(grid:EncodeExternalReport(report, "RaceLockedDataBus"))
local forkWire = assert(grid:EncodeExternalReport(report, "RaceLockedForkEUDataBus"))
local original = assert(grid:ParseExternalReport(originalWire, "RaceLockedDataBus"))
local fork = assert(grid:ParseExternalReport(forkWire, "RaceLockedForkEUDataBus"))
assert(original.points == 300 and original.membersLevel60 == 2 and original.guildDeaths == 7)
assert(original.classAverageLevels.WARRIOR == 30 and fork.classes.WARRIOR == 1)
assert(fork.points == 300 and fork.membersLevel60 == nil and fork.guildDeaths == nil)
assert(grid:StoreRaceLockedGuildReport(original))
local saved = iRCDB.globalRaceGrid.raceLockedGuildReports["TROLL@darkspear tribe"]
fork.timestamp = original.timestamp - 50
assert(not grid:StoreRaceLockedGuildReport(fork))
assert(saved.lastSeen == original.timestamp, "stale relay does not refresh age")
local wrong = {}; for k, v in pairs(report) do wrong[k] = v end
wrong.guildName = "Wrong guild"
assert(grid:EncodeExternalReport(wrong, "RaceLockedDataBus") == nil)
local own = grid:BuildOwnGuildReports()[1]
assert(own.points == 0 and own.members == 3 and own.membersLevel60 == 2)
local overview = iRC:GetRaceGridOverview()[1]
assert(overview.members == 3 and overview.points == 0, "achievement statistics are disabled")
local peerProfile = rows[2].profile
rows[2].profile = nil
assert(grid:BuildOwnGuildReports()[1].points == 0, "RaceLocked fallback row AP must not count")
rows[2].profile = { points = 9999 }
assert(grid:BuildOwnGuildReports()[1].points == 0, "profile points must not enter paused statistics")
rows[2].profile = peerProfile

-- Login, timers and network requests must never perform protected CHANNEL sends.
iRC:GetSettings().shareGlobalRaceGrid = true
gridFrame.OnEvent(nil, "PLAYER_LOGIN")
advance(12)
assert(#chat == 0, "login does not send protected channel chat")
gridFrame.OnEvent(nil, "CHAT_MSG_ADDON", "iRCGridV1", "REQUEST\t1", "CHANNEL", "Peer-Soulseeker")
grid:BroadcastExternalReports(); grid:RequestReports(); grid:BroadcastReport()
advance(3)
assert(#chat == 0, "network requests and non-click callers cannot send channel chat")
click(function() grid:PublishFromClick() end)
local externalCount = 0
for _, packet in ipairs(chat) do if packet[4] == 4 or packet[4] == 5 then externalCount = externalCount + 1 end end
assert(externalCount == 2, "one native snapshot on each external bus")
for _, packet in ipairs(chat) do assert(#packet[1] <= 255 and packet[2] == "CHANNEL") end
local chatCount = #chat
click(function() grid:BroadcastExternalReports(true) end); advance(3)
assert(#chat == chatCount, "broadcast cooldown")
loaded.RaceLocked, loaded.RaceLockedForkEU = true, true
advance(121); click(function() grid:BroadcastExternalReports(true) end); advance(10)
assert(#chat == chatCount, "native addons prevent duplicate external publication")

-- Independent native parsers prove compatibility, not just our own round trips.
local nativeRoot = "../Other/RaceLockedStuff from Curseforge/"
function strsplit(separator, value)
    local fields = {}
    for field in (value .. separator):gmatch("(.-)" .. separator) do fields[#fields + 1] = field end
    return table.unpack(fields)
end
assert(loadfile(nativeRoot .. "RaceLocked/Functions/Comms/Utils/WireCodec.lua"))()
local nativeOriginal = RaceLocked_GuildChampion.Comms.ParsePayload(originalWire)
assert(nativeOriginal.guildDeaths == 7 and nativeOriginal.guildAchievementsAverage == 100 and nativeOriginal.guildMembersLevel60 == 2)
assert(loadfile(nativeRoot .. "RaceLockedForkEU/Functions/Comms/Utils/WireCodec.lua"))()
local nativeFork = RaceLockedForkEU_GuildChampion.Comms.ParsePayload(forkWire)
assert(nativeFork.totalAP == 300 and nativeFork.classes.warriors == 1)
local function nativeWire(comms, value)
    return comms.PREFIX .. ":" .. comms.BytesToHex(comms.BuildPayload("Troll", value))
end
assert(grid:ParseExternalReport(nativeWire(RaceLocked_GuildChampion.Comms, nativeOriginal), "RaceLockedDataBus").guildDeaths == 7)
assert(grid:ParseExternalReport(nativeWire(RaceLockedForkEU_GuildChampion.Comms, nativeFork), "RaceLockedForkEUDataBus").points == 300)
local function wireFields(fields)
    return "RLRaceGridV1:" .. RaceLocked_GuildChampion.Comms.BytesToHex(table.concat(fields, string.char(1)))
end
local simple = { "v1", "Troll", "Darkspear Tribe", "3", "50", "0", "0", "0", "1", "1", "1", "0", "0", "0" }
assert(grid:ParseExternalReport(wireFields(simple), "RaceLockedDataBus").members == 3)
simple[1], simple[15] = "v2", tostring(time())
assert(grid:ParseExternalReport(wireFields(simple), "RaceLockedForkEUDataBus").timestamp == time())
simple[4] = "-1"
assert(grid:ParseExternalReport(wireFields(simple), "RaceLockedDataBus") == nil)
simple[4], simple[3] = "3", "Wrong guild"
assert(grid:ParseExternalReport(wireFields(simple), "RaceLockedDataBus") == nil)
local paired = { strsplit(string.char(1), RaceLocked_GuildChampion.Comms.HexToBytes(originalWire:match(":(.+)$"))) }
paired[1], paired[27], paired[26] = "v4", nil, nil
assert(grid:ParseExternalReport(wireFields(paired), "RaceLockedDataBus").guildDeaths == 7)
paired[1], paired[25] = "v3", nil
assert(grid:ParseExternalReport(wireFields(paired), "RaceLockedDataBus").classAverageLevels.MAGE == 60)

loaded.RaceLocked, loaded.RaceLockedForkEU = false, false
local externalReport = {}; for key, value in pairs(report) do externalReport[key] = value end
externalReport.race, externalReport.guildName, externalReport.timestamp = "NIGHTELF", "Children of Elune", time()
local relayWire = assert(grid:EncodeExternalReport(externalReport, "RaceLockedForkEUDataBus"))
gridFrame.OnEvent(nil, "CHAT_MSG_CHANNEL", relayWire, "External", nil, nil, nil, nil, nil, 5, "RaceLockedForkEUDataBus")
local combined = iRC:GetRaceGridOverview()
assert(#combined == 2, "local and external hardcoded guild slots coexist")
local relayBefore = #chat
advance(121); click(function() grid:BroadcastExternalReports(true) end); advance(10)
assert(#chat == relayBefore + 3, "two own snapshots and one unchanged native relay")
local exactRelay = false
for index = relayBefore + 1, #chat do if chat[index][1] == relayWire then exactRelay = true end end
assert(exactRelay, "relay retains original packet and timestamp")
rows[2].profile = { shareGlobalRaceGrid = true, lastSeen = time(), hardcorePoints = 50 }
rows[2].online = true
assert(not grid:IsExternalBroadcaster(), "one live sharing client elected per guild")
rows[2].profile = peerProfile
assert(grid:IsExternalBroadcaster())

-- Co-installed native data predates our login; retain population snapshots,
-- but never use their AP, including for our own guild.
iRCDB.globalRaceGrid.raceLockedGuildReports = {}
local oldStamp = time() - 4000
local cache = {
    Troll = {{ guildName = "Darkspear Tribe", guildSize = 630, averageLevel = 14, totalAP = 11098, timestamp = oldStamp, classes = { warriors = 100 } }},
    Scourge = {{ guildName = "WE are FORSAKEN", guildSize = 10, averageLevel = 30, totalAP = 18162, timestamp = oldStamp, classes = { priests = 10 } }},
    Tauren = {{ guildName = "Wrong guild", guildSize = 20, averageLevel = 30, totalAP = 99, timestamp = time() }},
    Human = {{ guildName = "Northshire Survivors", guildSize = 0, averageLevel = 0, totalAP = 0, timestamp = 0 }},
}
RaceLockedForkEUAccountDB = { raceGridStoredGuildReportsByRace = cache }
loaded.RaceLockedForkEU = true
local byRace = {}
for _, group in ipairs(iRC:GetRaceGridOverview()) do byRace[group.race] = group end
assert(byRace.TROLL.points == 0 and byRace.TROLL.members == 3, "own verified/compatible count replaces native population without AP")
assert(byRace.SCOURGE.points == 0 and byRace.SCOURGE.averagePoints == nil and byRace.SCOURGE.cached and byRace.SCOURGE.timestamp == oldStamp)
assert(not byRace.TAUREN and not byRace.HUMAN, "wrong guild and empty native placeholders excluded")
byRace.SCOURGE.classes.PRIEST = 0
assert(cache.Scourge[1].classes.priests == 10 and cache.Scourge[1].timestamp == oldStamp, "native cache never mutated")
-- Prefer current in-memory native reports over its saved-table snapshot.
local liveRow = { guildName = "WE are FORSAKEN", guildSize = 11, averageLevel = 31, totalAP = 19000, timestamp = time(), classes = { priests = 11 } }
RaceLockedForkEU_GuildChampion.RACE_GRID_STORED_GUILD_REPORTS_BY_RACE = { Scourge = { liveRow } }
byRace = {}; for _, group in ipairs(iRC:GetRaceGridOverview()) do byRace[group.race] = group end
assert(byRace.SCOURGE.points == 0 and byRace.SCOURGE.members == 11 and not byRace.SCOURGE.cached, "even live native AP is excluded")
-- Achievement fields in iRC reports remain ignored while statistics are paused.
local function publicReport(name, points, guild)
    local fields = { "REPORT", "1", name, "Player-1-" .. name, "SCOURGE", "PRIEST", "30", tostring(points), guild or "WE are FORSAKEN", "1", "UNVERIFIED" }
    gridFrame.OnEvent(nil, "CHAT_MSG_ADDON", "iRCGridV1", table.concat(fields, "\t"), "CHANNEL", name)
end
publicReport("UndeadOne-Soulseeker", 120)
publicReport("UndeadOne-Soulseeker", 150)
publicReport("UndeadTwo-Soulseeker", 50)
publicReport("WrongGuild-Soulseeker", 9999, "Wrong guild")
byRace = {}; for _, group in ipairs(iRC:GetRaceGridOverview()) do byRace[group.race] = group end
assert(byRace.SCOURGE.points == 0 and byRace.SCOURGE.members == 11, "individual iRC AP is ignored while achievement statistics are paused")
assert(byRace.SCOURGE.averagePoints == nil, "average AP remains disabled")
loaded.RaceLockedForkEU = false
advance(2000)
byRace = {}; for _, group in ipairs(iRC:GetRaceGridOverview()) do byRace[group.race] = group end
assert(byRace.SCOURGE.points == 0 and byRace.SCOURGE.cached, "expired iRC AP never falls back to retained native points")
-- Original RaceLocked uses class tables and average AP, not ForkEU's total AP.
loaded.RaceLocked = true
RaceLocked_GuildChampion.RACE_GRID_STORED_GUILD_REPORTS_BY_RACE = {
    Tauren = {{ guildName = "Fear The Beef", guildSize = 5, averageLevel = 20, guildAchievementsAverage = 100, guildDeaths = 3, guildMembersLevel60 = 1, timestamp = time(), classes = { warriors = { count = 5, averageLevel = 20 } } }},
}
byRace = {}; for _, group in ipairs(iRC:GetRaceGridOverview()) do byRace[group.race] = group end
assert(byRace.TAUREN.points == 0 and byRace.TAUREN.averagePoints == nil and byRace.TAUREN.guildDeaths == 3 and byRace.TAUREN.classAverageLevels.WARRIOR == 20)
local protectedBefore = #chat
grid:Refresh(); advance(12)
assert(#chat == protectedBefore, "refresh timers only read data")
loaded.RaceLocked = false

-- Recreate just the sync module to exercise a real reload boundary and persisted gold.
money = money + 25
assert(loadfile("iRacelockConnection_RaceLockedSync.lua"))("iRacelockConnection", private)
sync = iRC.RaceLockedSync
sync:ValidateMoney()
assert(iRCCharDB.guildFoundHistory.moneyDiscrepancyAt == time(), "changed gold flags at login")
local discrepancyAt = time()
advance(2)
assert(sync:SetOverride("Tester", true, true))
assert(sync:GetStatus("Tester").clean == true, "GM can clear an earlier incident")
iRCCharDB.guildFoundHistory.moneyDiscrepancyAt = time() + 1
assert(sync:GetStatus("Tester").clean == false, "new incident beats GM approval")
sf = true; sync:ObserveSelfFound()
assert(iRCCharDB.guildFoundHistory.moneyDiscrepancyAt == nil, "active game SF clears false discrepancy")
if nativeCachePath then
    local savedEnvironment = {}
    assert(loadfile(nativeCachePath, "t", savedEnvironment))()
    RaceLockedForkEUAccountDB = assert(savedEnvironment.RaceLockedForkEUAccountDB)
    RaceLockedForkEU_GuildChampion.RACE_GRID_STORED_GUILD_REPORTS_BY_RACE = nil
    loaded.RaceLocked, loaded.RaceLockedForkEU = false, true
    iRCDB.globalRaceGrid.raceLockedGuildReports = {}
    local imported = {}
    for _, group in ipairs(iRC:GetRaceGridOverview()) do imported[group.guildName] = group end
    local count = 0
    for _, guilds in pairs(RaceLockedForkEUAccountDB.raceGridStoredGuildReportsByRace) do
        for _, guild in ipairs(guilds) do
            if guild.guildSize > 0 then
                local group = assert(imported[guild.guildName], "saved native guild missing in iRC")
                if group.race == "TROLL" then
                    assert(group.members == 3 and group.populationSource == "verified_compatible", "own participation count ignores native total")
                else
                    assert(group.members == guild.guildSize and group.timestamp == guild.timestamp)
                    assert(group.averageLevel == math.floor(guild.averageLevel * 10 + 0.5) / 10, "preserve native fractional averages")
                end
                assert(group.points == 0 and group.averagePoints == nil, "achievement statistics stay disabled for all guilds")
                count = count + 1
            end
        end
    end
    assert(count > 0)
    print("Read-only saved-variable test passed: " .. count .. " guild snapshots checked; own participant count protected, external populations retained, all native AP excluded.")
end
print("RaceLocked sync tests passed: roster, overrides, clean state, deaths, codecs, deduplication, activation and coexistence.")
