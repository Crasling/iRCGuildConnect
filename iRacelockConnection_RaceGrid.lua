local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local RaceGrid = {}
iRC.RaceGrid = RaceGrid

local PREFIX = "iRCGridV1"
local CHANNEL_NAME = "iRacelockConnection"
local WIRE_VERSION = "1"
local REPORT_INTERVAL = 120
local STALE_AFTER = 900
local SEP = "\t"
-- RaceLocked and its ForkEU variant publish the same RLRaceGridV1 payload on
-- separate text channels.  iRC joins both to consume their public race data;
-- it never writes iRC payloads to either channel.
local RACELOCKED_CHANNELS = {
    "RaceLockedDataBus",
    "RaceLockedForkEUDataBus",
}
local RACELOCKED_CHANNEL_LOOKUP = {
    RaceLockedDataBus = true,
    RaceLockedForkEUDataBus = true,
}
local RACELOCKED_WIRE_PREFIX = "RLRaceGridV1:"
local RACELOCKED_FIELD_SEPARATOR = string.char(1)

local ALLIANCE_RACES = { HUMAN = true, DWARF = true, NIGHTELF = true, GNOME = true, DRAENEI = true }
local HORDE_RACES = { ORC = true, SCOURGE = true, TAUREN = true, TROLL = true, BLOODELF = true }
local VALID_RACES = {}
for race in pairs(ALLIANCE_RACES) do VALID_RACES[race] = true end
for race in pairs(HORDE_RACES) do VALID_RACES[race] = true end

local RACELOCKED_RACE_TOKENS = {
    Human = "HUMAN", Dwarf = "DWARF", NightElf = "NIGHTELF", Gnome = "GNOME",
    Orc = "ORC", Troll = "TROLL", Tauren = "TAUREN", Scourge = "SCOURGE",
}
local RACELOCKED_CLASS_KEYS = {
    druids = "DRUID", rogues = "ROGUE", hunters = "HUNTER", warriors = "WARRIOR",
    mages = "MAGE", priests = "PRIEST", warlocks = "WARLOCK", paladins = "PALADIN", shamans = "SHAMAN",
}

local function normalizeRaceToken(race)
    local token = tostring(race or ""):upper():gsub("%s+", "")
    if token == "UNDEAD" then token = "SCOURGE" end
    return VALID_RACES[token] and token or nil
end

local function registerPrefix(prefix)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then return C_ChatInfo.RegisterAddonMessagePrefix(prefix) end
    if RegisterAddonMessagePrefix then return RegisterAddonMessagePrefix(prefix) end
end

local function send(prefix, message, distribution, target)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then return C_ChatInfo.SendAddonMessage(prefix, message, distribution, target) end
    if SendAddonMessage then return SendAddonMessage(prefix, message, distribution, target) end
end

