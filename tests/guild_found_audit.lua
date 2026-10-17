-- Guild Found applicability and delegated audit replay regressions.
local now, player = 1800000000, "Recorder Test"
local sent, frames = {}, {}
local roster = {
    { name = "Recorder Test", rank = 5 },
    { name = "Review Officer", rank = 2 },
    { name = "Ordinary Member", rank = 5 },
}

function time() return now end
function GetTime() return now end
function GetBuildInfo() return "1.60.1", "70374", "", 16001 end
function GetRealmName() return "Soulseeker" end
function GetUnitName() return player end
function UnitName() return player:match("^(%S+)%s*(.*)$") end
function UnitGUID() return "Player-1-" .. player end
function UnitLevel() return 10 end
function UnitRace() return "Troll", "TROLL" end
function UnitClass() return "Warrior", "WARRIOR" end
function GetNumGuildMembers() return #roster end
function GetGuildRosterInfo(index)
    local row = roster[index]
    return row.name, "Rank", row.rank, 10, "Warrior", nil, nil, nil, true,
        nil, "WARRIOR", nil, nil, nil, nil, nil, "Player-1-" .. row.name
end
function GetGuildInfo() return "Audit Guild", "Rank", 5 end
function CreateFrame()
    local frame = { RegisterEvent = function() end, SetScript = function(self, key, callback) self[key] = callback end }
    frames[#frames + 1] = frame
    return frame
end

local addon, private = {}, {}
function LibStub() return { NewAddon = function() return addon end } end
C_ChatInfo = { SendAddonMessage = function(...) sent[#sent + 1] = { ... } end }

assert(loadfile("iRC_Core.lua"))("iRC", private)
assert(loadfile("Localization/enUS.lua"))("iRC", private)
assert(loadfile("iRC_Guild.lua"))("iRC", private)
assert(loadfile("iRC_Connection.lua"))("iRC", private)
local iRC = private.iRC
iRCDB, iRCCharDB = {}, {}
iRC.Frame.OnEvent(nil, "ADDON_LOADED", iRC.Name)
local db = assert(iRC:GetConnection())
db.active, db.rulesBootstrap = true, false
db.rules.selfFoundOnly, db.rules.guildFoundOnly, db.rules.level60GuildFound = false, false, true
db.rankPermissions.incidents = 2
function iRC:GetSelfFoundState() return false end
function iRC:DebugMsg() end

assert(iRC:IsGuildFoundEconomyActive(),
    "hybrid characters without Self-Found use Guild-Found protection below level 60")
assert(iRC:RecordGuildFoundAudit("MAIL_BLOCKED", "Outside"),
    "active hybrid protection records its audit events")
assert(sent[#sent] and sent[#sent][2]:match("^GF_AUDIT\t10\t"),
    "hybrid audit evidence is shared: " .. tostring(sent[#sent] and sent[#sent][2]))

db.guildFoundAudit = {}
for index = 1, 50 do
    iRC:StoreGuildFoundAudit({
        id = "audit-" .. index,
        player = index % 2 == 0 and "Recorder Test" or "Other Person",
        occurredAt = now - index,
        action = "MAIL_BLOCKED",
        target = "Target" .. index,
    })
end
sent = {}
assert(iRC:GuildMemberHasPermission("Review Officer", "incidents"),
    "rank 2 reviewer has delegated incident permission")
assert(iRC:UploadGuildFoundAudit("Review Officer"),
    "delegated incident reviewers receive audit history")
assert(#sent == 20, "audit replay searches all recent records and caps matching records at 20")
for _, packet in ipairs(sent) do
    assert(packet[3] == "WHISPER" and packet[4] == "Review Officer",
        "audit history is whispered only to the delegated reviewer")
end
sent = {}
assert(not iRC:UploadGuildFoundAudit("Ordinary Member") and #sent == 0,
    "members without incident permission never receive audit history")

print("Guild Found audit tests passed: shared applicability, delegated review, filtering, and replay cap.")
