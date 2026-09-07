local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local RaceGrid = {}
iRC.RaceGrid = RaceGrid

local PREFIX = "iRCGridV1"
local CHANNEL_NAME = "iRacelockConnection"
local WIRE_VERSION = "2"
local REPORT_INTERVAL = 120
local REFRESH_COOLDOWN = 300
local STALE_AFTER = 900
local REPORT_MAX_AGE = 5 * 86400
local SEP = "\t"
local ALLIANCE_RACES = { HUMAN = true, DWARF = true, NIGHTELF = true, GNOME = true, DRAENEI = true }
local HORDE_RACES = { ORC = true, SCOURGE = true, TAUREN = true, TROLL = true, BLOODELF = true }
local VALID_RACES = {}
for race in pairs(ALLIANCE_RACES) do VALID_RACES[race] = true end
for race in pairs(HORDE_RACES) do VALID_RACES[race] = true end

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
        if type(id) ~= "number" or id <= 0 or #message > 255 then return false end
        if not SendChatMessage then return false end
        local hex = message:gsub(".", function(character) return string.format("%02x", string.byte(character)) end)
        local single = prefix .. ":" .. hex
        if #single <= 255 then
            local called = pcall(SendChatMessage, single, "CHANNEL", nil, id)
            if called and message:match("^GUILD_REPORT") then iRC:DebugMsg(iRC:Text("RACEGRID_PACKAGE_SENDING", 1, 1), 3) end
            return called
        end

        local messageId = string.format("%x", math.floor(GetTime() * 1000) % 0xFFFFFF)
        local chunkSize = 210
        local total = math.ceil(#hex / chunkSize)
        for part = 1, total do
            local chunk = hex:sub((part - 1) * chunkSize + 1, part * chunkSize)
            local wire = table.concat({ prefix, "C", messageId, part, total, chunk }, ":")
            local called = pcall(SendChatMessage, wire, "CHANNEL", nil, id)
            if not called then return false end
            iRC:DebugMsg(iRC:Text("RACEGRID_PACKAGE_SENDING", part, total), 3)
        end
        return true
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
        store = { guildReports = {} }
        iRCDB.globalRaceGrid.servers[serverKey] = store
    end
    store.guildReports = store.guildReports or {}
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

local incomingChunks = {}
local MAX_PENDING_PACKAGES = 32

local function cleanIncomingChunks(now)
    local count, oldestKey, oldestAt = 0, nil, nil
    for key, entry in pairs(incomingChunks) do
        if type(entry) ~= "table" or not entry.startedAt or now - entry.startedAt > 15 then
            incomingChunks[key] = nil
        else
            count = count + 1
            if not oldestAt or entry.startedAt < oldestAt then oldestKey, oldestAt = key, entry.startedAt end
        end
    end
    if count >= MAX_PENDING_PACKAGES and oldestKey then incomingChunks[oldestKey] = nil end
end

local function decodeChannelWire(message, sender)
    local direct = message:match("^" .. PREFIX .. ":([0-9a-fA-F]+)$")
    if direct then
        local decoded = hexToBytes(direct)
        if decoded and decoded:match("^GUILD_REPORT") then iRC:DebugMsg(iRC:Text("RACEGRID_PACKAGE_RECEIVING", 1, 1, sender), 3) end
        return decoded
    end
    local messageId, part, total, chunk = message:match("^" .. PREFIX .. ":C:([0-9a-fA-F]+):(%d+):(%d+):([0-9a-fA-F]+)$")
    part, total = tonumber(part), tonumber(total)
    if not messageId or not part or not total or total < 2 or total > 8 or part < 1 or part > total then return nil end
    cleanIncomingChunks(GetTime())
    local key = fullNameKey(sender) .. ":" .. messageId
    local entry = incomingChunks[key]
    if not entry or entry.total ~= total or GetTime() - entry.startedAt > 15 then
        entry = { total = total, startedAt = GetTime(), parts = {} }
        incomingChunks[key] = entry
    end
    entry.parts[part] = chunk
    iRC:DebugMsg(iRC:Text("RACEGRID_PACKAGE_RECEIVING", part, total, sender), 3)
    for index = 1, total do if not entry.parts[index] then return nil end end
    incomingChunks[key] = nil
    return hexToBytes(table.concat(entry.parts))
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
    return true
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
        guildContacts = guild.guildContacts,
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
    if not silent and iRC.MainUI then iRC.MainUI:RefreshIfShown() end
    return true
end

local externalReady = false

-- Verification and compatible participation remain useful metadata, but the
-- guild statistics themselves count the complete current roster.
function RaceGrid:GetRosterParticipation(member)
    if iRC:NormalizeName(member.name) == iRC:NormalizeName(iRC:GetPlayerName()) then return "verified" end
    local state = member.verification and member.verification.state
    if state == "verified" or state == "compatible" then return state end
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
        guildName = guildName, members = 0, activePlayers = 0, totalLevel = 0,
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
        guildContacts = tostring(rules.guildContacts or ""):sub(1, 60),
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
    for class, count in pairs(group.classes) do group.classAverageLevels[class] = group.classTotals[class] / count end
    group.totalLevel, group.classTotals = nil, nil
    return { group }
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
    fields[#fields + 1] = tostring(report.guildContacts or ""):gsub("[%c]", " "):sub(1, 60)
    fields[#fields + 1] = iRC.Version
    local payload = table.concat(fields, SEP)
    if #payload > 255 then return false end
    self:StoreGuildReport(report)
    -- Public custom-channel sends require a hardware event on Classic. Startup
    -- and ticker refreshes update the local cache only and are not failures.
    if fromClick ~= true then return false end
    if not send(PREFIX, payload, "CHANNEL", CHANNEL_NAME) then
        iRC:DebugMsg(iRC:Text("RACEGRID_REPORT_SEND_FAILED", report.guildName, #payload), 1)
        return false
    end
    iRC:DebugMsg(iRC:Text("RACEGRID_GUILD_REPORT_SENT", report.guildName, report.membersLevel60, report.activePlayers, report.members), 3)
    return true
end

function RaceGrid:RequestReports(fromClick)
    if fromClick ~= true or not self:IsEnabled() then return false end
    self:EnsureChannel()
    if not getChannelId() then return false end
    if not send(PREFIX, table.concat({ "REQUEST", WIRE_VERSION, iRC.Version }, SEP), "CHANNEL", CHANNEL_NAME) then return false end
    iRC:DebugMsg(iRC:Text("RACEGRID_REQUEST_SENT"), 3)
    return true
end

local lastRefreshActivityAt

function RaceGrid:GetRefreshCooldownRemaining()
    if not lastRefreshActivityAt then return 0 end
    return math.max(0, REFRESH_COOLDOWN - (GetTime() - lastRefreshActivityAt))
end

-- Only call synchronously from an actual UI OnClick handler.
function RaceGrid:PublishFromClick()
    if not self:IsEnabled() then return false end
    local remaining = self:GetRefreshCooldownRemaining()
    if remaining > 0 then
        iRC:DebugMsg(iRC:Text("RACEGRID_REFRESH_COOLDOWN_ACTIVE", math.ceil(remaining)), 3)
        return false
    end
    lastRefreshActivityAt = GetTime()
    self:BroadcastReport(true)
    self:RequestReports(true)
    return true
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
    local guildContacts = tostring(parts[25] or "")
    if #guildContacts > 60 or guildContacts:find("[%c]") then return nil end
    local addonVersion = parts[26]
    return {
        name = name, guid = guid, guildName = guildName, race = race,
        membersLevel60 = level60, activePlayers = active, members = members,
        averageLevel = averageLevel, timestamp = timestamp, guildDeaths = deaths,
        classes = classes, rules = rules, rulesKnown = rulesKnown,
        guildContacts = guildContacts,
        addonVersion = addonVersion,
        source = "iRC guild report",
    }
end

local function handleMessage(prefix, message, sender)
    if prefix ~= PREFIX or not RaceGrid:IsEnabled() then return end
    if iRC:NormalizeName(sender) == iRC:NormalizeName(iRC:GetPlayerName()) then return end
    local parts = split(message)
    if parts[1] == "REQUEST" and (parts[2] == WIRE_VERSION or parts[2] == "1") then
        iRC:CheckForNewVersion(parts[3])
        iRC:DebugMsg(iRC:Text("RACEGRID_REQUEST_RECEIVED", sender, math.ceil(RaceGrid:GetRefreshCooldownRemaining())), 3)
        return
    end
    local report = parseGuildReport(parts)
    -- WoW may qualify the channel sender with its realm while the profile in
    -- the payload uses the character's short name. Compare them using iRC's
    -- canonical character-name form without weakening the sender check.
    if not report or iRC:NormalizeName(report.name) ~= iRC:NormalizeName(sender) then return end
    iRC:CheckForNewVersion(report.addonVersion)
    RaceGrid:StoreGuildReport(report)
    iRC:DebugMsg(iRC:Text("RACEGRID_GUILD_REPORT_RECEIVED", report.guildName, report.membersLevel60, report.activePlayers, report.members), 3)
end

function iRC:GetGlobalRaceOverview()
    local serverStore = getServerStore()
    local stored = serverStore.guildReports
    local result = {}
    local now = time()
    for key, report in pairs(stored) do
        local timestamp = type(report) == "table" and tonumber(report.timestamp) or nil
        if not timestamp or timestamp <= 0 or now - timestamp > REPORT_MAX_AGE then
            stored[key] = nil
            serverStore.guildActivity[key] = nil
        elseif normalizeRaceToken(report.race) and (tonumber(report.members) or 0) > 0 then
            report.cached = now - timestamp > STALE_AFTER
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
    local groups = {}
    if RaceGrid:IsEnabled() then
        for _, report in ipairs(self:GetGlobalRaceOverview()) do groups[normalizeGuildName(report.guildName)] = report end
    end
    for _, report in ipairs(RaceGrid:BuildOwnGuildReports()) do
        RaceGrid:StoreGuildReport(report, true)
        groups[normalizeGuildName(report.guildName)] = report
    end

    local result = {}
    for _, group in pairs(groups) do
        group.faction = ALLIANCE_RACES[group.race] and "Alliance" or "Horde"
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
            end)
        else
            externalReady = true
            RaceGrid:Refresh()
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
            local decoded = decodeChannelWire(message, sender)
            if decoded then handleMessage(PREFIX, decoded, sender) end
        end
    end
end)
