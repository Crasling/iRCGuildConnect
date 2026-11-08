-- Run from the addon directory. No game, network or saved-variable writes.
local rosterRank = 0
local frames = {}

function GetBuildInfo() return "1.15.9", "1", "", 11509 end
function GetGuildInfo() return "Guild", "Guild Master", nil end
function GetNumGuildMembers() return 1 end
function GetGuildRosterInfo() return "Player-Realm", "Guild Master", rosterRank end
function GetUnitName() return "Player-Realm" end
function UnitName() return "Player" end
function GetRealmName() return "Realm" end
function CreateFrame()
    local frame = { RegisterEvent = function() end, SetScript = function() end }
    frames[#frames + 1] = frame
    return frame
end
function LibStub(name)
    if name ~= "AceAddon-3.0" then return nil end
    return { NewAddon = function() return {} end }
end

local private = {}
assert(loadfile("iRC_Core.lua"))("iRC", private)
iRCDB, iRCCharDB = {}, {}

assert(private.iRC:IsGuildMaster(), "roster rank 0 retains Guild Master authority when GetGuildInfo has no rank")
rosterRank = 1
assert(not private.iRC:IsGuildMaster(), "nonzero roster ranks do not receive Guild Master authority")

private.iRC.GetConnection = function() return { guildMasterRank = 1 } end
assert(private.iRC:IsGuildMaster(), "the configured Guild master rank receives iRC Guild Master authority")
rosterRank = 2
assert(not private.iRC:IsGuildMaster(), "ranks below the configured Guild master rank remain regular members")

local addon = private.iRC
local connection = { active = true, guildMasterRank = 0, rankPermissions = { notesView = 9 }, memberPermissions = {} }
addon.GetConnection = function() return connection end
assert(addon:HasGuildPermission("notesView"), "a lower rank can receive read access to notes")
assert(not addon:HasGuildPermission("verification") and not addon:CanAutomaticallyEstablishGuildRules(),
    "reading notes does not grant verification or guild-rule authority")
local key = addon:NormalizeName(addon:GetPlayerName())
connection.memberPermissions[key] = { permissions = { notesManage = true } }
assert(addon:HasGuildPermission("notesManage") and not addon:CanAutomaticallyEstablishGuildRules(),
    "an individual note-management grant remains limited to notes")
local file = assert(io.open("iRC_Connection.lua"))
local source = file:read("*a"); file:close()
local first = assert(source:find("local function rankHasGuildMasterAuthority(", 1, true))
local last = assert(source:find("local function getRulesAuthority(", first, true))
local relayPermission = assert(load("local iRC = ...\n" .. source:sub(first, last - 1)
    .. "\nreturn rankHasDelegatedPermission", "rule relay permission"))(addon)
assert(not relayPermission(2, connection, addon:GetPlayerName()), "notes-only delegates cannot relay guild rules")
connection.memberPermissions[key].permissions.identity = true
assert(addon:CanAutomaticallyEstablishGuildRules() and relayPermission(2, connection, addon:GetPlayerName()),
    "existing management permissions retain their rule-relay behaviour")

print("Guild Master authority tests passed: native, delegated, and lower-rank handling.")
