-- Guild raid progress counts distinct linked players, not account-wide credit.
local addon = {}
local connection = { progressReports = {} }
local scope = "test-pve"
function CreateFrame()
    return { RegisterEvent = function() end, SetScript = function() end }
end
function addon:GetConnection() return connection end
function addon:GetGuildDirectoryScope() return scope end
function addon:NormalizeName(name) return tostring(name or ""):lower() end
addon.Identity = { GetMainCharacterName = function(_, name)
    if name == "Alt One" then return "Member One" end
end }
local private = { iRC = addon }
assert(loadfile("iRC_Progress.lua"))("iRC", private)
local progress = addon.Progress
function progress:ReadLocal()
    return { PVE = { { id = 684 }, { id = 62034 }, { id = 62035 } },
        PVP = { { id = 900 } } }
end
local reports = {}
connection.progressReports[scope] = reports
local roster = {}
for index = 1, 20 do
    local name = "Member " .. (index == 1 and "One" or index)
    roster[#roster + 1] = { name = name }
    reports[addon:NormalizeName(name)] = { PVE = {
        { id = 62035, earned = index <= 10 },
        { id = 62034, earned = index <= 10 },
        { id = 684, earned = index <= 20 },
    }, PVP = { { id = 900, earned = index == 1 } }, pvpRank = index <= 3 and index or 0 }
end
local function summary(count)
    local subset = {}
    for index = 1, count do subset[index] = roster[index] end
    return progress:GetGuildSummary(subset)
end
assert(summary(4).PVE.raids[3].state == "NONE", "four of ten is not a yellow clear")
assert(summary(5).PVE.raids[3].state == "YELLOW", "five of ten is a yellow clear")
assert(summary(10).PVE.raids[3].state == "CLEARED", "ten of ten is a full clear")
assert(summary(10).PVE.raids[2].state == "YELLOW", "ten of twenty is a yellow clear")
assert(summary(20).PVE.raids[1].state == "YELLOW", "twenty of forty is a yellow clear")
roster[#roster + 1] = { name = "Alt One" }
reports[addon:NormalizeName("Alt One")] = reports[addon:NormalizeName("Member One")]
assert(progress:GetGuildSummary(roster).PVE.raids[3].count == 20,
    "a linked alt cannot add another player to a raid count")
local pvp = progress:GetGuildSummary(roster).PVP
assert(pvp.highestRank == 3 and pvp.score == 6 and pvp.rankedMembers == 3,
    "guild score sums each distinct player's highest lifetime PvP rank")
reports[addon:NormalizeName("Alt One")].pvpRank = 7
pvp = progress:GetGuildSummary(roster).PVP
assert(pvp.highestRank == 7 and pvp.score == 12,
    "linked alts contribute only their highest rank")
print("PASS: raid clear thresholds and linked-player deduplication")

-- A larger Legacy catalog must fit the addon transport and only replace a
-- member's previous report once every packet has arrived.
addon.Prefix = "iRCConnV1"
function addon:IsGuildConnectionActive() return true end
function addon:IsGuildMemberName() return true end
function addon:GetPlayerName() return "Self" end
function addon:DebugMsg() end
function addon:FormatPlayerName(name) return name end
local packets = {}
function addon:SendAddonTraffic(_, message)
    assert(#message <= 255, "progress packet exceeds WoW's addon-message limit")
    packets[#packets + 1] = message
    return true
end
function progress:ReadLocal()
    local entries = {}
    for id = 1, 60 do entries[id] = { id = 62000 + id, earned = id % 2 == 0 } end
    return { PVE = entries, PVP = {} }
end
function progress:ReadLocalPVPRank() return nil end
progress:Send(true)
assert(#packets > 1, "the larger achievement catalog is split into packets")
local function fields(packet)
    local result = {}
    for field in (packet .. "\t"):gmatch("(.-)\t") do result[#result + 1] = field end
    return result
end
reports.other = { PVE = { { id = 1, earned = true } } }
progress:Receive(fields(packets[1]), "Other", "GUILD")
assert(reports.other.PVE[1].id == 1, "an incomplete transfer preserves the old report")
for index = #packets, 2, -1 do
    progress:Receive(fields(packets[index]), "Other", "GUILD")
end
assert(#reports.other.PVE == 60 and reports.other.PVE[60].id == 62060,
    "out-of-order packets assemble the full character report")
print("PASS: progress packets fit the wire and assemble before replacing a report")
