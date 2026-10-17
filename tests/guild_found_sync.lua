-- Guild Found verification trust-boundary and packet-splitting regressions.
local now, player = 1800000000, "Self-Realm"
local sent = {}
local localCanVerify = false
local db = { active = true, key = "guild", guildFoundRoster = {}, raceDeaths = {}, deathReports = {} }

function time() return now end
function GetTime() return now end
function GetMoney() return 0 end
function UnitLevel() return 60 end
function CreateFrame()
    return { RegisterEvent = function() end, SetScript = function(self, event, callback) self[event] = callback end }
end
C_Timer = {
    After = function(_, callback) callback() end,
    NewTicker = function() return { Cancel = function() end } end,
}
C_ChatInfo = { RegisterAddonMessagePrefix = function() end }

local function normalize(name)
    return tostring(name or ""):match("^([^-]+)"):lower()
end

local iRC = {
    Name = "iRC",
    ConnectionDashboard = nil,
    MainUI = nil,
    Identity = { IsPersonalBank = function() return false end },
    IsGuildConnectionActive = function() return true end,
    IsGuildFoundRequired = function() return true end,
    IsGuildFoundEconomyActive = function() return true end,
    GetProgressionMode = function() return "GUILD_FOUND" end,
    GetConnection = function() return db end,
    GetPlayerName = function() return player end,
    NormalizeName = function(_, name) return normalize(name) end,
    FormatPlayerName = function(_, name) return tostring(name or "") end,
    IsGuildMemberName = function(_, name) return type(name) == "string" and name ~= "" end,
    GetGuildMemberRankIndex = function(_, name) return normalize(name) == "officer" and 1 or 5 end,
    GuildMemberHasPermission = function(_, name, permission)
        return permission == "verification" and normalize(name) == "officer"
    end,
    HasGuildPermission = function(_, permission) return permission == "verification" and localCanVerify end,
    IsRulesetBroadcaster = function() return true end,
    IsRulesetBroadcasterName = function(_, name) return normalize(name) == "relay" end,
    DeferLowTraffic = function() return false end,
    SendAddonTraffic = function(_, prefix, payload, distribution, target)
        sent[#sent + 1] = { prefix = prefix, payload = payload, distribution = distribution, target = target }
        return true
    end,
    GetSettings = function() return { debugMode = false } end,
    DebugMsg = function() end,
    Text = function(_, key) return key end,
    InvalidateGuildMemberRow = function() end,
    IsLowTrafficMode = function() return false end,
    GetSelfFoundState = function() return false end,
    GetStartupTrafficDelay = function() return 0 end,
    HasSecretValues = function() return false end,
    AcceptIncomingAddonTraffic = function() return true end,
    QueuePerformanceIncoming = function() return false end,
}

local private = { iRC = iRC }
assert(loadfile("iRC_RaceLockedSync.lua"))("iRC", private)
local sync = assert(iRC.RaceLockedSync)

sync:ReceiveRoster("S:Member,1,1,0,1,1,1800000000", "Member-Realm")
local member = assert(db.guildFoundRoster.member)
assert(member.verified == true and member.clean == true, "self-report keeps raw member evidence")
assert(member.gmVerified == nil and member.gmClean == nil and member.gmTimestamp == nil,
    "self-report cannot inject an officer verification override")

sync:ReceiveRoster("S:Member,1,0,1799999999,-,-,0,100,200,1799999900,1799999999,300,400,1799999900,1799999999,PLAYED_GAP", "Member-Realm")
assert(member.clean == false and member.tamperAt == 1799999999 and member.discrepancyReason == "PLAYED_GAP",
    "a reported monitoring discrepancy is retained with its evidence reason")
sync:ReceiveRoster("S:Member,1,1,0,-,-,0", "Member-Realm")
assert(member.clean == false and member.tamperAt == 1799999999,
    "a later clean self-report cannot erase discrepancy evidence already witnessed by another client")

sync:ReceiveRoster("R:Member,1,1,1800000001,Officer-Realm", "Member-Realm")
assert(member.gmTimestamp == nil, "non-broadcaster cannot forge an authorized officer relay")
sync:ReceiveRoster("R:Member,1,1,1800000001,Officer-Realm", "Relay-Realm")
assert(member.gmVerified == true and member.gmClean == true and member.gmTimestamp == 1800000001,
    "elected broadcaster can relay an authorized officer decision")

sync:ReceiveRoster("W:Other,1799999998,100,100,1799999900,1799999998,300,400,1799999900,1799999998,PLAYED_GAP", "Officer-Realm")
local witnessed = assert(db.guildFoundRoster.other)
assert(witnessed.verified == nil and witnessed.clean == false and witnessed.tamperAt == 1799999998,
    "an officer witness preserves negative evidence without granting progression eligibility")
localCanVerify, sent = true, {}
assert(sync:RelayWitnesses("Officer-Realm"), "authorized officers replay witnessed discrepancies to another reviewer")
assert(sent[1] and sent[1].payload:sub(1, 2) == "W:" and sent[1].distribution == "WHISPER",
    "witness history uses its negative-only packet and targets the reviewing officer")

db.guildFoundRoster = {}
for index = 1, 20 do
    local name = string.format("Verylongmembername%02d", index)
    db.guildFoundRoster[normalize(name)] = {
        name = name, gmVerified = true, gmClean = true, gmTimestamp = now + index,
        overrideSource = "Officer-Realm",
    }
end
sent = {}
assert(sync:RelayOverrides("Target-Realm"), "override relay emits at least one packet")
assert(#sent > 1, "large override sets split across multiple packets")
for _, packet in ipairs(sent) do
    assert(packet.payload:sub(1, 2) == "R:", "every split override packet retains the relay schema")
    assert(#packet.payload <= 255, "split override packet respects WoW's payload limit")
end

print("Guild Found sync tests passed: self-report isolation, authenticated relays, and packet splitting.")
