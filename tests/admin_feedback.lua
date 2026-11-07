-- Exercise actual outgoing-event handling and saved history without sending chat.
local clock, admin, realm, scope = 1000, true, "Forever", "normal"
local player, frame = "Crasling Mordaine", nil
local secret = {}
local addon = { L = { TEST_ADMIN_ONLINE_WHISPER_MESSAGE = "Could I ask for feedback?" } }
function addon:IsTestAdmin() return admin end
function addon:IsSecretValue(value) return value == secret end
function addon:GetGuildDirectoryScope() return scope end
function addon:GetPlayerName() return player end
function addon:NormalizeName(name) return self:FormatPlayerName(name):lower() end
function addon:FormatPlayerName(name) return name:gsub("%-", " ") end
function GetNormalizedRealmName() return realm end
function time() return clock end
function CreateFrame()
    frame = {
        RegisterEvent = function(self, event) self.event = event end,
        SetScript = function(self, _, handler) self.handler = handler end,
    }
    return frame
end
local function loadModule()
    assert(loadfile("iRC_AdminFeedback.lua"))("iRC", { iRC = addon })
end
local function sent(message, name)
    frame.handler(frame, "CHAT_MSG_WHISPER_INFORM", message, name)
end
iRCDB = {}
loadModule()
local feedback = addon.AdminFeedback
assert(frame.event == "CHAT_MSG_WHISPER_INFORM")
assert(#feedback:GetHistory() == 0 and iRCDB.adminFeedbackHistory == nil,
    "opening history or preparing a draft does not create a sent record")
sent("Ordinary conversation", "Visitor Name")
sent(secret, "Visitor Name")
sent(addon.L.TEST_ADMIN_ONLINE_WHISPER_MESSAGE, secret)
sent(addon.L.TEST_ADMIN_ONLINE_WHISPER_MESSAGE, "")
assert(iRCDB.adminFeedbackHistory == nil, "unrelated or unavailable chat does not create records")
sent(addon.L.TEST_ADMIN_ONLINE_WHISPER_MESSAGE, "Visitor-Name")
local entry = feedback:GetEntry("Visitor Name")
assert(entry.name == "Visitor Name" and entry.count == 1 and entry.lastSent == 1000)
assert(entry.sends[1].timestamp == 1000 and entry.sends[1].sender == player)
local savedRoot = iRCDB.adminFeedbackHistory
clock, player = 1060, "Crasling Veyrath"
sent(addon.L.TEST_ADMIN_ONLINE_WHISPER_MESSAGE, "Visitor Name")
assert(feedback:GetEntry("Visitor-Name") == entry and entry.count == 2)
assert(entry.lastSent == 1060 and entry.sends[1].timestamp == 1000
    and entry.sends[2].sender == "Crasling Veyrath", "all send times and sending admins are retained")
clock = 1070
sent(addon.L.TEST_ADMIN_ONLINE_WHISPER_MESSAGE, "Another Player")
local rows = feedback:GetHistory()
assert(#rows == 2 and rows[1].name == "Another Player", "history includes offline contacts, newest first")
loadModule()
feedback = addon.AdminFeedback
assert(iRCDB.adminFeedbackHistory == savedRoot and feedback:GetEntry("Visitor Name").count == 2,
    "history survives reloads and is shared between this account's admins")
admin = false
assert(feedback:GetEntry("Visitor Name") == nil and #feedback:GetHistory() == 0)
sent(addon.L.TEST_ADMIN_ONLINE_WHISPER_MESSAGE, "Unrecorded Player")
admin = true
assert(feedback:GetEntry("Unrecorded Player") == nil and #feedback:GetHistory() == 2,
    "non-admin characters cannot read or add contact history")
scope = "hardcore"
assert(#feedback:GetHistory() == 0)
sent(addon.L.TEST_ADMIN_ONLINE_WHISPER_MESSAGE, "Visitor Name")
assert(feedback:GetEntry("Visitor Name").count == 1)
realm = "AnotherRealm"
assert(#feedback:GetHistory() == 0, "other realms have separate contact history")
scope = nil
sent(addon.L.TEST_ADMIN_ONLINE_WHISPER_MESSAGE, "Unrecorded Player")
assert(#feedback:GetHistory() == 0, "unresolved rulesets do not contaminate another history")
realm, scope = "Forever", "normal"
assert(#feedback:GetHistory() == 2 and feedback:GetEntry("Visitor Name").count == 2)
addon.Roleplay = { TransformChatText = function(_, message) return "Well met! " .. message end }
sent("Well met! " .. addon.L.TEST_ADMIN_ONLINE_WHISPER_MESSAGE, "RP Visitor")
assert(feedback:GetEntry("RP Visitor").count == 1, "the exact RP-transformed feedback message is recorded too")
sent("Well met! Ordinary conversation", "Unrecorded Player")
assert(feedback:GetEntry("Unrecorded Player") == nil, "ordinary RP chat cannot create feedback records")
print("Admin feedback history tests passed")