local function split(message)
    local fields = {}
    for value in (tostring(message or "") .. SEP):gmatch("(.-)" .. SEP) do fields[#fields + 1] = value end
    return fields
end

local function fullNameKey(name)
    return string.lower(tostring(name or ""))
end

local function validNumber(value, minimum, maximum)
    value = tonumber(value)
    if not value or value < minimum or value > maximum then return nil end
    return math.floor(value)
end

local function normalizeGuildName(name)
    return string.lower((tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")))
end

local function hexToBytes(value)
    if type(value) ~= "string" or value == "" or #value % 2 ~= 0 then return nil end
    local bytes = {}
    for index = 1, #value, 2 do
        local byte = tonumber(value:sub(index, index + 1), 16)
        if not byte then return nil end
        bytes[#bytes + 1] = string.char(byte)
    end
    return table.concat(bytes)
end

local function getChannelId(channelName)
    local channelId = GetChannelName and GetChannelName(channelName or CHANNEL_NAME)
    return type(channelId) == "number" and channelId > 0 and channelId or nil
end

local function hideChannelFromChatWindows(channelName)
    if not ChatFrame_RemoveChannel or not NUM_CHAT_WINDOWS then return end
    for index = 1, NUM_CHAT_WINDOWS do
        local chatFrame = _G["ChatFrame" .. index]
        if chatFrame then ChatFrame_RemoveChannel(chatFrame, channelName) end
    end
end

function RaceGrid:IsEnabled()
    return iRC:GetSettings().shareGlobalRaceGrid == true
end

function RaceGrid:EnsureChannel()
    if not self:IsEnabled() then return end
    if getChannelId() then
        hideChannelFromChatWindows(CHANNEL_NAME)
        return
    end
    if JoinChannelByName then
        iRC:DebugMsg(iRC:Text("RACEGRID_OWN_CHANNEL_JOIN"), 3)
        JoinChannelByName(CHANNEL_NAME)
    end
end

function RaceGrid:EnsureRaceLockedChannels()
    -- Receiving external race reports is independent of iRC's optional public
    -- broadcast setting.  This keeps the overview useful without sharing the
    -- player's own iRC report on the iRC channel.
    if not JoinChannelByName then return end
    for _, channelName in ipairs(RACELOCKED_CHANNELS) do
        if not getChannelId(channelName) then
            iRC:DebugMsg(iRC:Text("RACEGRID_CHANNEL_JOIN", channelName), 3)
            JoinChannelByName(channelName)
        end
        hideChannelFromChatWindows(channelName)
        if getChannelId(channelName) then iRC:DebugMsg(iRC:Text("RACEGRID_EXTERNAL_CHANNEL_READY", channelName), 3) end
    end
end

function RaceGrid:Disable()
    if LeaveChannelByName and getChannelId() then LeaveChannelByName(CHANNEL_NAME) end
end

function RaceGrid:GetLocalReport()
    local profile = iRC:GetLocalProfile()
    local evidence = profile.selfFoundEvidence or {}
    return {
        name = profile.name,
        guid = profile.guid,
        race = normalizeRaceToken(profile.race),
        class = profile.class,
        level = profile.level,
        points = profile.points,
        guildName = (GetGuildInfo and GetGuildInfo("player")) or "",
        selfFound = profile.selfFound and true or false,
        selfFoundStatus = evidence.status or "UNVERIFIED",
        source = "iRC global live report",
        lastSeen = time(),
    }
end

function RaceGrid:StoreReport(report)
    if type(report) ~= "table" or type(report.name) ~= "string" or report.name == "" then return end
    local originalRace = report.race
    report.race = normalizeRaceToken(report.race)
    if not report.race then
        iRC:DebugMsg(iRC:Text("RACEGRID_UNSUPPORTED_RACE", tostring(originalRace or "")), 2)
        return
    end
    iRCDB = iRCDB or {}
    iRCDB.globalRaceGrid = iRCDB.globalRaceGrid or { members = {} }
    local members = iRCDB.globalRaceGrid.members
    report.lastSeen = time()
    members[fullNameKey(report.name)] = report
    if iRC.AchievementsUI then iRC.AchievementsUI:RefreshIfShown() end
end

function RaceGrid:StoreRaceLockedGuildReport(report)
    if type(report) ~= "table" or not report.race or not report.guildName then return end
    iRCDB = iRCDB or {}
    iRCDB.globalRaceGrid = iRCDB.globalRaceGrid or { members = {} }
    iRCDB.globalRaceGrid.raceLockedGuildReports = iRCDB.globalRaceGrid.raceLockedGuildReports or {}
    report.lastSeen = time()
    iRCDB.globalRaceGrid.raceLockedGuildReports[report.race .. "@" .. normalizeGuildName(report.guildName)] = report
    if iRC.AchievementsUI then iRC.AchievementsUI:RefreshIfShown() end
end

local function parseRaceLockedGuildReport(message, channelName)
    if type(message) ~= "string" or message:sub(1, #RACELOCKED_WIRE_PREFIX) ~= RACELOCKED_WIRE_PREFIX then return nil end
    local payload = hexToBytes(message:sub(#RACELOCKED_WIRE_PREFIX + 1))
    if not payload then return nil end
    local fields = {}
    for value in (payload .. RACELOCKED_FIELD_SEPARATOR):gmatch("(.-)" .. RACELOCKED_FIELD_SEPARATOR) do fields[#fields + 1] = value end
    if fields[1] ~= "v5" or #fields < 27 then return nil end
    local race = RACELOCKED_RACE_TOKENS[fields[2]]
    local guildName = fields[3]
    local members = validNumber(fields[4], 1, 10000)
    local averageLevel = validNumber(fields[5], 1, 100)
    if not race or not guildName or guildName == "" or not members or not averageLevel then return nil end
    local classes = {}
    local index = 6
    for _, classKey in ipairs({ "druids", "rogues", "hunters", "warriors", "mages", "priests", "warlocks", "paladins", "shamans" }) do
        local count = validNumber(fields[index], 0, members) or 0
        classes[RACELOCKED_CLASS_KEYS[classKey]] = count
        index = index + 2
    end
    local averagePoints = validNumber(fields[26], 0, 10000000) or 0
    return {
        source = channelName == "RaceLockedForkEUDataBus" and "RaceLockedForkEU global guild report" or "RaceLocked global guild report",
        race = race, guildName = guildName,
        members = members, averageLevel = averageLevel, points = averagePoints * members, classes = classes,
    }
end

local function raceLockedReportExistsFor(race, guildName)
    local reports = iRCDB and iRCDB.globalRaceGrid and iRCDB.globalRaceGrid.raceLockedGuildReports or {}
    local report = reports[race .. "@" .. normalizeGuildName(guildName)]
    return report and time() - (tonumber(report.lastSeen) or 0) <= STALE_AFTER or false
end

function RaceGrid:BroadcastReport()
    if not self:IsEnabled() then return false end
    self:EnsureChannel()
    if not getChannelId() then
        iRC:DebugMsg(iRC:Text("RACEGRID_OWN_CHANNEL_UNAVAILABLE"), 2)
        return false
    end
    local report = self:GetLocalReport()
    if not report.name or report.name == "" or not report.guid or report.guid == "" or not report.race then return false end
    local payload = table.concat({
        "REPORT", WIRE_VERSION, report.name, report.guid, report.race, report.class,
        tostring(report.level), tostring(report.points), report.guildName,
        report.selfFound and "1" or "0", report.selfFoundStatus,
    }, SEP)
    if #payload > 255 then return false end
    self:StoreReport(report)
    send(PREFIX, payload, "CHANNEL", CHANNEL_NAME)
    iRC:DebugMsg(iRC:Text("RACEGRID_REPORT_SENT", report.name, report.race, report.level, report.guildName ~= "" and report.guildName or iRC:Text("RACEGRID_NO_GUILD")), 3)
    return true
end

function RaceGrid:RequestReports()
    if not self:IsEnabled() then return false end
    self:EnsureChannel()
    if not getChannelId() then return false end
    send(PREFIX, table.concat({ "REQUEST", WIRE_VERSION }, SEP), "CHANNEL", CHANNEL_NAME)
    iRC:DebugMsg(iRC:Text("RACEGRID_REQUEST_SENT"), 3)
    return true
end

function RaceGrid:Refresh()
    self:EnsureRaceLockedChannels()
    iRC:DebugMsg(iRC:Text("RACEGRID_INITIALIZED", iRC:Text(self:IsEnabled() and "RACEGRID_SHARING_ENABLED" or "RACEGRID_SHARING_DISABLED")), 3)
    if not self:IsEnabled() then return end
    self:EnsureChannel()
    if C_Timer and C_Timer.After then
        C_Timer.After(2, function()
            RaceGrid:BroadcastReport()
            RaceGrid:RequestReports()
        end)
    end
end

local function parseReport(parts)
    if parts[1] ~= "REPORT" or parts[2] ~= WIRE_VERSION then return nil end
    local name, guid, race, class = parts[3], parts[4], parts[5], parts[6]
    local level, points = validNumber(parts[7], 1, 100), validNumber(parts[8], 0, 10000000)
    if not name or name == "" or #name > 80 or not guid or guid == "" or #guid > 80 then return nil end
    if not VALID_RACES[race] or not class or class == "" or #class > 24 or not level or not points then return nil end
    local selfFoundStatus = parts[11] or "UNVERIFIED"
    if not selfFoundStatus:match("^[A-Z_]+$") or #selfFoundStatus > 32 then return nil end
    return {
        name = name, guid = guid, race = race, class = class, level = level, points = points,
        guildName = (parts[9] or ""):sub(1, 80), selfFound = parts[10] == "1",
        selfFoundStatus = selfFoundStatus, source = "iRC global live report",
    }
end

local function handleMessage(prefix, message, sender)
    if prefix ~= PREFIX or not RaceGrid:IsEnabled() then return end
    local parts = split(message)
    if parts[1] == "REQUEST" and parts[2] == WIRE_VERSION then
        iRC:DebugMsg(iRC:Text("RACEGRID_REQUEST_RECEIVED", sender), 3)
        RaceGrid:BroadcastReport()
        return
    end
    local report = parseReport(parts)
    if not report or fullNameKey(report.name) ~= fullNameKey(sender) then return end
    RaceGrid:StoreReport(report)
    iRC:DebugMsg(iRC:Text("RACEGRID_IRC_REPORT_RECEIVED", report.name, report.race, report.level, report.guildName ~= "" and report.guildName or iRC:Text("RACEGRID_NO_GUILD")), 3)
end

function iRC:GetGlobalRaceOverview()
    local stored = iRCDB and iRCDB.globalRaceGrid and iRCDB.globalRaceGrid.members or {}
    local groups = {}
    local now = time()
    for key, report in pairs(stored) do
        if type(report) ~= "table" or now - (tonumber(report.lastSeen) or 0) > STALE_AFTER then
            stored[key] = nil
        elseif VALID_RACES[report.race] and not raceLockedReportExistsFor(report.race, report.guildName) then
            local group = groups[report.race]
            if not group then
                group = {
                    race = report.race,
                    faction = ALLIANCE_RACES[report.race] and "Alliance" or "Horde",
                    members = 0, totalLevel = 0, points = 0, addonUsers = 0, selfFound = 0,
                    classes = {}, guilds = {}, guildName = "",
                }
                groups[report.race] = group
            end
            group.members = group.members + 1
            group.totalLevel = group.totalLevel + report.level
            group.points = group.points + report.points
            group.addonUsers = group.addonUsers + 1
            if report.selfFound then group.selfFound = group.selfFound + 1 end
            group.classes[report.class] = (group.classes[report.class] or 0) + 1
            if report.guildName and report.guildName ~= "" then group.guilds[report.guildName] = (group.guilds[report.guildName] or 0) + 1 end
        end
    end
    local result = {}
    for _, group in pairs(groups) do
        group.averageLevel = math.floor((group.totalLevel / group.members) * 10 + 0.5) / 10
        local highestCount = 0
        for guildName, count in pairs(group.guilds) do
            if count > highestCount or (count == highestCount and guildName < group.guildName) then
                group.guildName, highestCount = guildName, count
            end
        end
        group.guilds = nil
        result[#result + 1] = group
    end
    table.sort(result, function(a, b) return a.race < b.race end)
    return result
end

function iRC:GetRaceGridOverview()
    local iRCGlobalEnabled = RaceGrid:IsEnabled()
    local globalGroups = iRCGlobalEnabled and self:GetGlobalRaceOverview() or {}
    local groupsByRace, representedMembers = {}, {}
    local stored = iRCDB and iRCDB.globalRaceGrid and iRCDB.globalRaceGrid.members or {}
    if iRCGlobalEnabled then
        for _, report in pairs(stored) do representedMembers[self:NormalizeName(report.name)] = true end
    end
    for _, group in ipairs(globalGroups) do
        group.totalLevel = (group.averageLevel or 0) * (group.members or 0)
        groupsByRace[group.race] = group
    end

    local connection = self:GetConnection()
    for _, member in ipairs(self:GetGuildRosterRows()) do
        if not representedMembers[self:NormalizeName(member.name)] then
            local race = normalizeRaceToken(member.race)
            if not race then
                self:DebugMsg(self:Text("RACEGRID_UNSUPPORTED_RACE", tostring(member.race or "")), 2)
            else
                local group = groupsByRace[race]
                if not group then
                    group = {
                        race = race,
                        faction = ALLIANCE_RACES[race] and "Alliance" or "Horde",
                        members = 0, totalLevel = 0, points = 0, addonUsers = 0, selfFound = 0,
                        classes = {}, guildName = connection and connection.guildName or "",
                    }
                    groupsByRace[race] = group
                end
                group.members = group.members + 1
                group.totalLevel = group.totalLevel + (member.level or 1)
                group.points = group.points + (member.points or 0)
                if member.profile or member.compatibility then group.addonUsers = group.addonUsers + 1 end
                if member.selfFound then group.selfFound = group.selfFound + 1 end
                group.classes[member.class or "UNKNOWN"] = (group.classes[member.class or "UNKNOWN"] or 0) + 1
            end
        end
    end

    local ownGuildName = connection and connection.guildName or ""
    local raceLockedReports = iRCDB and iRCDB.globalRaceGrid and iRCDB.globalRaceGrid.raceLockedGuildReports or {}
    local hasLiveRaceLockedData, externalReportCount = false, 0
    for key, report in pairs(raceLockedReports) do
        if type(report) ~= "table" or time() - (tonumber(report.lastSeen) or 0) > STALE_AFTER then
            raceLockedReports[key] = nil
        elseif normalizeGuildName(report.guildName) ~= normalizeGuildName(ownGuildName) then
            hasLiveRaceLockedData = true
            externalReportCount = externalReportCount + 1
            local group = groupsByRace[report.race]
            if not group then
                group = {
                    race = report.race,
                    faction = ALLIANCE_RACES[report.race] and "Alliance" or "Horde",
                    members = 0, totalLevel = 0, points = 0, addonUsers = 0, selfFound = 0,
                    classes = {}, guildName = report.guildName,
                }
                groupsByRace[report.race] = group
            end
            group.members = group.members + (report.members or 0)
            group.totalLevel = group.totalLevel + (report.averageLevel or 0) * (report.members or 0)
            group.points = group.points + (report.points or 0)
            group.addonUsers = group.addonUsers + (report.members or 0)
            for class, count in pairs(report.classes or {}) do group.classes[class] = (group.classes[class] or 0) + count end
        end
    end

    local result = {}
    for _, group in pairs(groupsByRace) do
        group.averageLevel = group.members > 0 and math.floor((group.totalLevel / group.members) * 10 + 0.5) / 10 or 0
        group.totalLevel = nil
        result[#result + 1] = group
    end
    table.sort(result, function(a, b) return a.race < b.race end)
    local source = hasLiveRaceLockedData and iRCGlobalEnabled and "combined" or (hasLiveRaceLockedData and "racelocked" or (iRCGlobalEnabled and "global" or "guild"))
    self:DebugMsg(self:Text("RACEGRID_SUMMARY", #result, externalReportCount, source), 3)
    return result, source
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("CHAT_MSG_CHANNEL")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= iRC.Name then return end
        registerPrefix(PREFIX)
    elseif event == "PLAYER_LOGIN" then
        RaceGrid:Refresh()
        -- Custom channels may not be ready in the first login event.  Retry
        -- shortly afterwards so external RaceLocked data is available even
        -- when iRC global sharing is disabled.
        if C_Timer and C_Timer.After then
            C_Timer.After(3, function() RaceGrid:EnsureRaceLockedChannels() end)
        end
        if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(REPORT_INTERVAL, function() RaceGrid:BroadcastReport() end) end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, _, sender = ...
        handleMessage(prefix, message, sender)
    elseif event == "CHAT_MSG_CHANNEL" then
        local message = ...
        local channelName = select(9, ...)
        if RACELOCKED_CHANNEL_LOOKUP[channelName] then
            local report = parseRaceLockedGuildReport(message, channelName)
            if report then
                RaceGrid:StoreRaceLockedGuildReport(report)
                iRC:DebugMsg(iRC:Text("RACEGRID_REPORT_RECEIVED", report.source, report.guildName, report.members, report.averageLevel), 3)
            end
        end
    end
end)
