-- Directory sorting uses saved and local reports without assigning scores.
local addon, private = {}, {}
WOW_PROJECT_ID = 18
function GetCurrentRegion() return 3 end
function wipe(value) for key in pairs(value) do value[key] = nil end; return value end
function GetTime() return 100 end
function time() return 1800000000 end
function GetBuildInfo() return "1.60.1", "70374", "", 16001 end
function CreateFrame() return { RegisterEvent = function() end, SetScript = function() end } end
function LibStub(name)
    if name == "AceAddon-3.0" then return { NewAddon = function() return addon end } end
end
assert(loadfile("iRC_Core.lua"))("iRC", private)
function addon:GetSettings() return {} end
function addon:GetGuildDirectoryScope() return "s-18-3-10-0-pve" end
function addon:ContainsProfanity() return false end
function addon:DebugMsg() end
function addon:Text(key) return key end
assert(loadfile("iRC_RaceGrid.lua"))("iRC", private)
local grid, own = addon.RaceGrid, {}
function grid:BuildOwnGuildReports() return own end
local function report(name, active, peak, members, maxLevel)
    return {
        serverRuleset = addon:GetGuildDirectoryScope(),
        name = "Reporter", guid = "Player-1-Report", guildName = name, race = "HUMAN",
        faction = "Alliance", members = members, activeMembers = active, activePlayers = peak,
        activeLevel60 = maxLevel, membersLevel60 = maxLevel, timestamp = time(),
        classes = {}, rules = {}, rulesKnown = true, guildDescription = "", guildHomepageTag = "NORMAL",
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
local function progress(pve, pvp, partial, pveTotal, score, rank)
    return { PVE = { completed = pve, partial = partial or 0, total = pveTotal or 3 },
        PVP = { completed = pvp, total = 12, score = score, highestRank = rank or 0 } }
end
saved[1].progress = progress(0, 0, nil, nil, 0)
saved[2].progress = progress(1, 7, nil, nil, 18, 9)
saved[3].progress = progress(1, 2, 1, nil, 12, 12)
saved[4].progress = progress(0, 0, 2, nil, 0)
saved[5].progress = progress(0, 0, 1, nil, 0)
saved[7].progress = progress(0, 0, nil, nil, 0)
for _, entry in ipairs(saved) do assert(grid:StoreGuildReport(entry, true, true)) end
own = { report("Home Guild", 15, 1, 50, 0) }
own[1].progress = progress(2, 4, nil, nil, 15, 7)
local function names(rows)
    local result = {}
    for _, entry in ipairs(rows) do result[#result + 1] = entry.guildName end
    return table.concat(result, ",")
end
local pve = addon:GetGuildDirectoryOverview("PVE")
assert(names(pve) == "Home Guild,Gamma Busy,Beta Large,Delta Active,Echo Twin,Alpha Archive,Zulu Quiet",
    "raid clears lead, yellow half-roster clears break ties, and missing progress sorts last")
assert(pve[1] == own[1], "the local guild report replaces its cached copy and remains in the directory")
assert(names(addon:GetGuildDirectoryOverview("PVP"))
    == "Beta Large,Home Guild,Gamma Busy,Alpha Archive,Delta Active,Echo Twin,Zulu Quiet",
    "PvP progress sorts by lifetime rank score independently of challenge counts")
assert(names(addon:GetGuildDirectoryOverview("MEMBERS"))
    == "Alpha Archive,Beta Large,Delta Active,Zulu Quiet,Echo Twin,Gamma Busy,Home Guild",
    "member sorting uses total membership with alphabetical ties")
assert(names(addon:GetGuildDirectoryOverview("NAME"))
    == "Alpha Archive,Beta Large,Delta Active,Echo Twin,Gamma Busy,Home Guild,Zulu Quiet",
    "name sorting is alphabetical regardless of activity or max levels")
assert(names(addon:GetGuildDirectoryOverview("invalid")) == names(pve), "invalid sort choices safely use PvE progress")
assert(names(addon:GetRaceGridOverview()) == names(pve), "the previous entry point also uses directory order")
saved[1].activeLevel60, saved[2].activeLevel60, saved[3].activeLevel60 = 0, 0, 100
assert(names(addon:GetGuildDirectoryOverview("PVE")) == names(pve), "max-level counts cannot change directory order")
for _, entry in ipairs(pve) do
    assert(entry.rank == nil and entry.score == nil, "directory reports do not acquire competitive placements")
end
print("PASS: directory progress sort choices, unknown progress, alphabetical ties, own guild, and max-level independence")
