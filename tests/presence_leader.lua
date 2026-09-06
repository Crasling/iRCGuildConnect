-- Run from the addon directory. No game, network or saved-variable writes.
local now, player = 1800000000, "Crasjin"
local roster = {
    { name = "Crasjin", rank = 5, online = true },
    { name = "Aleader", rank = 0, online = true },
    { name = "Aofficer", rank = 1, online = true },
    { name = "Zofficer", rank = 1, online = true },
    { name = "Member", rank = 2, online = true },
    { name = "Jujukhan", rank = 5, online = true },
}
local frames, messages, debugMessages = {}, {}, {}
function time() return now end
function GetTime() return now end
function GetBuildInfo() return "1.15.9", "1", "", 11509 end
function GetRealmName() return "Soulseeker" end
function GetUnitName() return player .. "-Soulseeker" end
function UnitName() return player end
function UnitGUID() return "Player-1-" .. player end
function UnitLevel() return 10 end
function UnitRace() return "Troll", "Troll" end
function UnitClass() return "Warrior", "WARRIOR" end
function GetNumGuildMembers() return #roster end
function GetGuildRosterInfo(index)
    local row = roster[index]
    return row.name .. "-Soulseeker", "Rank", row.rank, 10, "Warrior", nil, nil, nil, row.online, nil, "WARRIOR", nil, nil, nil, nil, nil, row.guid or ("Player-1-" .. row.name)
end
function GetGuildInfo()
    for _, row in ipairs(roster) do if row.name == player then return "Darkspear Tribe", "Rank", row.rank end end
