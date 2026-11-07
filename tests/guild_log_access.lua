-- Exercise public log access and restricted history replies with real identity code.
local now, authorized = 1800000000, false
local permissions = { ["Officer One"] = true, ["Officer Two"] = true }
local timers, sent = {}, {}
local addon = { Prefix = "iRCConnV1" }
function time() return now end
function CreateFrame() return { RegisterEvent = function() end, SetScript = function() end } end
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
function addon:NormalizeName(name) return tostring(name or ""):lower() end
function addon:FormatPlayerName(name) return tostring(name or "") end
function addon:GetGuildKey() return "guild" end
function addon:GetPlayerName() return "Local Member" end
function addon:HasGuildPermission() return authorized end
function addon:GuildMemberHasPermission(name) return permissions[name] == true end
function addon:IsGuildConnectionActive() return true end
function addon:IsRulesetBroadcaster() return true end
function addon:IsGuildMemberName(name) return name ~= "Outside Player" end
function addon:GetGuildMemberRankIndex(name) return self:IsGuildMemberName(name) and 2 or nil end
function addon:SendAddonTraffic(prefix, payload, distribution, target)
    sent[#sent + 1] = { payload = payload, distribution = distribution, target = target }
    return true
end
local records = {
    { id = "join1", eventType = "JOIN", name = "Subject Player", occurredAt = now - 10, text = "Subject Player joined the guild." },
    { id = "level1", eventType = "LEVEL", name = "Subject Player", occurredAt = now - 9, text = "Subject Player changed from level 10 to level 11." },
    { id = "note1", eventType = "NOTE", name = "Subject Player", occurredAt = now - 8, text = "A public note changed." },
    { id = "officer1", eventType = "OFFICER_NOTE", name = "Subject Player", occurredAt = now - 7, text = "An officer note changed." },
    { id = "audit1", eventType = "INBOX_BLOCKED", name = "Subject Player", occurredAt = now - 6, text = "Private audit evidence" },
}
iRCDB = { identityGuilds = { guild = { guildLog = records } } }
assert(loadfile("iRC_Identity.lua"))("iRC", { iRC = addon })
local identity = addon.Identity
assert(#identity:GetGuildLog() == 2 and #identity:GetMemberActivity("Subject Player", 20) == 2,
    "ordinary members only see general roster events, even with previously cached private records")
assert(#identity:GetGuildLog("Member Two") == 2 and #identity:GetGuildLog("Officer Two") == 4)
authorized = true
assert(#identity:GetGuildLog() == 4, "authorized detailed history includes note changes but excludes unknown audit types")
assert(identity:BroadcastGuildLog(records[1]) and sent[#sent].distribution == "GUILD")
assert(not identity:BroadcastGuildLog(records[4]), "restricted notes are never broadcast to the whole guild")
assert(not identity:BroadcastGuildLog(records[4], "Member Two"))
assert(not identity:BroadcastGuildLog(records[1], "Outside Player"))
assert(identity:BroadcastGuildLog(records[4], "Officer Two") and sent[#sent].distribution == "WHISPER")

-- Incoming authority remains restricted, independently of public read access.
authorized = false
local event = { "IDENT_EVENT", "2", "private2", tostring(now), "OFFICER_NOTE", "Subject Player", "MAGE", "Restricted history" }
assert(not identity:ReceiveSync(event, "Officer One"), "members reject restricted incoming history from old clients too")
event[3], event[5], event[8] = "public2", "RETURN", "Subject Player returned."
assert(not identity:ReceiveSync(event, "Member Two"), "read access does not grant authority to publish guild history")
assert(identity:ReceiveSync(event, "Officer One"), "an authorized sender can share general events with a member")

identity.BroadcastPersonalIdentity = function() return false end
authorized = true
sent = {}
assert(identity:ReceiveSync({ "IDENT_REQUEST", "2" }, "Member Two"))
while #timers > 0 do table.remove(timers, 1)() end
assert(#sent == 3, "member catch-up includes all public events")
for _, packet in ipairs(sent) do
    assert(not packet.payload:find("NOTE", 1, true) and not packet.payload:find("Private audit", 1, true))
end
sent = {}
assert(identity:ReceiveSync({ "IDENT_REQUEST", "2" }, "Officer Two"))
permissions["Officer Two"] = false
while #timers > 0 do table.remove(timers, 1)() end
for _, packet in ipairs(sent) do
    assert(not packet.payload:find("NOTE", 1, true), "permission is rechecked when a delayed reply is actually sent")
end
print("Guild log access tests passed: public reading, private notes, sender authority, and queued permission changes")
