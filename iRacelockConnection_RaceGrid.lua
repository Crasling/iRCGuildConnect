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
-- separate text channels. External messages always use the native protocol.
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

-- Fixed ForkEU guild slots shared by the overview display and its data filter.
-- Races without a configured guild must not accumulate overview statistics.
local OVERVIEW_GUILDS = {
    HUMAN = "Northshire Survivors",
    NIGHTELF = "Children of Elune",
    TROLL = "Darkspear Tribe",
    TAUREN = "Fear The Beef",
    SCOURGE = "WE are FORSAKEN",
}

function iRC:GetRaceOverviewGuildName(race)
    return OVERVIEW_GUILDS[race]
end

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
    if distribution == "CHANNEL" then
        local id = GetChannelName and GetChannelName(target)
        local wire = prefix .. ":" .. message:gsub(".", function(char) return string.format("%02x", string.byte(char)) end)
        if SendChatMessage and type(id) == "number" and id > 0 and #wire <= 255 then
            SendChatMessage(wire, "CHANNEL", nil, id)
            return true
        end
        return false
    end
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

local function validNumber(value, minimum, maximum, preserveFraction)
    value = tonumber(value)
    if not value or value ~= value or value < minimum or value > maximum then return nil end
    return preserveFraction and value or math.floor(value)
end

