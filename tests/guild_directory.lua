-- Directory sorting uses saved and local reports without assigning scores.
local addon, private = {}, {}
function GetTime() return 100 end
function time() return 1800000000 end
function GetBuildInfo() return "1.60.1", "70374", "", 16001 end
function CreateFrame() return { RegisterEvent = function() end, SetScript = function() end } end
function LibStub(name)
    if name == "AceAddon-3.0" then return { NewAddon = function() return addon end } end
end
assert(loadfile("iRC_Core.lua"))("iRC", private)
function addon:GetSettings() return {} end
function addon:ContainsProfanity() return false end
function addon:DebugMsg() end
function addon:Text(key) return key end
assert(loadfile("iRC_RaceGrid.lua"))("iRC", private)
local grid, own = addon.RaceGrid, {}
function grid:BuildOwnGuildReports() return own end
local function report(name, active, peak, members, maxLevel)
    return {
        name = "Reporter", guid = "Player-1-Report", guildName = name, race = "HUMAN",
        faction = "Alliance", members = members, activeMembers = active, activePlayers = peak,
        activeLevel60 = maxLevel, membersLevel60 = maxLevel, timestamp = time(),
        classes = {}, rules = {}, guildDescription = "", guildHomepageTag = "NORMAL",
    }
end
local saved = {
    report("Alpha Archive", nil, 500, 600, 600),
    report("Beta Large", 10, 20, 500, 500),
    report("Gamma Busy", 80, 30, 120, 1),
    report("Delta Active", 80, 10, 200, 100),
    report("Echo Twin", 80, 30, 120, 2),
    report("Zulu Quiet", 0, 0, 150, 150),
    report("Home Guild", 100, 40, 500, 500),
}
for _, entry in ipairs(saved) do assert(grid:StoreGuildReport(entry, true, true)) end
own = { report("Home Guild", 15, 1, 50, 0) }
local function names(rows)
    local result = {}
    for _, entry in ipairs(rows) do result[#result + 1] = entry.guildName end
    return table.concat(result, ",")
end
local activity = addon:GetGuildDirectoryOverview("ACTIVITY")
assert(names(activity) == "Echo Twin,Gamma Busy,Delta Active,Home Guild,Beta Large,Zulu Quiet,Alpha Archive",
    "activity uses active members, then online peak, and keeps unknown activity after known zero")
assert(activity[4] == own[1], "the local guild report replaces its cached copy and remains in the directory")
assert(names(addon:GetGuildDirectoryOverview("MEMBERS"))
    == "Alpha Archive,Beta Large,Delta Active,Zulu Quiet,Echo Twin,Gamma Busy,Home Guild",
    "member sorting uses total membership with alphabetical ties")
assert(names(addon:GetGuildDirectoryOverview("NAME"))
    == "Alpha Archive,Beta Large,Delta Active,Echo Twin,Gamma Busy,Home Guild,Zulu Quiet",
    "name sorting is alphabetical regardless of activity or max levels")
assert(names(addon:GetGuildDirectoryOverview("invalid")) == names(activity), "invalid sort choices safely use activity")
assert(names(addon:GetRaceGridOverview()) == names(activity), "the previous entry point also uses directory order")
saved[1].activeLevel60, saved[2].activeLevel60, saved[3].activeLevel60 = 0, 0, 100
assert(names(addon:GetGuildDirectoryOverview("ACTIVITY")) == names(activity), "max-level counts cannot change directory order")
for _, entry in ipairs(activity) do
    assert(entry.rank == nil and entry.score == nil, "directory reports do not acquire competitive placements")
end
print("PASS: directory sort choices, unknown activity, alphabetical ties, own guild, and max-level independence")
