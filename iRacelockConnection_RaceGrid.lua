local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local RaceGrid = {}
iRC.RaceGrid = RaceGrid

local PREFIX = "iRCGridV1"
local CHANNEL_NAME = "iRacelockConnection"
local WIRE_VERSION = "2"
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

local function getServerStore()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or (GetRealmName and GetRealmName()) or "Unknown"
    local serverKey = string.lower(tostring(realm):gsub("%s+", ""))
    iRCDB = iRCDB or {}
    iRCDB.globalRaceGrid = iRCDB.globalRaceGrid or {}
    iRCDB.globalRaceGrid.servers = iRCDB.globalRaceGrid.servers or {}
    local store = iRCDB.globalRaceGrid.servers[serverKey]
    if not store then
        store = { guildReports = {}, raceLockedGuildReports = {} }
        iRCDB.globalRaceGrid.servers[serverKey] = store
    end
    store.guildReports = store.guildReports or {}
    store.raceLockedGuildReports = store.raceLockedGuildReports or {}
    store.guildActivity = store.guildActivity or {}
    return store
end

local function recordGuildActivity(guildName, onlinePlayers)
    local activity = getServerStore().guildActivity
    local key, now = normalizeGuildName(guildName), time()
    local samples = activity[key]
    if type(samples) ~= "table" then
        samples = {}
        activity[key] = samples
    end
    local retained = {}
    for _, sample in ipairs(samples) do
        if type(sample) == "table" and (tonumber(sample.timestamp) or 0) >= now - 86400 then
            retained[#retained + 1] = sample
        end
    end
    samples = retained
    activity[key] = samples
    local current = math.max(0, math.floor(tonumber(onlinePlayers) or 0))
    local latest = samples[#samples]
    if latest and latest.players == current then
        latest.timestamp = now
    else
        samples[#samples + 1] = { timestamp = now, players = current }
    end
    local peak = current
    for _, sample in ipairs(samples) do peak = math.max(peak, tonumber(sample.players) or 0) end
    return peak
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
    local reports = self:BuildOwnGuildReports()
    local guild = reports[1]
    if not guild then return {} end
    return {
        name = profile.name,
        guid = profile.guid,
        guildName = guild.guildName, race = guild.race, faction = guild.faction,
        members = guild.members, activePlayers = guild.activePlayers,
        membersLevel60 = guild.membersLevel60, averageLevel = guild.averageLevel,
        classes = guild.classes, guildDeaths = guild.guildDeaths,
        rules = guild.rules, rulesKnown = guild.rulesKnown,
        source = "iRC guild report", timestamp = time(), lastSeen = time(),
    }
end

function RaceGrid:StoreGuildReport(report, silent)
    if type(report) ~= "table" or type(report.guildName) ~= "string" or report.guildName == "" then return false end
    report.race = normalizeRaceToken(report.race)
    if not report.race then return false end
    local reports = getServerStore().guildReports
    local key = normalizeGuildName(report.guildName)
    local old = reports[key]
    if old and (tonumber(old.timestamp) or 0) > (tonumber(report.timestamp) or 0) then return false end
    report.activePlayers = recordGuildActivity(report.guildName, report.activePlayers)
    report.faction = ALLIANCE_RACES[report.race] and "Alliance" or "Horde"
    report.lastSeen = time()
    reports[key] = report
    if not silent and iRC.AchievementsUI then iRC.AchievementsUI:RefreshIfShown() end
    return true
end

function RaceGrid:StoreRaceLockedGuildReport(report)
    if type(report) ~= "table" or not report.race or not report.guildName then return end
    report.race = normalizeRaceToken(report.race)
    if not report.race or report.guildName == "" or #report.guildName > 80 then return end
    local reports = getServerStore().raceLockedGuildReports
    -- Received relays retain the origin timestamp; hearing stale data again
    -- must not turn it into a fresh report.
    report.lastSeen = report.timestamp and report.timestamp > 0 and report.timestamp or time()
    local key = report.race .. "@" .. normalizeGuildName(report.guildName)
    local old = reports[key]
    if old and (old.timestamp or 0) > (report.timestamp or 0) then return false end
    if old then
        if old.guildDeaths ~= nil or report.guildDeaths ~= nil then report.guildDeaths = math.max(old.guildDeaths or 0, report.guildDeaths or 0) end
        if report.membersLevel60 == nil then report.membersLevel60 = old.membersLevel60 end
        if report.classAverageLevels == nil then report.classAverageLevels = old.classAverageLevels end
    end
    reports[key] = report
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
                    if type(row) == "table" and race and type(row.guildName) == "string" and row.guildName ~= "" then
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
                                race = race, guildName = row.guildName, members = members,
                                averageLevel = average, points = 0, classes = classes,
                                timestamp = stamp, source = addon, importedCache = true,
                                classAverageLevels = next(averages) and averages or nil,
                                guildDeaths = validNumber(row.guildDeaths, 0, 10000000),
                                membersLevel60 = validNumber(row.guildMembersLevel60, 0, members),
                                averagePoints = nil,
                            }
                            local reports = getServerStore().raceLockedGuildReports
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
    if not normalizeRaceToken(report.race) or type(report.guildName) ~= "string" or report.guildName == "" then return nil end
    local raceToken
    for token, race in pairs(RACELOCKED_RACE_TOKENS) do if race == report.race then raceToken = token break end end
    if not raceToken then return nil end
    local original = channelName == "RaceLockedDataBus"
    local function integer(value) return tostring(math.max(0, math.floor(tonumber(value) or 0))) end
    local fields = { original and "v5" or "v3", raceToken, report.guildName, integer(report.members), integer(report.averageLevel) }
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

local externalReady, lastExternalBroadcast = false, nil

-- Verification and compatible participation remain useful metadata, but the
-- guild statistics themselves count the complete current roster.
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
    local guildRace = normalizeRaceToken(iRC:GetGuildRace())
    local guildName = tostring(connection.guildName or (GetGuildInfo and GetGuildInfo("player")) or "")
    if not guildRace or guildName == "" then return {} end
    local rules = iRC:GetConnectionRules() or {}
    local group = {
        race = guildRace, faction = ALLIANCE_RACES[guildRace] and "Alliance" or "Horde",
        guildName = guildName, members = 0, activePlayers = 0, totalLevel = 0, points = 0,
        classes = {}, classTotals = {}, classAverageLevels = {}, membersLevel60 = 0,
        verifiedMembers = 0, compatibleMembers = 0, populationSource = "irc_guild_roster",
        guildDeaths = (connection.raceDeaths or {})[guildRace] or 0, timestamp = time(), source = "iRC",
        rulesKnown = true,
        rules = {
            nativeTongueOnly = rules.nativeTongueOnly and true or false,
            selfFoundOnly = rules.selfFoundOnly and true or false,
            level60GuildFound = rules.level60GuildFound and true or false,
            allowLevel60WithoutSelfFound = rules.allowLevel60WithoutSelfFound and true or false,
            sameRaceGroupsOnly = rules.sameRaceGroupsOnly and true or false,
            allowLevel60MixedRaceGroups = rules.allowLevel60MixedRaceGroups and true or false,
            guildGroupsOnly = rules.guildGroupsOnly and true or false,
            sameRaceMinimumLevel = tonumber(rules.sameRaceMinimumLevel) or 1,
            guildGroupsMinimumLevel = tonumber(rules.guildGroupsMinimumLevel) or 1,
        },
    }
    local counted = {}
    for _, member in ipairs(iRC:GetGuildRosterRows()) do
        local participation = self:GetRosterParticipation(member)
        local key = iRC:NormalizeName(member.name)
        if key ~= "" and not counted[key] then
            counted[key] = true
            local level, class = member.level or 1, member.class or "UNKNOWN"
            group.members, group.totalLevel = group.members + 1, group.totalLevel + level
            if member.online then group.activePlayers = group.activePlayers + 1 end
            if participation == "verified" then group.verifiedMembers = group.verifiedMembers + 1
            elseif participation == "compatible" then group.compatibleMembers = group.compatibleMembers + 1 end
            if level >= 19 then
                group.classes[class] = (group.classes[class] or 0) + 1
                group.classTotals[class] = (group.classTotals[class] or 0) + level
            end
            if level >= 60 then group.membersLevel60 = group.membersLevel60 + 1 end
        end
    end
    if group.members == 0 then return {} end
    group.activePlayers = recordGuildActivity(guildName, group.activePlayers)
    group.averageLevel = group.totalLevel / group.members
    group.averagePoints = nil
    for class, count in pairs(group.classes) do group.classAverageLevels[class] = group.classTotals[class] / count end
    group.totalLevel, group.classTotals = nil, nil
    return { group }
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
    for _, channel in ipairs(RACELOCKED_CHANNELS) do
        if not externalAddonLoaded(channel) then
            for _, report in ipairs(own) do
                local wire = self:EncodeExternalReport(report, channel)
                if wire then outgoing[#outgoing + 1] = { channel = channel, wire = wire } end
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
    local fields = {
        "GUILD_REPORT", WIRE_VERSION, report.name, report.guid, report.guildName, report.race,
        tostring(report.membersLevel60 or 0), tostring(report.activePlayers or 0), tostring(report.members or 0),
        tostring(report.averageLevel or 0), tostring(report.timestamp or time()), tostring(report.guildDeaths or 0),
    }
    for _, class in ipairs({ "DRUID", "ROGUE", "HUNTER", "WARRIOR", "MAGE", "PRIEST", "WARLOCK", "PALADIN", "SHAMAN" }) do
        fields[#fields + 1] = tostring((report.classes or {})[class] or 0)
    end
    local rules, ruleMask = report.rules or {}, 0
    for _, entry in ipairs({
        { "nativeTongueOnly", 1 }, { "selfFoundOnly", 2 }, { "level60GuildFound", 4 },
        { "allowLevel60WithoutSelfFound", 8 }, { "sameRaceGroupsOnly", 16 },
        { "allowLevel60MixedRaceGroups", 32 }, { "guildGroupsOnly", 64 },
    }) do
        if rules[entry[1]] then ruleMask = ruleMask + entry[2] end
    end
    fields[#fields + 1] = tostring(ruleMask)
    fields[#fields + 1] = tostring(math.max(1, math.min(60, tonumber(rules.sameRaceMinimumLevel) or 1)))
    fields[#fields + 1] = tostring(math.max(1, math.min(60, tonumber(rules.guildGroupsMinimumLevel) or 1)))
    local payload = table.concat(fields, SEP)
    if #payload > 255 then return false end
    self:StoreGuildReport(report)
    if fromClick ~= true or not send(PREFIX, payload, "CHANNEL", CHANNEL_NAME) then return false end
    iRC:DebugMsg(iRC:Text("RACEGRID_GUILD_REPORT_SENT", report.guildName, report.membersLevel60, report.activePlayers, report.members), 3)
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

local function parseGuildReport(parts)
    if parts[1] ~= "GUILD_REPORT" or parts[2] ~= WIRE_VERSION then return nil end
    local name, guid, guildName, race = parts[3], parts[4], parts[5], normalizeRaceToken(parts[6])
    local level60 = validNumber(parts[7], 0, 10000)
    local active = validNumber(parts[8], 0, 10000)
    local members = validNumber(parts[9], 1, 10000)
    local averageLevel = validNumber(parts[10], 1, 100, true)
    local timestamp = validNumber(parts[11], 0, time() + 300)
    local deaths = validNumber(parts[12], 0, 10000000)
    if not name or name == "" or #name > 80 or not guid or guid == "" or #guid > 80 then return nil end
    if not guildName or guildName == "" or #guildName > 80 or not race or not level60 or not active or not members or not averageLevel or not timestamp or not deaths then return nil end
    if level60 > members or active > members then return nil end
    local classes, classTotal = {}, 0
    for index, class in ipairs({ "DRUID", "ROGUE", "HUNTER", "WARRIOR", "MAGE", "PRIEST", "WARLOCK", "PALADIN", "SHAMAN" }) do
        local count = validNumber(parts[12 + index], 0, members)
        if not count then return nil end
        classes[class], classTotal = count, classTotal + count
    end
    if classTotal > members then return nil end
    local rules, rulesKnown
    if parts[22] ~= nil then
        local mask = validNumber(parts[22], 0, 127)
        local sameRaceLevel = validNumber(parts[23], 1, 60)
        local guildGroupsLevel = validNumber(parts[24], 1, 60)
        if not mask or not sameRaceLevel or not guildGroupsLevel then return nil end
        local function enabled(flag) return math.floor(mask / flag) % 2 == 1 end
        rulesKnown = true
        rules = {
            nativeTongueOnly = enabled(1), selfFoundOnly = enabled(2),
            level60GuildFound = enabled(4), allowLevel60WithoutSelfFound = enabled(8),
            sameRaceGroupsOnly = enabled(16), allowLevel60MixedRaceGroups = enabled(32),
            guildGroupsOnly = enabled(64), sameRaceMinimumLevel = sameRaceLevel,
            guildGroupsMinimumLevel = guildGroupsLevel,
        }
    end
    return {
        name = name, guid = guid, guildName = guildName, race = race,
        membersLevel60 = level60, activePlayers = active, members = members,
        averageLevel = averageLevel, timestamp = timestamp, guildDeaths = deaths,
        classes = classes, rules = rules, rulesKnown = rulesKnown,
        source = "iRC guild report",
    }
end

local function handleMessage(prefix, message, sender)
    if prefix ~= PREFIX or not RaceGrid:IsEnabled() then return end
    if iRC:NormalizeName(sender) == iRC:NormalizeName(iRC:GetPlayerName()) then return end
    local parts = split(message)
    if parts[1] == "REQUEST" and (parts[2] == WIRE_VERSION or parts[2] == "1") then
        iRC:DebugMsg(iRC:Text("RACEGRID_REQUEST_RECEIVED", sender), 3)
        return
    end
    local report = parseGuildReport(parts)
    if not report or fullNameKey(report.name) ~= fullNameKey(sender) then return end
    RaceGrid:StoreGuildReport(report)
    iRC:DebugMsg(iRC:Text("RACEGRID_GUILD_REPORT_RECEIVED", report.guildName, report.membersLevel60, report.activePlayers, report.members), 3)
end

function iRC:GetGlobalRaceOverview()
    local stored = getServerStore().guildReports
    local result = {}
    for _, report in pairs(stored) do
        if type(report) == "table" and normalizeRaceToken(report.race) and (tonumber(report.members) or 0) > 0 then
            report.cached = not report.timestamp or time() - report.timestamp > STALE_AFTER
            result[#result + 1] = report
        end
    end
    return result
end

local function guildRank(a, b)
    if (a.membersLevel60 or 0) ~= (b.membersLevel60 or 0) then return (a.membersLevel60 or 0) > (b.membersLevel60 or 0) end
    if (a.activePlayers or 0) ~= (b.activePlayers or 0) then return (a.activePlayers or 0) > (b.activePlayers or 0) end
    if (a.members or 0) ~= (b.members or 0) then return (a.members or 0) > (b.members or 0) end
    return normalizeGuildName(a.guildName) < normalizeGuildName(b.guildName)
end

function iRC:GetRaceGridOverview()
    RaceGrid:ImportNativeCaches()
    local groups = {}
    if RaceGrid:IsEnabled() then
        for _, report in ipairs(self:GetGlobalRaceOverview()) do groups[normalizeGuildName(report.guildName)] = report end
    end
    for _, report in ipairs(RaceGrid:BuildOwnGuildReports()) do
        RaceGrid:StoreGuildReport(report, true)
        groups[normalizeGuildName(report.guildName)] = report
    end

    -- Native data may enrich a guild already discovered through iRC, but it
    -- can never create or rename a Stats card on its own.
    local native = getServerStore().raceLockedGuildReports
    for _, report in pairs(native) do
        local group = type(report) == "table" and groups[normalizeGuildName(report.guildName)]
        if group and normalizeRaceToken(report.race) == group.race then
            if group.guildDeaths == nil then group.guildDeaths = report.guildDeaths end
        end
    end

    local result = {}
    for _, group in pairs(groups) do
        group.faction = ALLIANCE_RACES[group.race] and "Alliance" or "Horde"
        group.points, group.averagePoints = 0, nil
        result[#result + 1] = group
    end
    table.sort(result, guildRank)
    self:DebugMsg(self:Text("RACEGRID_SUMMARY", #result), 3)
    return result, "irc_guilds"
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
        if iRC:NormalizeName(sender) == iRC:NormalizeName(iRC:GetPlayerName()) then return end
        if channelName == CHANNEL_NAME and type(message) == "string" and message:sub(1, #PREFIX + 1) == PREFIX .. ":" then
            local decoded = hexToBytes(message:sub(#PREFIX + 2))
            if decoded then handleMessage(PREFIX, decoded, sender) end
        elseif RACELOCKED_CHANNEL_LOOKUP[channelName] then
            local report = parseRaceLockedGuildReport(message, channelName)
            if report then
                RaceGrid:StoreRaceLockedGuildReport(report)
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
