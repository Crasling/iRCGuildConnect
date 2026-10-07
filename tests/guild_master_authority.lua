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

print("Guild Master authority tests passed: native, delegated, and lower-rank handling.")