local function normalizeGuildName(name)
    return string.lower((tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")))
end

local function isOverviewGuild(race, guildName)
    local expected = OVERVIEW_GUILDS[race]
    return expected ~= nil and normalizeGuildName(guildName) == normalizeGuildName(expected)
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
        points = 0,
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
    if not isOverviewGuild(report.race, report.guildName) then return end
    iRCDB = iRCDB or {}
    iRCDB.globalRaceGrid = iRCDB.globalRaceGrid or { members = {} }
    iRCDB.globalRaceGrid.raceLockedGuildReports = iRCDB.globalRaceGrid.raceLockedGuildReports or {}
    -- Received relays retain the origin timestamp; hearing stale data again
    -- must not turn it into a fresh report.
    report.lastSeen = report.timestamp and report.timestamp > 0 and report.timestamp or time()
    local key = report.race .. "@" .. normalizeGuildName(report.guildName)
    local old = iRCDB.globalRaceGrid.raceLockedGuildReports[key]
    if old and (old.timestamp or 0) > (report.timestamp or 0) then return false end
    if old then
        if old.guildDeaths ~= nil or report.guildDeaths ~= nil then report.guildDeaths = math.max(old.guildDeaths or 0, report.guildDeaths or 0) end
        if report.membersLevel60 == nil then report.membersLevel60 = old.membersLevel60 end
        if report.classAverageLevels == nil then report.classAverageLevels = old.classAverageLevels end
    end
    iRCDB.globalRaceGrid.raceLockedGuildReports[key] = report
    return true
end

local function parseRaceLockedGuildReport(message, channelName)
    if type(message) ~= "string" or #message > 255 or message:sub(1, #RACELOCKED_WIRE_PREFIX) ~= RACELOCKED_WIRE_PREFIX then return nil end
    local payload = hexToBytes(message:sub(#RACELOCKED_WIRE_PREFIX + 1))
    if not payload then return nil end
    local fields = {}
    for value in (payload .. RACELOCKED_FIELD_SEPARATOR):gmatch("(.-)" .. RACELOCKED_FIELD_SEPARATOR) do fields[#fields + 1] = value end
    local version = fields[1]
    -- ForkEU v3 has 16 fields; original v3 has class count/average pairs.
    local paired = (version == "v3" and #fields >= 24) or version == "v4" or version == "v5"
    local required = version == "v5" and 27 or (version == "v4" and 25 or
        (version == "v3" and (paired and 24 or 16) or (version == "v2" and 15 or (version == "v1" and 14))))
    if not required or #fields < required then return nil end
    local race = RACELOCKED_RACE_TOKENS[fields[2]]
    local guildName = fields[3]
    local members = validNumber(fields[4], 1, 10000)
    local averageLevel = validNumber(fields[5], 1, 100)
    if not race or not guildName or guildName == "" or not members or not averageLevel then return nil end
    if not isOverviewGuild(race, guildName) then return nil end
    local classes, classAverageLevels, total = {}, paired and {} or nil, 0
    local index = 6
    for _, classKey in ipairs({ "druids", "rogues", "hunters", "warriors", "mages", "priests", "warlocks", "paladins", "shamans" }) do
        local count = validNumber(fields[index], 0, members)
        if not count then return nil end
        classes[RACELOCKED_CLASS_KEYS[classKey]] = count
        total = total + count
        if paired then
            local average = validNumber(fields[index + 1], 0, 100)
            if not average then return nil end
            classAverageLevels[RACELOCKED_CLASS_KEYS[classKey]] = average
        end
        index = index + (paired and 2 or 1)
    end
    if total > members then return nil end
    local stamp = version == "v1" and 0 or validNumber(fields[paired and 24 or 15], 0, time() + 300)
    if not stamp then return nil end
    local averagePoints = paired and tonumber(fields[26]) or nil
    local deaths = paired and fields[25] and validNumber(fields[25], 0, 10000000) or nil
    local maxLevelCount = paired and fields[27] and validNumber(fields[27], 0, members) or nil
    if (version == "v4" or version == "v5") and deaths == nil then return nil end
    if version == "v5" and (averagePoints == nil or maxLevelCount == nil) then return nil end
    local points = averagePoints and averagePoints * members or (not paired and version == "v3" and tonumber(fields[16]) or 0)
    if not validNumber(points, 0, 100000000000) then return nil end
    return {
        source = channelName == "RaceLockedForkEUDataBus" and "RaceLockedForkEU global guild report" or "RaceLocked global guild report",
        race = race, guildName = guildName,
        members = members, averageLevel = averageLevel, points = points, classes = classes,
        timestamp = stamp, classAverageLevels = classAverageLevels,
        guildDeaths = deaths, membersLevel60 = maxLevelCount,
        averagePoints = averagePoints, wireVersion = version, channel = channelName,
    }
end

RaceGrid.ParseExternalReport = function(_, message, channelName) return parseRaceLockedGuildReport(message, channelName) end

-- Native overviews retain whole-guild snapshots between sessions. Read these
-- tables without calling native update functions or modifying their saved data.
function RaceGrid:ImportNativeCaches()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    for _, addon in ipairs({ "RaceLocked", "RaceLockedForkEU" }) do
        if loaded and loaded(addon) then
            local live, saved = _G[addon .. "_GuildChampion"], _G[addon .. "AccountDB"]
            local byRace = type(live) == "table" and live.RACE_GRID_STORED_GUILD_REPORTS_BY_RACE
            if type(byRace) ~= "table" then byRace = type(saved) == "table" and saved.raceGridStoredGuildReportsByRace end
            for token, rows in pairs(type(byRace) == "table" and byRace or {}) do
                local race = normalizeRaceToken(token)
                for _, row in pairs(type(rows) == "table" and rows or {}) do
                    if type(row) == "table" and isOverviewGuild(race, row.guildName) then
                        local members = validNumber(row.guildSize, 1, 10000)
                        local average = validNumber(row.averageLevel, 1, 100, true)
                        local stamp = validNumber(row.timestamp or 0, 0, time() + 300)
                        local classes, averages, total, valid = {}, {}, 0, true
                        for native, class in pairs(RACELOCKED_CLASS_KEYS) do
                            local entry = type(row.classes) == "table" and row.classes[native] or 0
                            local count = validNumber(type(entry) == "table" and entry.count or entry or 0, 0, members or 0)
                            if not count then valid = false break end
                            classes[class], total = count, total + count
                            if type(entry) == "table" then averages[class] = validNumber(entry.averageLevel, 0, 100, true) end
                        end
                        if members and average and stamp and valid and total <= members then
                            local report = {
                                race = race, guildName = OVERVIEW_GUILDS[race], members = members,
                                averageLevel = average, points = 0, classes = classes,
                                timestamp = stamp, source = addon, importedCache = true,
                                classAverageLevels = next(averages) and averages or nil,
                                guildDeaths = validNumber(row.guildDeaths, 0, 10000000),
                                membersLevel60 = validNumber(row.guildMembersLevel60, 0, members),
                                averagePoints = nil,
                            }
                            local reports = iRCDB and iRCDB.globalRaceGrid and iRCDB.globalRaceGrid.raceLockedGuildReports or {}
                            local old = reports[race .. "@" .. normalizeGuildName(row.guildName)]
                            if self:StoreRaceLockedGuildReport(report) and (not old or old.timestamp ~= stamp or old.members ~= members) then
                                iRC:DebugMsg(iRC:Text("RL_GRID_CACHE_IMPORTED", addon, report.guildName, members), 3)
                            end
                        end
                    end
                end
            end
        end
    end
end

function RaceGrid:EncodeExternalReport(report, channelName)
    if not isOverviewGuild(report.race, report.guildName) then return nil end
    local raceToken
    for token, race in pairs(RACELOCKED_RACE_TOKENS) do if race == report.race then raceToken = token break end end
    if not raceToken then return nil end
    local original = channelName == "RaceLockedDataBus"
    local function integer(value) return tostring(math.max(0, math.floor(tonumber(value) or 0))) end
    local fields = { original and "v5" or "v3", raceToken, OVERVIEW_GUILDS[report.race], integer(report.members), integer(report.averageLevel) }
    for _, class in ipairs({ "DRUID", "ROGUE", "HUNTER", "WARRIOR", "MAGE", "PRIEST", "WARLOCK", "PALADIN", "SHAMAN" }) do
        fields[#fields + 1] = integer((report.classes or {})[class])
        if original then fields[#fields + 1] = integer((report.classAverageLevels or {})[class]) end
    end
    fields[#fields + 1] = integer(report.timestamp)
    if original then
        fields[#fields + 1] = integer(report.guildDeaths)
        fields[#fields + 1] = integer(report.members > 0 and report.points / report.members or 0)
        fields[#fields + 1] = integer(report.membersLevel60)
    else fields[#fields + 1] = integer(report.points) end
    local bytes = table.concat(fields, RACELOCKED_FIELD_SEPARATOR)
    local wire = RACELOCKED_WIRE_PREFIX .. bytes:gsub(".", function(char) return string.format("%02x", string.byte(char)) end)
    return #wire <= 255 and wire or nil
end

local externalRelayCache, externalReady, lastExternalBroadcast = {}, false, nil

-- Overview population is historical addon participation, not live presence.
-- Only current roster members are considered; cached records of leavers are
-- never iterated here. Officer verification still uses its live timeouts.
function RaceGrid:GetRosterParticipation(member)
    if iRC:NormalizeName(member.name) == iRC:NormalizeName(iRC:GetPlayerName()) then return "verified" end
    local state = member.verification and member.verification.state
    if state == "verified" or state == "compatible" then return state end
    if member.profile and (tonumber(member.profile.lastSeen) or 0) > 0 then return "verified" end
    local compatible = member.compatibilityMember or {}
    for _, entry in pairs({ stats = member.compatibility, presence = compatible.presence, guildFound = compatible.guildFound }) do
        if type(entry) == "table" and (tonumber(entry.lastSeen) or 0) > 0 then return "compatible" end
    end
    if iRC.RaceLockedSync then
        local status = member.raceLockedStatus
        if not member.hasParticipationSnapshot then status = iRC.RaceLockedSync:GetStatus(member.name) end
        if status and (tonumber(status.lastSeen) or 0) > 0 then return "compatible" end
    end
end

function RaceGrid:BuildOwnGuildReports()
    local connection = iRC:GetConnection()
    if not connection or not iRC:IsGuildConnectionActive() then return {} end
    local guildRace
    for race, guild in pairs(OVERVIEW_GUILDS) do
        if normalizeGuildName(guild) == normalizeGuildName(connection.guildName) then guildRace = race break end
    end
    if not guildRace then return {} end
    local groups, counted = {}, {}
    for _, member in ipairs(iRC:GetGuildRosterRows()) do
        local participation = self:GetRosterParticipation(member)
        local key = iRC:NormalizeName(member.name)
        -- The fixed slot represents this guild. Do not require a race lookup
        -- for each offline character; the game may not have that GUID cached.
        local race = guildRace
        if key ~= "" and participation and not counted[key] then
            counted[key] = true
            local group = groups[race]
            if not group then
                group = { race = race, guildName = OVERVIEW_GUILDS[race], members = 0, totalLevel = 0, points = 0,
                    classes = {}, classTotals = {}, classAverageLevels = {}, membersLevel60 = 0,
                    verifiedMembers = 0, compatibleMembers = 0, populationSource = "verified_compatible",
                    guildDeaths = (connection.raceDeaths or {})[race] or 0, timestamp = time() }
                groups[race] = group
            end
            local level, class = member.level or 1, member.class or "UNKNOWN"
            group.members, group.totalLevel = group.members + 1, group.totalLevel + level
            if participation == "verified" then group.verifiedMembers = group.verifiedMembers + 1
            else group.compatibleMembers = group.compatibleMembers + 1 end
            group.classes[class] = (group.classes[class] or 0) + 1
            group.classTotals[class] = (group.classTotals[class] or 0) + level
            if level >= 60 then group.membersLevel60 = group.membersLevel60 + 1 end
        end
    end
    local result = {}
    for _, group in pairs(groups) do
        group.averageLevel = group.totalLevel / group.members
        group.averagePoints = nil
        for class, count in pairs(group.classes) do group.classAverageLevels[class] = group.classTotals[class] / count end
        result[#result + 1] = group
    end
    return result
end

local function externalAddonLoaded(channelName)
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    return loaded and loaded(channelName == "RaceLockedDataBus" and "RaceLocked" or "RaceLockedForkEU")
end

function RaceGrid:IsExternalBroadcaster()
    if not self:IsEnabled() or not iRC:IsGuildConnectionActive() then return false end
    local ownName = iRC:NormalizeName(iRC:GetPlayerName())
    for _, member in ipairs(iRC:GetGuildRosterRows()) do
        local profile = member.profile
        if member.online and profile and profile.shareGlobalRaceGrid and profile.lastSeen
            and time() - profile.lastSeen <= 135 and iRC:NormalizeName(member.name) < ownName then return false end
    end
    return true
end

function RaceGrid:BroadcastExternalReports(fromClick)
    -- CHANNEL chat is protected on Classic. Never defer this send into a timer,
    -- nor respond to network events with public chat; retain the hardware click.
    if fromClick ~= true or not externalReady or not self:IsExternalBroadcaster() then return end
    if lastExternalBroadcast and GetTime() - lastExternalBroadcast < REPORT_INTERVAL then return end
    lastExternalBroadcast = GetTime()
    self:EnsureRaceLockedChannels()
    local outgoing, own = {}, self:BuildOwnGuildReports()
    local connection = iRC:GetConnection()
    local ownGuild = normalizeGuildName(connection.guildName)
    for _, channel in ipairs(RACELOCKED_CHANNELS) do
        if not externalAddonLoaded(channel) then
            for _, report in ipairs(own) do
                local wire = self:EncodeExternalReport(report, channel)
                if wire then outgoing[#outgoing + 1] = { channel = channel, wire = wire } end
            end
            for _, cached in pairs(externalRelayCache[channel] or {}) do
                if normalizeGuildName(cached.report.guildName) ~= ownGuild
                    and time() - cached.report.timestamp <= STALE_AFTER then
                    outgoing[#outgoing + 1] = { channel = channel, wire = cached.wire }
                end
            end
        end
    end
    for _, packet in ipairs(outgoing) do
        local id = getChannelId(packet.channel)
        if id and SendChatMessage then
            SendChatMessage(packet.wire, "CHANNEL", nil, id)
            iRC:DebugMsg(iRC:Text("RL_GRID_SENT", packet.channel), 3)
        end
    end
end

function RaceGrid:BroadcastReport(fromClick)
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
    if fromClick ~= true or not send(PREFIX, payload, "CHANNEL", CHANNEL_NAME) then return false end
    iRC:DebugMsg(iRC:Text("RACEGRID_REPORT_SENT", report.name, report.race, report.level, report.guildName ~= "" and report.guildName or iRC:Text("RACEGRID_NO_GUILD")), 3)
    return true
end

function RaceGrid:RequestReports(fromClick)
    if fromClick ~= true or not self:IsEnabled() then return false end
    self:EnsureChannel()
    if not getChannelId() then return false end
    if not send(PREFIX, table.concat({ "REQUEST", WIRE_VERSION }, SEP), "CHANNEL", CHANNEL_NAME) then return false end
    iRC:DebugMsg(iRC:Text("RACEGRID_REQUEST_SENT"), 3)
    return true
end

local lastClickPublish
-- Only call synchronously from an actual UI OnClick handler.
function RaceGrid:PublishFromClick()
    self:ImportNativeCaches()
    if lastClickPublish and GetTime() - lastClickPublish < 5 then return end
    lastClickPublish = GetTime()
    self:BroadcastReport(true)
    self:RequestReports(true)
    self:BroadcastExternalReports(true)
end

function RaceGrid:Refresh()
    iRC:DebugMsg(iRC:Text("RACEGRID_INITIALIZED", iRC:Text(self:IsEnabled() and "RACEGRID_SHARING_ENABLED" or "RACEGRID_SHARING_DISABLED")), 3)
    if not self:IsEnabled() then return end
    self:EnsureChannel()
    if C_Timer and C_Timer.After then
        C_Timer.After(2, function()
            RaceGrid:BroadcastReport()
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
    local connection = self:GetConnection()
    local ownGuild = connection and normalizeGuildName(connection.guildName) or ""
    for key, report in pairs(stored) do
        if type(report) ~= "table" or now - (tonumber(report.lastSeen) or 0) > STALE_AFTER then
            stored[key] = nil
        elseif isOverviewGuild(report.race, report.guildName) and normalizeGuildName(report.guildName) ~= ownGuild then
            local group = groups[report.race]
            if not group then
                group = {
                    race = report.race,
                    faction = ALLIANCE_RACES[report.race] and "Alliance" or "Horde",
                    members = 0, totalLevel = 0, points = 0, addonUsers = 0, selfFound = 0,
                    classes = {}, guildName = OVERVIEW_GUILDS[report.race],
                }
                groups[report.race] = group
            end
            group.members = group.members + 1
            group.totalLevel = group.totalLevel + report.level
            group.addonUsers = group.addonUsers + 1
            if report.selfFound then group.selfFound = group.selfFound + 1 end
            group.classes[report.class] = (group.classes[report.class] or 0) + 1
        end
    end
    local result = {}
    for _, group in pairs(groups) do
        group.averageLevel = math.floor((group.totalLevel / group.members) * 10 + 0.5) / 10
        result[#result + 1] = group
    end
    table.sort(result, function(a, b) return a.race < b.race end)
    return result
end

function iRC:GetRaceGridOverview()
    RaceGrid:ImportNativeCaches()
    local iRCGlobalEnabled = RaceGrid:IsEnabled()
    local globalGroups = iRCGlobalEnabled and self:GetGlobalRaceOverview() or {}
    local groupsByRace = {}
    for _, group in ipairs(globalGroups) do
        group.totalLevel = (group.averageLevel or 0) * (group.members or 0)
        groupsByRace[group.race] = group
    end

    for _, group in ipairs(RaceGrid:BuildOwnGuildReports()) do
        group.faction = ALLIANCE_RACES[group.race] and "Alliance" or "Horde"
        groupsByRace[group.race] = group
    end

    local raceLockedReports = iRCDB and iRCDB.globalRaceGrid and iRCDB.globalRaceGrid.raceLockedGuildReports or {}
    local hasRaceLockedData, externalReportCount = false, 0
    for key, report in pairs(raceLockedReports) do
        if type(report) ~= "table" then
            raceLockedReports[key] = nil
        elseif isOverviewGuild(report.race, report.guildName) and (tonumber(report.members) or 0) > 0
            and not (groupsByRace[report.race] and groupsByRace[report.race].populationSource == "verified_compatible") then
            hasRaceLockedData = true
            externalReportCount = externalReportCount + 1
            -- Achievement statistics are paused. Native snapshots provide
            -- population/class data only.
            local group = {
                race = report.race,
                faction = ALLIANCE_RACES[report.race] and "Alliance" or "Horde",
                members = 0, totalLevel = 0, points = 0, addonUsers = 0, selfFound = 0,
                classes = {}, guildName = OVERVIEW_GUILDS[report.race],
            }
            groupsByRace[report.race] = group
            group.members = group.members + (report.members or 0)
            group.totalLevel = group.totalLevel + (report.averageLevel or 0) * (report.members or 0)
            group.points = 0
            group.addonUsers = group.addonUsers + (report.members or 0)
            for class, count in pairs(report.classes or {}) do group.classes[class] = (group.classes[class] or 0) + count end
            group.guildDeaths, group.membersLevel60 = report.guildDeaths, report.membersLevel60
            group.classAverageLevels, group.timestamp = report.classAverageLevels, report.timestamp
            group.averagePoints = nil
            group.source = report.source
            group.cached = not report.timestamp or report.timestamp == 0 or time() - report.timestamp > STALE_AFTER
        end
    end

    local result = {}
    for _, group in pairs(groupsByRace) do
        group.averageLevel = group.members > 0 and math.floor((group.totalLevel / group.members) * 10 + 0.5) / 10 or 0
        group.totalLevel = nil
        group.points, group.averagePoints = 0, nil
        result[#result + 1] = group
    end
    table.sort(result, function(a, b) return a.race < b.race end)
    local source = hasRaceLockedData and iRCGlobalEnabled and "combined" or (hasRaceLockedData and "racelocked" or (iRCGlobalEnabled and "global" or "guild"))
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
        -- Let WoW finish restoring the player's normal chat channels before
        -- adding any hidden data channels.
        if C_Timer and C_Timer.After then
            C_Timer.After(6, function()
                externalReady = true
                RaceGrid:Refresh()
                RaceGrid:EnsureRaceLockedChannels()
            end)
        else
            externalReady = true
            RaceGrid:Refresh()
            RaceGrid:EnsureRaceLockedChannels()
        end
        if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(REPORT_INTERVAL, function()
            RaceGrid:BroadcastReport()
        end) end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, _, sender = ...
        handleMessage(prefix, message, sender)
    elseif event == "CHAT_MSG_CHANNEL" then
        local message, sender = ...
        local channelName = select(9, ...)
        if channelName == CHANNEL_NAME and type(message) == "string" and message:sub(1, #PREFIX + 1) == PREFIX .. ":" then
            local decoded = hexToBytes(message:sub(#PREFIX + 2))
            if decoded then handleMessage(PREFIX, decoded, sender) end
        elseif RACELOCKED_CHANNEL_LOOKUP[channelName] then
            local report = parseRaceLockedGuildReport(message, channelName)
            if report then
                RaceGrid:StoreRaceLockedGuildReport(report)
                externalRelayCache[channelName] = externalRelayCache[channelName] or {}
                local cached = externalRelayCache[channelName][report.race]
                if report.timestamp > 0 and (not cached or report.timestamp > cached.report.timestamp) then
                    externalRelayCache[channelName][report.race] = { report = report, wire = message }
                end
                local connection = iRC:GetConnection()
                if connection and normalizeGuildName(connection.guildName) == normalizeGuildName(report.guildName) and report.guildDeaths then
                    connection.raceDeaths = connection.raceDeaths or {}
                    connection.raceDeaths[report.race] = math.max(connection.raceDeaths[report.race] or 0, report.guildDeaths)
                end
                iRC:DebugMsg(iRC:Text("RACEGRID_REPORT_RECEIVED", report.source, report.guildName, report.members, report.averageLevel), 3)
                if iRC.AchievementsUI then iRC.AchievementsUI:RefreshIfShown() end
            end
        end
    end
end)