end
function CreateFrame()
    local frame = { RegisterEvent = function() end, SetScript = function(self, event, callback) self[event] = callback end }
    frames[#frames + 1] = frame
    return frame
end
local addon = {}
function LibStub() return { NewAddon = function() return addon end } end
C_ChatInfo = { SendAddonMessage = function(...) messages[#messages + 1] = { ... } end }
local private = {}
assert(loadfile("iRacelockConnection_Core.lua"))("iRacelockConnection", private)
assert(loadfile("iRacelockConnection_Localization_enUS.lua"))("iRacelockConnection", private)
assert(loadfile("iRacelockConnection_Guild.lua"))("iRacelockConnection", private)
assert(loadfile("iRacelockConnection_Connection.lua"))("iRacelockConnection", private)
local connectionFrame, iRC = frames[#frames], private.iRC
assert(iRC:IsTestAdminName("Crasling-Soulseeker"), "Crasling is an explicit test admin")
assert(iRC:IsTestAdminName("Crasjin-Soulseeker"), "Crasjin is an explicit test admin")
assert(not iRC:IsTestAdminName("Crasling-OtherRealm"), "test admin authority is realm-locked")
iRC.TestAdminName = "Crasjin-Soulseeker"
iRCDB, iRCCharDB = {}, {}
local db = iRC:GetConnection()
db.active = true
function iRC:DebugMsg(message) debugMessages[#debugMessages + 1] = message end
function iRC:GetSelfFoundEvidence() return { status = "UNVERIFIED" } end
function iRC:GetHardcoreAchievementPoints() return 0 end
function iRC:GetCompatibilityStats() return { source = "RaceLockedForkEU", lastSeen = now } end
local function profile(name, age, override)
    db.members[iRC:NormalizeName(name)] = { name = name, addonVersion = "0.2.4", lastSeen = now - (age or 0), testGuildMasterOverride = override }
end
local function expectLeader(name)
    local elected, actual = iRC:IsPresenceNotificationLeader()
    assert(actual == name .. "-Soulseeker", "unexpected leader: " .. tostring(actual))
    assert(elected == (player == name), "clients must agree on the same winner")
end

assert(not iRC:IsPresenceNotificationLeader(), "ordinary member cannot notify")
iRC:CheckPresenceMismatches()
assert(debugMessages[#debugMessages] == iRC:Text("PRESENCE_NOTIFICATION_INELIGIBLE"), "do not claim another leader when local rank is ineligible")
iRC:GetSettings().testGuildMasterOverride = true
assert(iRC:IsTestAdminGuildMaster())
expectLeader("Crasjin") -- GM is online with ForkEU, not iRC.
profile("Member", 0, true)
expectLeader("Crasjin") -- Arbitrary self-claimed test authority is ignored.
profile("Aleader")
expectLeader("Aleader") -- Fresh actual GM + iRC wins the rank/name tie.
iRC:CheckPresenceMismatches()
assert(debugMessages[#debugMessages]:find("Aleader-Soulseeker", 1, true), "debug names the actual iRC leader")
now = now + 200
profile("Aleader", 136)
expectLeader("Crasjin") -- Expired iRC profile plus fresh ForkEU must not qualify.
profile("Aleader", 201)
expectLeader("Crasjin") -- Previous-session profile must not qualify.
profile("Aleader", -1)
expectLeader("Crasjin") -- Future timestamps cannot qualify.
profile("Aleader")
roster[2].online = false
expectLeader("Crasjin") -- Offline GM cannot qualify even with fresh iRC data.
roster[2].online = true
db.members.aleader = nil

-- Actual HELLO serialization/deserialization conveys enabled AND disabled
-- test admin state, so peers use the same effective role as the test client.
iRC:SendHello()
local packet = messages[#messages]
db.members.crasjin = nil
connectionFrame.OnEvent(nil, "CHAT_MSG_ADDON", packet[1], packet[2], "GUILD", "Crasjin-Soulseeker")
assert(db.members.crasjin == nil, "self-sent guild packets are ignored")
player = "Zofficer"
connectionFrame.OnEvent(nil, "CHAT_MSG_ADDON", packet[1], packet[2], "GUILD", "Crasjin-Soulseeker")
assert(db.members.crasjin.testGuildMasterOverride == true)
expectLeader("Crasjin")
player = "Crasjin"
iRC:GetSettings().testGuildMasterOverride = false
iRC:SendHello()
packet = messages[#messages]
db.members.crasjin = nil
player = "Zofficer"
connectionFrame.OnEvent(nil, "CHAT_MSG_ADDON", packet[1], packet[2], "GUILD", "Crasjin-Soulseeker")
assert(db.members.crasjin.testGuildMasterOverride == false)
expectLeader("Zofficer")
profile("Jujukhan")
expectLeader("Zofficer") -- An ordinary member cannot gain authority by name.
roster[6].online = false
expectLeader("Zofficer")
profile("Aofficer"); profile("Zofficer")
expectLeader("Aofficer")
player = "Aofficer"
expectLeader("Aofficer") -- Exactly the same result on the other officer client.
db.active = false
assert(not iRC:IsPresenceNotificationLeader(), "inactive guild never elects a notifier")

-- Exercise actual guild roster -> Race Overview with offline characters whose
-- races are unavailable, mixed addon sources, duplicate rows and a departed member.
assert(loadfile("iRacelockConnection_RaceGrid.lua"))("iRacelockConnection", private)
db.active, player = true, "Crasjin"
roster[2].online, roster[3].online, roster[6].online = false, false, false
db.members = {
    aleader = { name = "Aleader", lastSeen = now - 5000, hardcorePoints = 30 },
    departed = { name = "Departed", lastSeen = now, hardcorePoints = 999 },
}
local compatibleMembers = {
    aleader = { stats = { lastSeen = now - 5000, points = 999 } },
    aofficer = { presence = { source = "RaceLockedForkEU", lastSeen = now - 5000 } },
    zofficer = { stats = { source = "RaceLockedForkEU", lastSeen = now, points = 999 } },
}
db.compatibilityMembers = compatibleMembers
function iRC:GetCompatibilityMember(name) return compatibleMembers[self:NormalizeName(name)] end
function iRC:GetCompatibilityStats(name)
    local member = self:GetCompatibilityMember(name)
    return member and member.stats
end
roster[#roster + 1] = roster[2] -- Same character must still only count once.
local group = assert(iRC.RaceGrid:BuildOwnGuildReports()[1])
assert(group.members == 6 and group.activePlayers == 3 and group.verifiedMembers == 2 and group.compatibleMembers == 2,
    string.format("guild snapshot totals: %s/%s/%s/%s", group.members, group.activePlayers, group.verifiedMembers, group.compatibleMembers))
assert(group.points == 0, "achievement statistics stay disabled")
assert(group.averageLevel == 10, "averages use the same participant population")
local classTotal = 0; for _, count in pairs(group.classes) do classTotal = classTotal + count end
assert(classTotal == 6, "class breakdown uses the full guild roster")
local native = { race = "TROLL", guildName = "Darkspear Tribe", members = 600, averageLevel = 30, points = 9999, classes = { WARRIOR = 600 }, timestamp = now }
assert(iRC.RaceGrid:StoreRaceLockedGuildReport(native))
group = assert(iRC:GetRaceGridOverview()[1])
assert(group.members == 6 and group.points == 0 and group.populationSource == "irc_guild_roster", "external data cannot overwrite the local iRC guild snapshot")
assert(iRC:GetMemberVerification("Aofficer", false).state == "offline", "live verification behavior remains unchanged")
db.members.member = { name = "Member", guid = "Player-1-Member", race = "Troll", lastSeen = now, addonVersion = "0.2.4" }
db.compatibilityMembers.member = { guid = "Player-1-Member", stats = { guid = "Player-1-Member", source = "RaceLockedForkEU", lastSeen = now } }
local sourceRows = iRC:GetGuildRosterRows()
local sourced
for _, row in ipairs(sourceRows) do if iRC:NormalizeName(row.name) == "member" then sourced = row break end end
assert(sourced and sourced.profile and not sourced.compatibility and sourced.source == "iRC", "fresh iRC suppresses the compatible source for the same character")
db.members.member.lastSeen = now - 136
db.compatibilityMembers.member.stats.lastSeen = now - 100
sourceRows = iRC:GetGuildRosterRows()
for _, row in ipairs(sourceRows) do if iRC:NormalizeName(row.name) == "member" then sourced = row break end end
assert(sourced and not sourced.profile and sourced.compatibility and sourced.source == "RaceLockedForkEU", "newer native data replaces and clears an expired iRC profile")
assert(db.members.member == nil, "expired iRC profile is removed from the connection cache after native takeover")
db.members.member = { name = "Member", guid = "Player-OLD-Member", race = "Troll", lastSeen = now }
db.compatibilityMembers.member = { guid = "Player-OLD-Member", stats = { guid = "Player-OLD-Member", source = "RaceLockedForkEU", lastSeen = now } }
db.guildFoundRoster = { member = { source = "RaceLocked", lastSeen = now } }
local identityRows = iRC:GetGuildRosterRows()
local recreated
for _, row in ipairs(identityRows) do if iRC:NormalizeName(row.name) == "member" then recreated = row break end end
assert(recreated and not recreated.profile and recreated.verification.state == "missing", "same-name character with a new GUID cannot inherit cached verification")
assert(db.members.member == nil and db.compatibilityMembers.member == nil and db.guildFoundRoster.member == nil, "all name-keyed identity caches are cleared after a GUID change")
assert(db.newMemberChecks["guid:Player-1-Member"], "a recreated character receives a new GUID-scoped confirmation check")
print("Race Overview population tests passed: verified + compatible, offline/unknown race, dual-source deduplication, departed/undetected exclusions and native overwrite protection.")
print("Presence leader tests passed: iRC-only officers, test overrides, fresh/session/offline checks, deterministic election and profile wire round trip.")

-- Large-guild regression: one roster read per member, constant connection
-- lookups, and no persistent cache hiding changes from subsequent passes.
assert(loadfile("iRacelockConnection_RaceLockedSync.lua"))("iRacelockConnection", private)
roster, db.members, db.compatibilityMembers, db.guildFoundRoster, db.hardcorePoints = {}, {}, {}, {}, {}
for index = 1, 1000 do
    local name = index == 1 and "Crasjin" or string.format("Member%04d", index)
    local key = iRC:NormalizeName(name)
    roster[index] = { name = name, rank = 5, online = index % 2 == 0 or index == 1 }
    if index % 3 == 0 then db.members[key] = { name = name, race = "Troll", lastSeen = now, hardcorePoints = 30 } end
    if index % 5 == 0 then db.compatibilityMembers[key] = { presence = { source = "RaceLockedForkEU", lastSeen = now } } end
    if index % 7 == 0 then db.guildFoundRoster[key] = { source = "RaceLocked", lastSeen = now, verified = true, clean = true } end
    if index % 11 == 0 then db.hardcorePoints[key] = { points = 20, directAt = now } end
end
local getConnection, getRoster = iRC.GetConnection, GetGuildRosterInfo
local connectionReads, rosterReads = 0, 0
function iRC:GetConnection() connectionReads = connectionReads + 1; return getConnection(self) end
function GetGuildRosterInfo(index) rosterReads = rosterReads + 1; return getRoster(index) end
local rosterRows = iRC:GetGuildRosterRows()
assert(#rosterRows == 1000 and rosterReads == 1000 and connectionReads <= 3, "large roster must use constant connection lookups")
db.compatibilityMembers.member0002 = { presence = { source = "RaceLockedForkEU", lastSeen = now } }
local refreshed = iRC:GetGuildRosterRows()
assert(refreshed[2].verification.state == "compatible", "next pass sees newly received presence immediately")
print("Large-guild test passed: 1000 members, " .. (connectionReads / 2) .. " connection lookup(s) per pass.")

-- Test the real visible-row renderer with lightweight WoW frame mocks.
unpack = table.unpack
local methods = {}
local function widget() return setmetatable({}, { __index = function(_, key) return methods[key] or function() end end }) end
function methods:CreateFontString() return widget() end
function methods:SetText(value) self.text = value end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetScript(event, callback) self[event] = callback end
function CreateFrame() return widget() end
assert(loadfile("iRacelockConnection_ConnectionDashboard.lua"))("iRacelockConnection", private)
local dashboard, offset, shown = iRC.ConnectionDashboard, 0, true
local view = { rows = {}, rowData = {}, content = widget(), scroll = {
    GetVerticalScroll = function() return offset end, GetHeight = function() return 360 end,
}, IsShown = function() return shown end }
dashboard.frame = view
for index = 1, 1000 do view.rowData[index] = { values = { tostring(index), "", "", "", "" } } end
dashboard:RenderVisibleRows()
assert(#view.rows == 7 and view.rows[1].columns[1].text == "1", "only visible rows plus one overscan row are created")
offset = 500 * 60
dashboard:RenderVisibleRows()
assert(#view.rows == 7 and view.rows[1].columns[1].text == "501", "scrolling reuses row frames with the correct data")
offset = 999 * 60
dashboard:RenderVisibleRows()
assert(view.rows[1].columns[1].text == "1000" and not view.rows[2].shown, "last page hides unused pooled rows")
local readsBefore = rosterReads
for _ = 1, 10 do dashboard:RenderVisibleRows() end
assert(rosterReads == readsBefore, "timer/scroll rendering never rebuilds the guild roster")

-- Exercise the full Verification Refresh, not just the renderer in isolation.
date = os.date
view.tab, view.tabs, view.filters, view.filterButtons = "Verification", {}, {}, {}
view.status, view.title, view.subtitle = widget(), widget(), widget()
view.headers, view.summaryCards = {}, {}
for index = 1, 5 do view.headers[index] = widget(); view.headers[index].text = widget() end
for index = 1, 4 do
    view.summaryCards[index] = widget()
    view.summaryCards[index].label, view.summaryCards[index].value = widget(), widget()
end
function view.scroll:SetVerticalScroll(value) offset = value end
local connectionBefore, rowsBefore = connectionReads, rosterReads
offset = 0
dashboard:Refresh()
assert(#view.rowData == 1000 and #view.rows == 7, "full verification refresh retains all data with bounded UI frames")
assert(rosterReads - rowsBefore == 1000 and connectionReads - connectionBefore <= 5, "full refresh avoids per-row connection lookups")
assert(view.rows[1].OnClick == view.rowData[1].onClick, "pooled row receives current click handler")
view.filters.Verification = "attention"
dashboard:Refresh()
assert(#view.rowData > 0 and #view.rowData < 1000, "filters still work with pooled rows")
local timerBefore, previousRosterReads = view.rows[1].columns[4].text, rosterReads
now = now + 60
dashboard:RenderVisibleRows()
assert(view.rows[1].columns[4].text ~= timerBefore and rosterReads == previousRosterReads, "attention timer advances without rebuilding the roster")

local callbacks, refreshes = {}, 0
C_Timer = { After = function(_, callback) callbacks[#callbacks + 1] = callback end }
function dashboard:Refresh() self.pendingRefresh = nil; refreshes = refreshes + 1 end
for _ = 1, 100 do dashboard:RefreshIfShown() end
assert(#callbacks == 1)
callbacks[1]()
assert(refreshes == 1, "100 rapid updates produce one dashboard redraw")
dashboard:RefreshIfShown(); dashboard:Refresh(); callbacks[2]()
assert(refreshes == 2, "manual refresh cancels the pending redraw")
dashboard:RefreshIfShown(); shown = false; callbacks[3]()
assert(refreshes == 2, "hidden windows skip queued work")
print("Dashboard performance tests passed: bounded row pool, scrolling, timer isolation and redraw coalescing.")
