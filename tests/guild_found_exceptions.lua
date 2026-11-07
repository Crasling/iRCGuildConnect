-- Exercise exception permissions and real send/receive packets without a game.
local now, ownRank = 1800000000, 0
local frames, sent = {}, {}
local roster = {
    { name = "Local Member", rank = 0 }, { name = "Guild Master", rank = 0 },
    { name = "Review Officer", rank = 1 }, { name = "Ordinary Member", rank = 5 },
}
function time() return now end
function GetTime() return now end
function GetBuildInfo() return "1.60.1", "70790", "", 16001 end
function GetRealmName() return "Realm" end
function GetUnitName() return "Local Member" end
function UnitName() return "Local", "Member" end
function UnitGUID() return "Player-1-local" end
function UnitLevel() return 20 end
function UnitRace() return "Undead", "SCOURGE" end
function UnitClass() return "Warlock", "WARLOCK" end
function GetGuildInfo() return "Test Guild", "Rank", ownRank end
function GetNumGuildMembers() return #roster end
function GetGuildRosterInfo(index)
    local row = roster[index]
    return row.name, "Rank", index == 1 and ownRank or row.rank, 20, "Warlock", nil, nil, nil, true,
        nil, "WARLOCK", nil, nil, nil, nil, nil, "Player-1-" .. index
end
function CreateFrame()
    local frame = { RegisterEvent = function() end, SetScript = function(self, key, callback) self[key] = callback end }
    frames[#frames + 1] = frame
    return frame
end
local addon, private = {}, {}
function LibStub() return { NewAddon = function() return addon end } end
assert(loadfile("iRC_Core.lua"))("iRC", private)
assert(loadfile("Localization/enUS.lua"))("iRC", private)
assert(loadfile("iRC_Guild.lua"))("iRC", private)
assert(loadfile("iRC_Connection.lua"))("iRC", private)
local connectionFrame = frames[#frames]
local iRC = private.iRC
iRCDB, iRCCharDB = {}, {}
iRC.Frame.OnEvent(nil, "ADDON_LOADED", iRC.Name)
local db = assert(iRC:GetConnection())
db.active, db.rulesBootstrap = true, false
db.rules.guildFoundOnly, db.rules.guildFoundTradeExceptions = true, true
db.rankPermissions.tradeExceptions = 1
function iRC:DebugMsg() end
function iRC:SendAddonTraffic(prefix, message, distribution, target)
    assert(#message <= 255, "exception settings fit in one addon packet")
    sent[#sent + 1] = { prefix, message, distribution, target }
    return true
end
local function receive(message, sender)
    now = now + 1
    connectionFrame.OnEvent(nil, "CHAT_MSG_ADDON", iRC.Prefix, message, "GUILD", sender)
end
local function fields(message)
    local result = {}
    for value in (message .. "\t"):gmatch("(.-)\t") do result[#result + 1] = value end
    return result
end
local function setRank(rank)
    ownRank = rank
    iRC:InvalidateGuildRosterSnapshot()
end
local settings = iRC:GetGuildFoundTradeExceptionSettings()
assert(settings.outgoingMail == false, "outgoing mail defaults to restricted")
assert(iRC:SetGuildFoundTradeException("outgoingMail", true), "GM can enable the mail exception")
local enabledPacket = sent[#sent][2]
local enabledFields = fields(enabledPacket)
assert(enabledFields[8] == "1" and enabledFields[9] ~= "" and tonumber(enabledFields[3]) <= 255,
    "mail uses a checked extension without expanding the existing item mask")
assert(iRC:SetGuildFoundTradeException("conjured", true), "existing item exceptions remain configurable")
assert(iRC:SetGuildFoundTradeExceptionItem("conjured", 5350, true))
local combinedPacket = sent[#sent][2]
assert(iRC:SetGuildFoundTradeException("outgoingMail", false))
local disabledPacket = sent[#sent][2]

-- An ordinary receiving member must learn the setting from an authorized sender.
setRank(5)
local before = #sent
assert(not iRC:SetGuildFoundTradeException("outgoingMail", true) and #sent == before,
    "ordinary members cannot edit or broadcast exceptions")
assert(not iRC:SendGuildFoundTradeExceptions(nil, true))
settings.timestamp = 0
receive(combinedPacket, "Guild Master")
assert(settings.outgoingMail == true and settings.conjured == true and settings.items.conjured[5350],
    "members receive mail and selected-item settings together")
receive(disabledPacket, "Guild Master")
assert(settings.outgoingMail == false, "authorized revocation reaches members")
receive(combinedPacket, "Guild Master")
assert(settings.outgoingMail == false, "an older packet cannot reactivate a revoked exception")

local bad = fields(disabledPacket)
bad[8] = "1"
receive(table.concat(bad, "\t"), "Guild Master")
assert(settings.outgoingMail == false, "changing the mail bit without its checksum is rejected")
bad = fields(disabledPacket); bad[9] = nil
receive(table.concat(bad, "\t"), "Guild Master")
assert(settings.outgoingMail == false, "an incomplete extension is rejected")
settings.timestamp = 0
receive(combinedPacket, "Ordinary Member")
assert(settings.outgoingMail == false and settings.timestamp == 0, "an unauthorized guild member cannot relay mail permission")
receive(combinedPacket, "Outsider")
assert(settings.timestamp == 0, "non-guild senders are rejected")
receive(combinedPacket, "Review Officer")
assert(settings.outgoingMail == true, "delegated exception editors can update the setting")

-- Released clients still understand the base item packet. Their relays must
-- not erase a mail choice they cannot represent.
local old = fields(disabledPacket); old[8], old[9] = nil, nil
receive(table.concat(old, "\t"), "Guild Master")
assert(settings.outgoingMail == true and settings.items.conjured[5350],
    "a base-only relay keeps the mail choice while updating legacy item settings")
receive(disabledPacket, "Guild Master")
assert(settings.outgoingMail == false, "a complete packet with the same timestamp is not mistaken for the old relay")
setRank(0)
db.rules.guildFoundTradeExceptions = false
assert(not iRC:SetGuildFoundTradeException("outgoingMail", true), "the master exception rule gates edits")
db.rules.guildFoundTradeExceptions, db.active = true, false
assert(not iRC:SetGuildFoundTradeException("outgoingMail", true), "inactive connections cannot change exceptions")
print("PASS: exception defaults, permissions, checked mail sync, revocation, item selections, and released-client relays")
