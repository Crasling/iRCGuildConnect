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
local serverStore = iRCDB.globalRaceGrid.servers.soulseeker
local saved = serverStore.raceLockedGuildReports["TROLL@darkspear tribe"]
fork.timestamp = original.timestamp - 50
assert(not grid:StoreRaceLockedGuildReport(fork))
assert(saved.lastSeen == original.timestamp, "stale relay does not refresh age")
local wrong = {}; for k, v in pairs(report) do wrong[k] = v end
wrong.guildName = "Wrong guild"
assert(grid:EncodeExternalReport(wrong, "RaceLockedDataBus"), "native compatibility encoding no longer uses a hardcoded guild allowlist")
local own = grid:BuildOwnGuildReports()[1]
assert(own.points == 0 and own.members == 3 and own.membersLevel60 == 2)
assert(own.rulesKnown and type(own.rules) == "table", "live iRC guild snapshots include current rule metadata")
rows[4] = { name = "Lowbie", race = "Troll", class = "ROGUE", level = 18 }
members.lowbie = true
local filteredClasses = grid:BuildOwnGuildReports()[1]
assert(filteredClasses.members == 4 and filteredClasses.classes.ROGUE == nil, "class breakdown excludes characters below level 19")
rows[4], members.lowbie = nil, nil
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
assert(grid:ParseExternalReport(wireFields(simple), "RaceLockedDataBus"), "native reports accept dynamic guild names")
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
assert(#combined == 1, "native reports cannot create guild cards without an iRC guild report")
local relayBefore = #chat
advance(121); click(function() grid:BroadcastExternalReports(true) end); advance(10)
assert(#chat == relayBefore + 2, "only current own snapshots are sent; cached native data is never relayed")
local exactRelay = false
for index = relayBefore + 1, #chat do if chat[index][1] == relayWire then exactRelay = true end end
assert(not exactRelay, "cached native reports are display-only")
rows[2].profile = { shareGlobalRaceGrid = true, lastSeen = time(), hardcorePoints = 50 }
rows[2].online = true
assert(not grid:IsExternalBroadcaster(), "one live sharing client elected per guild")
rows[2].profile = peerProfile
assert(grid:IsExternalBroadcaster())

-- Dynamic guild snapshots are discovered only through iRC and ranked by
-- level-60 members, active players, total roster, then guild name.
serverStore.guildReports = {}
local function guildReport(name, guild, race, level60, active, total, stamp, ruleMask, sameRaceLevel, guildGroupsLevel)
    local fields = { "GUILD_REPORT", "2", name, "Player-1-" .. name, guild, race,
        tostring(level60), tostring(active), tostring(total), "30", tostring(stamp or time()), "0" }
    for index = 1, 9 do fields[#fields + 1] = tostring(index == 4 and total or 0) end
    if ruleMask ~= nil then
        fields[#fields + 1] = tostring(ruleMask)
        fields[#fields + 1] = tostring(sameRaceLevel or 1)
        fields[#fields + 1] = tostring(guildGroupsLevel or 1)
    end
    gridFrame.OnEvent(nil, "CHAT_MSG_ADDON", "iRCGridV1", table.concat(fields, "\t"), "CHANNEL", name)
end
guildReport("Elf-Soulseeker", "Moon Wardens", "NIGHTELF", 4, 2, 10)
guildReport("Orc-Soulseeker", "Warsong Vanguard", "ORC", 3, 9, 20, nil, 80, 50, 55)
guildReport("Human-Soulseeker", "Lion Guard", "HUMAN", 3, 8, 50)
guildReport("ElfTwo-Soulseeker", "Moon Wardens", "NIGHTELF", 4, 2, 11, time() + 1)
local ranked = iRC:GetRaceGridOverview()
assert(#ranked == 4 and ranked[1].guildName == "Moon Wardens" and ranked[1].members == 11, "same guild is deduplicated and newest iRC snapshot wins")
assert(ranked[2].guildName == "Warsong Vanguard" and ranked[3].guildName == "Lion Guard" and ranked[4].guildName == "Darkspear Tribe", "guild ranking is level60, active, then total")
assert(ranked[1].faction == "Alliance" and ranked[2].faction == "Horde", "guild race assigns the faction frame")
assert(ranked[1].rulesKnown == nil, "older iRC reports remain valid without rule metadata")
assert(ranked[2].rulesKnown and ranked[2].rules.sameRaceGroupsOnly and ranked[2].rules.guildGroupsOnly, "rule flags decode from new reports")
assert(ranked[2].rules.sameRaceMinimumLevel == 50 and ranked[2].rules.guildGroupsMinimumLevel == 55, "rule levels decode from new reports")

-- Native reports are retained for compatibility but cannot invent a Stats
-- guild that has never been announced through iRC.
assert(grid:StoreRaceLockedGuildReport({ race = "TAUREN", guildName = "Native Only", members = 99, averageLevel = 40, classes = {}, timestamp = time() }))
ranked = iRC:GetRaceGridOverview()
for _, group in ipairs(ranked) do assert(group.guildName ~= "Native Only") end
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
print("RaceLocked sync tests passed: roster, overrides, clean state, deaths, codecs, deduplication, activation and coexistence.")
