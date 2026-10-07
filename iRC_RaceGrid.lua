local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local RaceGrid = {}
iRC.RaceGrid = RaceGrid

local PREFIX = "iRCGridV1"
local CHANNEL_NAME = "iRCCommsV1"
local WIRE_VERSION = "5"
local REPORT_SCHEMA = 5
local REPORT_INTERVAL = 120
local REFRESH_COOLDOWN = 300
local STALE_AFTER = 900
local REPORT_MAX_AGE = 5 * 86400
local RECENT_REPORT_WINDOW = 60
local CACHE_REQUEST_WINDOW = 5
local CACHE_OPEN_REQUEST_COOLDOWN = 30
local CACHE_TRANSFER_TIMEOUT = 15
local CACHE_CHUNK_SIZE = 100
local MAX_CHANNEL_PAYLOAD = 1024
local MAX_CACHE_PARTS = 16
local MAX_CACHE_PACKAGES = 32
local cacheUpdatingUntil = 0
local lastCacheOpenRequestAt
local channelJoinReady = false
local channelJoinStartedAt = 0
local channelJoinGeneration = 0

local function setCacheUpdating(active)
    cacheUpdatingUntil = active and ((GetTime and GetTime() or 0) + CACHE_TRANSFER_TIMEOUT) or 0
end

function RaceGrid:IsCacheUpdating()
    return cacheUpdatingUntil > (GetTime and GetTime() or 0)
end
local SEP = "\t"
local ALLIANCE_RACES = { HUMAN = true, DWARF = true, NIGHTELF = true, GNOME = true, DRAENEI = true }
local HORDE_RACES = { ORC = true, SCOURGE = true, TAUREN = true, TROLL = true, BLOODELF = true }
local NEUTRAL_RACES = { SKYBORNE = true }
local VALID_RACES = {}
for race in pairs(ALLIANCE_RACES) do VALID_RACES[race] = true end
for race in pairs(HORDE_RACES) do VALID_RACES[race] = true end
for race in pairs(NEUTRAL_RACES) do VALID_RACES[race] = true end

local function normalizeRaceToken(race)
    local token = tostring(race or ""):upper():gsub("%s+", "")
    if token == "UNDEAD" then token = "SCOURGE" end
    return VALID_RACES[token] and token or nil
end

local function registerPrefix(prefix)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then return C_ChatInfo.RegisterAddonMessagePrefix(prefix) end
end

local function bytesToHex(value)
    return tostring(value or ""):gsub(".", function(character)
        return string.format("%02x", string.byte(character))
    end)
end

local function send(prefix, message, distribution, target)
    if distribution == "CHANNEL" then
        local id = GetChannelName and GetChannelName(target)
        if type(id) ~= "number" or id <= 0 or #message > MAX_CHANNEL_PAYLOAD then return false end
        if not SendChatMessage then return false end
        local hex = bytesToHex(message)
        local single = prefix .. ":" .. hex
        if #single <= 255 then
            local called = pcall(SendChatMessage, single, "CHANNEL", nil, id)
            if called then iRC:RecordTrafficBytes("out", #single, PREFIX, "CHANNEL") end
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
            iRC:RecordTrafficBytes("out", #wire, PREFIX, "CHANNEL")
            iRC:DebugMsg(iRC:Text("RACEGRID_PACKAGE_SENDING", part, total), 3)
        end
        return true
    end
    if #message > 255 then return false end
    return iRC:SendAddonTraffic(prefix, message, distribution, target)
end

local function split(message)
    local fields = {}
    for value in (tostring(message or "") .. SEP):gmatch("(.-)" .. SEP) do fields[#fields + 1] = value end
    return fields
end

local function fullNameKey(name)
    return iRC:NormalizeName(name)
end

local ownGuildRoster, ownGuildKey, ownGuildSenders = nil, nil, {}
local function isOwnGuildSender(sender)
    if not iRC.GetGuildRosterSnapshot or not iRC.GetGuildKey then return false end
    local guildKey = iRC:GetGuildKey()
    if not guildKey then return false end
    local roster = iRC:GetGuildRosterSnapshot()
    if roster ~= ownGuildRoster or guildKey ~= ownGuildKey then
        ownGuildRoster, ownGuildKey, ownGuildSenders = roster, guildKey, {}
        for _, member in ipairs(roster) do
            if member.name then ownGuildSenders[iRC:NormalizeName(member.name)] = true end
        end
    end
    return ownGuildSenders[iRC:NormalizeName(sender)] == true
end

local function validNumber(value, minimum, maximum, preserveFraction)
    value = tonumber(value)
    if not value or value ~= value or value < minimum or value > maximum then return nil end
    return preserveFraction and value or math.floor(value)
end

local function normalizeGuildName(name)
    return string.lower((tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")))
end

local function isOlympusMuteAddonLoaded()
    if not C_AddOns or not C_AddOns.IsAddOnLoaded then return false end
    -- OlympusMute is the published addon name. Keep the development aliases
    -- accepted as well; the lookup is repeated so either addon may load later.
    return C_AddOns.IsAddOnLoaded("OlympusMute") == true
        or C_AddOns.IsAddOnLoaded("olumpysmuteaddon") == true
        or C_AddOns.IsAddOnLoaded("OlympusMuteAddon") == true
end

local function isMutedOlympusGuild(guildName)
    return isOlympusMuteAddonLoaded() and normalizeGuildName(guildName):find("olympus", 1, true) ~= nil
end

local function payloadChecksum(value)
    local first, second = 1, 0
    for index = 1, #value do
        first = (first + value:byte(index)) % 65521
        second = (second + first) % 65521
    end
    return string.format("%04x%04x", second, first)
end

local function getServerStore()
    local realm
    if iRC:IsForeverClient() then
        realm = "Forever"
    else
        realm = GetNormalizedRealmName and GetNormalizedRealmName() or (GetRealmName and GetRealmName()) or "Unknown"
    end
    local serverKey = string.lower(tostring(realm):gsub("%s+", ""))
    iRCDB = iRCDB or {}
    iRCDB.globalRaceGrid = iRCDB.globalRaceGrid or {}
    iRCDB.globalRaceGrid.servers = iRCDB.globalRaceGrid.servers or {}
    local store = iRCDB.globalRaceGrid.servers[serverKey]
    if not store then
        store = { guildReports = {} }
        iRCDB.globalRaceGrid.servers[serverKey] = store
    end
    -- Cached reports are user data gathered from other guilds. A schema bump
    -- must never erase the complete cache; older records are validated and
    -- filled with safe defaults by the normal read/render path instead.
    store.reportSchema = REPORT_SCHEMA
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
    local retained, bucketIndex = {}, {}
    local cutoff = now - 86400
    for _, sample in ipairs(samples) do
        local timestamp = type(sample) == "table" and tonumber(sample.timestamp) or 0
        if timestamp >= cutoff then
            local bucket = math.floor(timestamp / 3600) * 3600
            local existing = bucketIndex[bucket]
            if existing then
                existing.players = math.max(tonumber(existing.players) or 0, tonumber(sample.players) or 0)
                existing.timestamp = math.max(tonumber(existing.timestamp) or 0, timestamp)
            else
                existing = { timestamp = timestamp, players = math.max(0, math.floor(tonumber(sample.players) or 0)) }
                retained[#retained + 1] = existing
                bucketIndex[bucket] = existing
            end
        end
    end
    samples = retained
    activity[key] = samples
    local current = math.max(0, math.floor(tonumber(onlinePlayers) or 0))
    local currentBucket = math.floor(now / 3600) * 3600
    local latest = bucketIndex[currentBucket]
    if latest then
        latest.players = math.max(tonumber(latest.players) or 0, current)
        latest.timestamp = now
    else
        latest = { timestamp = now, players = current }
        samples[#samples + 1] = latest
    end
    local peak = 0
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

-- Session-only roster used by the test-admin diagnostics page. The server's
-- channel roster is authoritative for who is online; version replies merely
-- enrich those rows and never add an offline character to the displayed list.
local adminPresence = { users = {}, versions = {}, requestedAt = 0, requestId = nil }
local adminProbeBySender = {}

local function rememberAdminVersion(name, version, guildName)
    local key = fullNameKey(name)
    if key == "" then return end
    version = tostring(version or ""):gsub("[%c%s]", "")
    if version == "" or #version > 32 then return end
    adminPresence.versions[key] = {
        version = version,
        guildName = tostring(guildName or ""):gsub("[%c]", " "):sub(1, 80),
        seenAt = time(),
    }
    if adminPresence.requestedAt > 0 and time() - adminPresence.requestedAt <= 10 then
        adminPresence.users[key] = name
    end
end

local function getAdminRosterAPI()
    if C_ChatInfo and C_ChatInfo.GetChannelRosterInfo then return C_ChatInfo.GetChannelRosterInfo end
    return GetChannelRosterInfo
end

local function findAdminChannelDisplayIndex()
    if adminPresence.displayIndex then return adminPresence.displayIndex end
    if not GetChannelDisplayInfo then return nil end
    for index = 1, 50 do
        local ok, displayName = pcall(GetChannelDisplayInfo, index)
        if ok and type(displayName) == "string" and displayName:lower() == CHANNEL_NAME:lower() then
            adminPresence.displayIndex = index
            return index
        end
    end
end

local function refreshAdminChannelRoster(displayIndex, rosterCount)
    if not iRC:IsTestAdmin() then return false end
    local getRosterInfo = getAdminRosterAPI()
    if not getRosterInfo then return false end
    displayIndex = tonumber(displayIndex) or findAdminChannelDisplayIndex()
    if not displayIndex then return false end
    local displayName
    if GetChannelDisplayInfo then
        local ok, value = pcall(GetChannelDisplayInfo, displayIndex)
        if ok then displayName = value end
        if type(displayName) == "string" and displayName ~= ""
            and displayName:lower() ~= CHANNEL_NAME:lower() then return false end
    end
    adminPresence.displayIndex = displayIndex
    local count = math.max(0, math.floor(tonumber(rosterCount) or 0))
    if count == 0 then count = 500 end
    for index = 1, count do
        local rosterOK, name = pcall(getRosterInfo, displayIndex, index)
        if rosterOK and type(name) == "string" and name ~= "" then
            adminPresence.users[fullNameKey(name)] = name
        elseif rosterCount == nil then
            break
        end
    end
    local ownName = iRC:GetPlayerName()
    if ownName and ownName ~= "" then adminPresence.users[fullNameKey(ownName)] = ownName end
    return true
end

local function captureAdminChannelList(message, sender)
    if not iRC:IsTestAdmin() or adminPresence.requestedAt <= 0
        or time() - adminPresence.requestedAt > 10 then return end
    local captured = false
    message = tostring(message or "")
    local function addName(name, allowSpaces)
        name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
            :gsub("^%*+", ""):gsub("^%s+", ""):gsub("%s+$", "")
            :gsub("^%[", ""):gsub("%]$", ""):gsub("[%.;]$", "")
        name = name:gsub("%s+", " ")
        local lowerName = name:lower()
        if name == "" or #name > 80 or name:find("[%c%[%],:|]")
            or (not allowSpaces and name:find("%s"))
            or lowerName == CHANNEL_NAME:lower() or lowerName == "channel"
            or lowerName == "players" or lowerName == "list" or lowerName == "owner"
            or lowerName == "moderator" then return false end
        adminPresence.users[fullNameKey(name)] = name
        return true
    end
    for name in message:gmatch("|Hplayer:([^:|]+)") do
        if addName(name, true) then captured = true end
    end
    if not captured then
        -- Forever may deliver /chatlist as CHAT_MSG_SYSTEM rather than
        -- CHAT_MSG_CHANNEL_LIST. Accept either one-name lines or the comma-
        -- separated tail of the channel header while the scan window is open.
        local plain = message:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            :gsub("|H.-|h", ""):gsub("|h", "")
        local listedChannel, listedUsers = plain:match("^%[%d+%.%s*([^%]]+)%]%s*(.*)$")
        if listedChannel and listedChannel:lower() == CHANNEL_NAME:lower() then
            for candidate in tostring(listedUsers or ""):gmatch("[^,]+") do
                if addName(candidate, true) then captured = true end
            end
        elseif #plain <= 80 and addName(plain) then
            captured = true
        elseif plain:lower():find(CHANNEL_NAME:lower(), 1, true) then
            local tail = plain:match(":%s*(.+)$")
            for candidate in tostring(tail or ""):gmatch("[^,]+") do
                if addName(candidate, true) then captured = true end
            end
        end
    end
    if not captured and type(sender) == "string" and sender ~= ""
        and sender:lower() ~= CHANNEL_NAME:lower() and not sender:find("[%s:%[%]]") then
        adminPresence.users[fullNameKey(sender)] = sender
    end
end

function RaceGrid:RequestAdminOnlineUsers()
    if not iRC:IsTestAdmin() then return false end
    self:EnsureChannel()
    local channelId = getChannelId()
    if not channelId then return false end
    adminPresence.requestedAt = time()
    adminPresence.requestId = string.format("%x%x", time() % 0xFFFFFF, math.floor(GetTime() * 1000) % 0xFFFF)
    adminPresence.users = {}
    adminPresence.displayIndex = nil
    if ListChannelByName then
        pcall(ListChannelByName, CHANNEL_NAME)
    elseif SlashCmdList and SlashCmdList.CHATLIST then
        pcall(SlashCmdList.CHATLIST, CHANNEL_NAME)
    end
    refreshAdminChannelRoster()
    send(PREFIX, table.concat({ "ADMIN_PRESENCE_REQUEST", WIRE_VERSION, adminPresence.requestId,
        tostring(iRC:GetPlayerName() or "") }, SEP), "CHANNEL", CHANNEL_NAME)
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, refreshAdminChannelRoster)
        C_Timer.After(1.5, refreshAdminChannelRoster)
    end
    return true
end

function RaceGrid:GetAdminOnlineUsers()
    if not iRC:IsTestAdmin() then return {}, { total = 0, known = 0, versions = {} } end
    refreshAdminChannelRoster()
    local rows, versionCounts, known = {}, {}, 0
    for key, name in pairs(adminPresence.users) do
        local observed = adminPresence.versions[key]
        local version = observed and observed.version or nil
        if key == fullNameKey(iRC:GetPlayerName()) then
            version = tostring(iRC.Version or "Unknown")
            observed = observed or { guildName = GetGuildInfo and GetGuildInfo("player") or "" }
        end
        if version and version ~= "" then
            known = known + 1
            versionCounts[version] = (versionCounts[version] or 0) + 1
        end
        rows[#rows + 1] = { name = name, version = version, guildName = observed and observed.guildName or "" }
    end
    table.sort(rows, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
    return rows, {
        total = #rows,
        known = known,
        versions = versionCounts,
        requestedAt = adminPresence.requestedAt,
    }
end

local function hideChannelFromChatWindows(channelName)
    if not ChatFrame_RemoveChannel or not NUM_CHAT_WINDOWS then return end
    for index = 1, NUM_CHAT_WINDOWS do
        local chatFrame = _G["ChatFrame" .. index]
        if chatFrame then ChatFrame_RemoveChannel(chatFrame, channelName) end
    end
end

local function hasRestoredServerChannel()
    if not GetChannelList then return false end
    local channels = { GetChannelList() }
    for index = 1, #channels, 3 do
        local channelId = tonumber(channels[index])
        local channelName = tostring(channels[index + 1] or "")
        if channelId and channelId > 0 and channelName ~= ""
            and channelName:lower() ~= CHANNEL_NAME:lower() then return true end
    end
    return false
end

function RaceGrid:IsEnabled()
    return true
end

function RaceGrid:EnsureChannel()
    if not self:IsEnabled() then return end
    -- Joining before Blizzard restores General/Trade makes the hidden addon
    -- channel claim channel 1 and shifts the player's normal global channels.
    if not channelJoinReady then return end
    if getChannelId() then
        hideChannelFromChatWindows(CHANNEL_NAME)
        return
    end
    if JoinChannelByName then
        iRC:DebugMsg(iRC:Text("RACEGRID_OWN_CHANNEL_JOIN"), 3)
        JoinChannelByName(CHANNEL_NAME)
    end
end

function RaceGrid:ScheduleChannelJoin(delay)
    if channelJoinReady or not C_Timer or not C_Timer.After then return end
    if channelJoinStartedAt <= 0 then channelJoinStartedAt = GetTime and GetTime() or 0 end
    channelJoinGeneration = channelJoinGeneration + 1
    local generation = channelJoinGeneration
    C_Timer.After(math.max(0, tonumber(delay) or 3), function()
        if generation ~= channelJoinGeneration or channelJoinReady then return end
        local now = GetTime and GetTime() or channelJoinStartedAt
        if hasRestoredServerChannel() or now - channelJoinStartedAt >= 30 then
            channelJoinReady = true
            RaceGrid:EnsureChannel()
            -- The channel ID is assigned asynchronously. Hide it and resume the
            -- initial local-report build once the join has completed.
            C_Timer.After(1, function()
                RaceGrid:EnsureChannel()
                RaceGrid:BroadcastReport()
            end)
        else
            RaceGrid:ScheduleChannelJoin(3)
        end
    end)
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
        membersLevel60 = guild.membersLevel60, activeLevel30 = guild.activeLevel30,
        activeMembers = guild.activeMembers, averageLevel = guild.averageLevel,
        classes = guild.classes, classBreakdownClasses = guild.classBreakdownClasses,
        guildDeaths = guild.guildDeaths,
        rules = guild.rules, rulesKnown = guild.rulesKnown,
        guildContacts = guild.guildContacts,
        guildContactsOnlineMask = guild.guildContactsOnlineMask,
        guildDescription = guild.guildDescription, guildDescriptionTimestamp = guild.guildDescriptionTimestamp,
        guildDescriptionEditedBy = guild.guildDescriptionEditedBy,
        guildHomepageIcon = guild.guildHomepageIcon,
        guildHomepageTag = guild.guildHomepageTag,
        classBreakdownMode = guild.classBreakdownMode,
        classBreakdownMinLevel = guild.classBreakdownMinLevel,
        classBreakdownMaxLevel = guild.classBreakdownMaxLevel,
        source = "iRC guild report", timestamp = time(), lastSeen = time(),
    }
end

function RaceGrid:StoreGuildReport(report, silent)
    if type(report) ~= "table" or type(report.guildName) ~= "string" or report.guildName == "" then return false end
    if isMutedOlympusGuild(report.guildName) then return false end
    if iRC:IsLowTrafficMode() then return false end
    if iRC:ContainsProfanity(report.guildDescription) then return false end
    report.race = normalizeRaceToken(report.race)
    if not report.race then return false end
    if report.classBreakdownMode ~= "RANGE" and report.classBreakdownMode ~= "MAX" then
        report.classBreakdownMode = "ALL"
    end
    if report.guildHomepageTag ~= "PVE" and report.guildHomepageTag ~= "PVP"
        and report.guildHomepageTag ~= "RP" then
        report.guildHomepageTag = "NORMAL"
    end
    report.classBreakdownMinLevel = math.max(1,
        math.min(60, math.floor(tonumber(report.classBreakdownMinLevel) or 1)))
    report.classBreakdownMaxLevel = math.max(report.classBreakdownMinLevel,
        math.min(60, math.floor(tonumber(report.classBreakdownMaxLevel) or 60)))
    if report.classBreakdownMode == "ALL" then
        report.classBreakdownMinLevel, report.classBreakdownMaxLevel = 1, 60
    elseif report.classBreakdownMode == "MAX" then
        report.classBreakdownMinLevel, report.classBreakdownMaxLevel = 60, 60
    end
    local reports = getServerStore().guildReports
    local key = normalizeGuildName(report.guildName)
    local old = reports[key]
    local oldTimestamp, newTimestamp = old and (tonumber(old.timestamp) or 0) or 0, tonumber(report.timestamp) or 0
    if old and (oldTimestamp > newTimestamp
        or (oldTimestamp == newTimestamp and (tonumber(old.cacheHop) or 0) < (tonumber(report.cacheHop) or 0))) then return false end
    if old and (tonumber(old.guildDescriptionTimestamp) or 0) > (tonumber(report.guildDescriptionTimestamp) or 0) then
        report.guildDescription = old.guildDescription
        report.guildDescriptionTimestamp = old.guildDescriptionTimestamp
        report.guildDescriptionEditedBy = old.guildDescriptionEditedBy
    end
    if iRC:ContainsProfanity(report.guildDescription) then return false end
    report.activePlayers = recordGuildActivity(report.guildName, report.activePlayers)
    if report.faction ~= "Alliance" and report.faction ~= "Horde" then
        report.faction = ALLIANCE_RACES[report.race] and "Alliance" or "Horde"
    end
    report.lastSeen = time()
    reports[key] = report
    if not silent and iRC.MainUI then
        local function refreshGuildStats() iRC.MainUI:RefreshIfShown() end
        if not iRC:DeferLowTraffic("ui:guild-statistics", refreshGuildStats) then refreshGuildStats() end
    end
    return true
end

local externalReady = false
local localReportDirty = true

function RaceGrid:MarkLocalReportDirty()
    localReportDirty = true
end

-- Verification participation remains useful metadata, but guild statistics
-- themselves count the complete current roster.
function RaceGrid:GetRosterParticipation(member)
    if iRC:NormalizeName(member.name) == iRC:NormalizeName(iRC:GetPlayerName()) then return "verified" end
    local state = member.verification and member.verification.state
    if iRC:IsLiveAddonState(state) then return state end
end

function RaceGrid:BuildOwnGuildReports()
    local connection = iRC:GetConnection()
    if not connection or not iRC:IsGuildConnectionActive() then return {} end
    local profile = iRC:GetLocalProfile()
    -- Ordinary members do not know the Guild Master's selected guild race
    -- during bootstrap. The report still needs a valid legacy race token;
    -- faction is carried separately and remains authoritative.
    local guildRace = normalizeRaceToken(iRC:GetGuildRace()) or normalizeRaceToken(profile.race)
    local guildName = tostring(connection.guildName or (GetGuildInfo and GetGuildInfo("player")) or "")
    if not guildRace or guildName == "" then return {} end
    local rules = iRC:GetConnectionRules() or {}
    local classBreakdown = iRC:GetGuildHomepageClassBreakdown()
    local classBreakdownMode = classBreakdown.mode == "RANGE" and "RANGE"
        or classBreakdown.mode == "MAX" and "MAX" or "ALL"
    local classBreakdownMinLevel = classBreakdownMode == "MAX" and 60
        or classBreakdownMode == "RANGE" and math.max(1, math.min(60, math.floor(tonumber(classBreakdown.minLevel) or 1))) or 1
    local classBreakdownMaxLevel = classBreakdownMode == "MAX" and 60
        or classBreakdownMode == "RANGE" and math.max(classBreakdownMinLevel,
            math.min(60, math.floor(tonumber(classBreakdown.maxLevel) or 60))) or 60
    local group = {
        name = profile.name, guid = profile.guid, addonVersion = iRC.Version,
        race = guildRace, faction = UnitFactionGroup and UnitFactionGroup("player")
            or (ALLIANCE_RACES[guildRace] and "Alliance" or "Horde"),
        guildName = guildName, members = 0, activePlayers = 0, activeMembers = 0, totalLevel = 0,
        classes = {}, classBreakdownClasses = {}, classTotals = {}, classAverageLevels = {}, membersLevel60 = 0, activeLevel30 = 0,
        verifiedMembers = 0, populationSource = "irc_guild_roster",
        guildDeaths = (connection.raceDeaths or {})[guildRace] or 0, timestamp = time(), source = "iRC",
        rulesKnown = connection.rulesBootstrap ~= true,
        rules = {
            requireIRC = rules.requireIRC == true,
            raceLock = rules.raceLock == true,
            nativeTongueOnly = rules.nativeTongueOnly and true or false,
            selfFoundOnly = rules.selfFoundOnly and true or false,
            guildFoundOnly = rules.guildFoundOnly and true or false,
            level60GuildFound = rules.level60GuildFound and true or false,
            allowLevel60WithoutSelfFound = rules.allowLevel60WithoutSelfFound and true or false,
            sameRaceGroupsOnly = rules.sameRaceGroupsOnly and true or false,
            allowLevel60MixedRaceGroups = rules.allowLevel60MixedRaceGroups and true or false,
            guildGroupsOnly = rules.guildGroupsOnly and true or false,
            sameRaceMinimumLevel = tonumber(rules.sameRaceMinimumLevel) or 1,
            guildGroupsMinimumLevel = tonumber(rules.guildGroupsMinimumLevel) or 1,
        },
        guildContacts = tostring(rules.guildContacts or ""):sub(1, 140),
        guildDescription = tostring(connection.guildHomepageDescription.text or ""):sub(1, iRC.GuildHomepageDescriptionMaxLength),
        guildDescriptionTimestamp = math.floor(tonumber(connection.guildHomepageDescription.timestamp) or 0),
        guildDescriptionEditedBy = tostring(connection.guildHomepageDescription.editedBy or ""):sub(1, 80),
        guildHomepageIcon = math.max(0, math.min(#iRC.GuildHomepageIcons,
            math.floor(tonumber(connection.guildHomepageIcon.icon) or 0))),
        guildHomepageTag = iRC:GetGuildHomepageTag(),
        classBreakdownMode = classBreakdownMode,
        classBreakdownMinLevel = classBreakdownMinLevel,
        classBreakdownMaxLevel = classBreakdownMaxLevel,
    }
    local counted, contactIndexes = {}, {}
    local contactIndex = 0
    for name in group.guildContacts:gmatch("[^,]+") do
        contactIndex = contactIndex + 1
        if contactIndex <= 5 then
            contactIndexes[iRC:NormalizeName(name:gsub("^%s+", ""):gsub("%s+$", ""))] = contactIndex
        end
    end
    group.guildContactsOnlineMask = 0
    for _, member in ipairs(iRC:GetGuildRosterRows()) do
        local participation = self:GetRosterParticipation(member)
        local key = iRC:NormalizeName(member.name)
        if key ~= "" and not counted[key] then
            counted[key] = true
            local level, class = member.level or 1, member.class or "UNKNOWN"
            local recentlyOnline = member.online == true
                or member.lastOnlineDays ~= nil and member.lastOnlineDays <= 30
            local recentlyOnlineFiveDays = member.online == true
                or member.lastOnlineDays ~= nil and member.lastOnlineDays <= 5
            group.members, group.totalLevel = group.members + 1, group.totalLevel + level
            if member.online then group.activePlayers = group.activePlayers + 1 end
            local inviteIndex = contactIndexes[key]
            if member.online and inviteIndex then
                group.guildContactsOnlineMask = group.guildContactsOnlineMask + 2 ^ (inviteIndex - 1)
            end
            if recentlyOnline then group.activeMembers = group.activeMembers + 1 end
            if participation == "verified" then group.verifiedMembers = group.verifiedMembers + 1 end
            group.classes[class] = (group.classes[class] or 0) + 1
            group.classTotals[class] = (group.classTotals[class] or 0) + level
            if level >= classBreakdownMinLevel and level <= classBreakdownMaxLevel then
                group.classBreakdownClasses[class] = (group.classBreakdownClasses[class] or 0) + 1
            end
            if level >= 60 then
                group.membersLevel60 = group.membersLevel60 + 1
            end
            if level >= 30 and recentlyOnlineFiveDays then group.activeLevel30 = group.activeLevel30 + 1 end
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

local function serializeGuildReport(report, includeDescription)
    local fields = {
        "GUILD_REPORT", WIRE_VERSION, tostring(report.name or ""), tostring(report.guid or ""),
        tostring(report.guildName or ""), tostring(report.race or ""),
        tostring(report.membersLevel60 or 0), tostring(report.activePlayers or 0), tostring(report.members or 0),
        tostring(report.averageLevel or 0), tostring(report.timestamp or time()), tostring(report.guildDeaths or 0),
    }
    for _, class in ipairs({ "DRUID", "ROGUE", "HUNTER", "WARRIOR", "MAGE", "PRIEST", "WARLOCK", "PALADIN", "SHAMAN" }) do
        fields[#fields + 1] = tostring((report.classes or {})[class] or 0)
    end
    local rules, ruleMask = report.rules or {}, report.rulesKnown == false and 256 or 0
    for _, entry in ipairs({
        { "nativeTongueOnly", 1 }, { "selfFoundOnly", 2 }, { "level60GuildFound", 4 },
        { "allowLevel60WithoutSelfFound", 8 }, { "sameRaceGroupsOnly", 16 },
        { "allowLevel60MixedRaceGroups", 32 }, { "guildGroupsOnly", 64 },
        { "guildFoundTradeExceptions", 128 },
    }) do
        local raceOnly = entry[1] == "nativeTongueOnly" or entry[1] == "sameRaceGroupsOnly"
            or entry[1] == "allowLevel60MixedRaceGroups"
        if report.rulesKnown ~= false and rules[entry[1]]
            and (not raceOnly or rules.raceLock == true) then ruleMask = ruleMask + entry[2] end
    end
    fields[#fields + 1] = tostring(ruleMask)
    fields[#fields + 1] = tostring(math.max(1, math.min(60, tonumber(rules.sameRaceMinimumLevel) or 1)))
    fields[#fields + 1] = tostring(math.max(1, math.min(60, tonumber(rules.guildGroupsMinimumLevel) or 1)))
    fields[#fields + 1] = tostring(report.guildContacts or ""):gsub("[%c]", " "):sub(1, 140)
    fields[#fields + 1] = tostring(report.addonVersion or iRC.Version or "")
    fields[#fields + 1] = report.activeLevel30 ~= nil and tostring(report.activeLevel30) or ""
    fields[#fields + 1] = report.activeMembers ~= nil and tostring(report.activeMembers) or ""
    fields[#fields + 1] = rules.guildMapEnabled and "1" or "0"
    fields[#fields + 1] = rules.raceLock == true and "1" or "0"
    fields[#fields + 1] = tostring(math.max(0, math.min(31, math.floor(tonumber(report.guildContactsOnlineMask) or 0))))
    fields[#fields + 1] = rules.guildFoundOnly and "1" or "0"
    fields[#fields + 1] = tostring(math.max(0, math.min(#iRC.GuildHomepageIcons, math.floor(tonumber(report.guildHomepageIcon) or 0))))
    fields[#fields + 1] = report.faction == "Alliance" and "Alliance" or "Horde"
    if includeDescription then
        fields[#fields + 1] = tostring(report.guildDescription or ""):gsub("[%c]", " "):sub(1, iRC.GuildHomepageDescriptionMaxLength)
        fields[#fields + 1] = tostring(math.floor(tonumber(report.guildDescriptionTimestamp) or 0))
        fields[#fields + 1] = tostring(report.guildDescriptionEditedBy or ""):gsub("[%c]", ""):sub(1, 80)
        fields[#fields + 1] = report.classBreakdownMode == "RANGE" and "RANGE"
            or report.classBreakdownMode == "MAX" and "MAX" or "ALL"
        fields[#fields + 1] = tostring(math.max(1, math.min(60,
            math.floor(tonumber(report.classBreakdownMinLevel) or 1))))
        fields[#fields + 1] = tostring(math.max(1, math.min(60,
            math.floor(tonumber(report.classBreakdownMaxLevel) or 60))))
        for _, class in ipairs({ "DRUID", "ROGUE", "HUNTER", "WARRIOR", "MAGE", "PRIEST", "WARLOCK", "PALADIN", "SHAMAN" }) do
            fields[#fields + 1] = tostring((report.classBreakdownClasses or report.classes or {})[class] or 0)
        end
        fields[#fields + 1] = report.guildHomepageTag == "PVE" and "PVE"
            or report.guildHomepageTag == "PVP" and "PVP" or report.guildHomepageTag == "RP" and "RP" or "NORMAL"
    end
    return table.concat(fields, SEP)
end

function RaceGrid:BroadcastReport(fromClick)
    if iRC:DeferLowTraffic("traffic:guild-statistics", function() RaceGrid:BroadcastReport(false) end) then return false end
    if not self:IsEnabled() then return false end
    if fromClick ~= true and not localReportDirty then return false end
    self:EnsureChannel()
    if not getChannelId() then
        iRC:DebugMsg(iRC:Text("RACEGRID_OWN_CHANNEL_UNAVAILABLE"), 2)
        return false
    end
    local report = self:GetLocalReport()
    if not report.name or report.name == "" or not report.guid or report.guid == "" or not report.race then return false end
    if isMutedOlympusGuild(report.guildName) then return false end
    local payload = serializeGuildReport(report)
    if #payload > MAX_CHANNEL_PAYLOAD then return false end
    if self:StoreGuildReport(report) then localReportDirty = false end
    -- Public custom-channel sends require a hardware event on Classic. Startup
    -- and ticker refreshes update the local cache only and are not failures.
    if fromClick ~= true then return false end
    if not send(PREFIX, payload, "CHANNEL", CHANNEL_NAME) then
        iRC:DebugMsg(iRC:Text("RACEGRID_REPORT_SEND_FAILED", report.guildName, #payload), 1)
        return false
    end
    local description = tostring(report.guildDescription or ""):gsub("[%c]", " "):sub(1, iRC.GuildHomepageDescriptionMaxLength)
    local descriptionTimestamp = math.floor(tonumber(report.guildDescriptionTimestamp) or 0)
    local descriptionEditor = tostring(report.guildDescriptionEditedBy or ""):gsub("[%c]", ""):sub(1, 40)
    if descriptionTimestamp > 0 and descriptionEditor ~= "" then
        send(PREFIX, table.concat({ "GUILD_DESC", WIRE_VERSION, tostring(descriptionTimestamp), descriptionEditor, description }, SEP), "CHANNEL", CHANNEL_NAME)
    end
    local classBreakdownFields = { "GUILD_CLASS_BREAKDOWN", WIRE_VERSION, tostring(report.timestamp or 0),
        report.classBreakdownMode == "RANGE" and "RANGE" or report.classBreakdownMode == "MAX" and "MAX" or "ALL",
        tostring(report.classBreakdownMinLevel or 1), tostring(report.classBreakdownMaxLevel or 60) }
    for _, class in ipairs({ "DRUID", "ROGUE", "HUNTER", "WARRIOR", "MAGE", "PRIEST", "WARLOCK", "PALADIN", "SHAMAN" }) do
        classBreakdownFields[#classBreakdownFields + 1] = tostring((report.classBreakdownClasses or report.classes or {})[class] or 0)
    end
    classBreakdownFields[#classBreakdownFields + 1] = report.guildHomepageTag == "PVE" and "PVE"
        or report.guildHomepageTag == "PVP" and "PVP" or report.guildHomepageTag == "RP" and "RP" or "NORMAL"
    send(PREFIX, table.concat(classBreakdownFields, SEP), "CHANNEL", CHANNEL_NAME)
    iRC:DebugMsg(iRC:Text("RACEGRID_GUILD_REPORT_SENT", report.guildName, report.activeLevel30,
        report.activeMembers, report.activePlayers, report.members), 3)
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
    return true
end

function RaceGrid:Refresh()
    if iRC:DeferLowTraffic("traffic:guild-statistics-refresh", function() RaceGrid:Refresh() end) then return end
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
        -- Mask 256 means the guild report was assembled during first-start
        -- bootstrap and intentionally does not claim authoritative rules.
        local mask = validNumber(parts[22], 0, 256)
        local sameRaceLevel = validNumber(parts[23], 1, 60)
        local guildGroupsLevel = validNumber(parts[24], 1, 60)
        if not mask or not sameRaceLevel or not guildGroupsLevel then return nil end
        if mask ~= 256 then
            local function enabled(flag) return math.floor(mask / flag) % 2 == 1 end
            rulesKnown = true
            rules = {
                nativeTongueOnly = enabled(1), selfFoundOnly = enabled(2),
                level60GuildFound = enabled(4), allowLevel60WithoutSelfFound = enabled(8),
                sameRaceGroupsOnly = enabled(16), allowLevel60MixedRaceGroups = enabled(32),
                guildGroupsOnly = enabled(64), sameRaceMinimumLevel = sameRaceLevel,
                guildFoundTradeExceptions = enabled(128),
                guildMapEnabled = parts[29] == "1",
                raceLock = parts[30] == "1",
                guildGroupsMinimumLevel = guildGroupsLevel,
            }
        end
    end
    local guildContacts = tostring(parts[25] or "")
    if #guildContacts > 140 or guildContacts:find("[%c]") then return nil end
    local addonVersion = parts[26]
    local activeLevel30, activeMembers
    if parts[27] ~= nil and parts[27] ~= "" or parts[28] ~= nil and parts[28] ~= "" then
        activeLevel30 = validNumber(parts[27], 0, members)
        activeMembers = validNumber(parts[28], 0, members)
        if not activeLevel30 or not activeMembers or activeLevel30 > activeMembers then return nil end
    end
    local rawOnlineMask = parts[31]
    local guildContactsOnlineMask = validNumber(rawOnlineMask or "0", 0, 31)
    local pureGuildFoundPresent = guildContactsOnlineMask ~= nil and (parts[32] == "0" or parts[32] == "1")
    if rules then rules.guildFoundOnly = pureGuildFoundPresent and parts[32] == "1" or false end
    local iconField = pureGuildFoundPresent and validNumber(parts[33] or "", 0, #iRC.GuildHomepageIcons) or nil
    local guildHomepageIcon = iconField and math.floor(iconField) or 0
    local faction = tostring(parts[34] or "")
    if faction ~= "Alliance" and faction ~= "Horde" then return nil end
    local descriptionStart = 35
    guildContactsOnlineMask = guildContactsOnlineMask or 0
    local guildDescription = tostring(parts[descriptionStart] or "")
    local guildDescriptionTimestamp = tonumber(parts[descriptionStart + 1]) or 0
    local guildDescriptionEditedBy = tostring(parts[descriptionStart + 2] or "")
    if #guildDescription > iRC.GuildHomepageDescriptionMaxLength or guildDescription:find("[%c]")
        or iRC:ContainsProfanity(guildDescription)
        or #guildDescriptionEditedBy > 80 or guildDescriptionEditedBy:find("[%c]") then return nil end
    local classBreakdownMode = tostring(parts[descriptionStart + 3] or "ALL")
    if classBreakdownMode ~= "RANGE" and classBreakdownMode ~= "MAX" then classBreakdownMode = "ALL" end
    local classBreakdownMinLevel = validNumber(parts[descriptionStart + 4] or "1", 1, 60) or 1
    local classBreakdownMaxLevel = validNumber(parts[descriptionStart + 5] or "60", classBreakdownMinLevel, 60) or 60
    if classBreakdownMode == "ALL" then classBreakdownMinLevel, classBreakdownMaxLevel = 1, 60
    elseif classBreakdownMode == "MAX" then classBreakdownMinLevel, classBreakdownMaxLevel = 60, 60 end
    local classBreakdownClasses, classBreakdownTotal = {}, 0
    for index, class in ipairs({ "DRUID", "ROGUE", "HUNTER", "WARRIOR", "MAGE", "PRIEST", "WARLOCK", "PALADIN", "SHAMAN" }) do
        local count = validNumber(parts[descriptionStart + 5 + index] or tostring(classes[class] or 0), 0, members)
        if not count then return nil end
        classBreakdownClasses[class], classBreakdownTotal = count, classBreakdownTotal + count
    end
    if classBreakdownTotal > members then return nil end
    local guildHomepageTag = tostring(parts[descriptionStart + 15] or "NORMAL")
    if guildHomepageTag ~= "PVE" and guildHomepageTag ~= "PVP" and guildHomepageTag ~= "RP" then
        guildHomepageTag = "NORMAL"
    end
    return {
        name = name, guid = guid, guildName = guildName, race = race,
        membersLevel60 = level60, activePlayers = active, members = members,
        activeLevel30 = activeLevel30, activeMembers = activeMembers,
        averageLevel = averageLevel, timestamp = timestamp, guildDeaths = deaths,
        classes = classes, classBreakdownClasses = classBreakdownClasses,
        rules = rules, rulesKnown = rulesKnown,
        guildContacts = guildContacts,
        guildContactsOnlineMask = guildContactsOnlineMask,
        guildDescription = guildDescription, guildDescriptionTimestamp = guildDescriptionTimestamp,
        guildDescriptionEditedBy = guildDescriptionEditedBy,
        guildHomepageIcon = guildHomepageIcon,
        guildHomepageTag = guildHomepageTag,
        classBreakdownMode = classBreakdownMode,
        classBreakdownMinLevel = classBreakdownMinLevel,
        classBreakdownMaxLevel = classBreakdownMaxLevel,
        faction = faction,
        addonVersion = addonVersion,
        source = "iRC guild report",
    }
end

local cacheRequests, observedCacheOffers, offeredCachePayloads, incomingCacheTransfers = {}, {}, {}, {}
local cacheRequestBySender = {}
local CACHE_REQUEST_SENDER_COOLDOWN = 10

local reportWorkQueue, reportWorkHead, reportWorkTail, reportWorkByKey = {}, 1, 0, {}
local reportWorkScheduled, reportWorkDirty = false, false
local REPORT_WORK_SPACING = 0.2
local MAX_REPORT_WORK = 64
local handleMessage
local cacheChunkWorkQueue, cacheChunkWorkHead, cacheChunkWorkTail = {}, 1, 0
local cacheChunkWorkScheduled = false
local MAX_CACHE_CHUNK_WORK = MAX_CACHE_PACKAGES * MAX_CACHE_PARTS

local function cacheChunkQueueSize()
    return math.max(0, cacheChunkWorkTail - cacheChunkWorkHead + 1)
end

local function processNextCacheChunks()
    for _ = 1, 2 do
        local work = cacheChunkWorkQueue[cacheChunkWorkHead]
        if not work then break end
        cacheChunkWorkQueue[cacheChunkWorkHead] = nil
        cacheChunkWorkHead = cacheChunkWorkHead + 1
        local ok, err = pcall(handleMessage, work.prefix, work.message, work.sender, work.distribution, true)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end
    cacheChunkWorkScheduled = false
    if cacheChunkWorkHead <= cacheChunkWorkTail then
        cacheChunkWorkScheduled = true
        C_Timer.After(0.03, processNextCacheChunks)
    else
        cacheChunkWorkQueue, cacheChunkWorkHead, cacheChunkWorkTail = {}, 1, 0
    end
end

local function queueCacheChunk(prefix, message, sender, distribution)
    if cacheChunkQueueSize() >= MAX_CACHE_CHUNK_WORK then return end
    cacheChunkWorkTail = cacheChunkWorkTail + 1
    cacheChunkWorkQueue[cacheChunkWorkTail] = {
        prefix = prefix, message = message, sender = sender, distribution = distribution,
    }
    if not cacheChunkWorkScheduled then
        cacheChunkWorkScheduled = true
        C_Timer.After(0.03, processNextCacheChunks)
    end
end

local function processNextReportWork()
    local work = reportWorkQueue[reportWorkHead]
    reportWorkQueue[reportWorkHead] = nil
    reportWorkHead = reportWorkHead + 1
    if work then
        reportWorkByKey[work.key] = nil
        local ok, err = pcall(work.run)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end
    reportWorkScheduled = false
    if reportWorkHead <= reportWorkTail and C_Timer and C_Timer.After then
        reportWorkScheduled = true
        C_Timer.After(REPORT_WORK_SPACING, processNextReportWork)
    else
        reportWorkQueue, reportWorkHead, reportWorkTail = {}, 1, 0
        if reportWorkDirty then
            reportWorkDirty = false
            if iRC.MainUI then iRC.MainUI:RefreshIfShown() end
        end
    end
end

local function queueReportWork(key, callback, timestamp)
    if not C_Timer or not C_Timer.After then
        callback()
        return
    end
    local existing = reportWorkByKey[key]
    if existing then
        if not timestamp or not existing.timestamp or timestamp >= existing.timestamp then
            existing.run, existing.timestamp = callback, timestamp
        end
        return
    end
    if reportWorkTail - reportWorkHead + 1 >= MAX_REPORT_WORK then
        local dropped = reportWorkQueue[reportWorkHead]
        reportWorkQueue[reportWorkHead] = nil
        reportWorkHead = reportWorkHead + 1
        if dropped then reportWorkByKey[dropped.key] = nil end
    end
    local work = { key = key, run = callback, timestamp = timestamp }
    reportWorkTail = reportWorkTail + 1
    reportWorkQueue[reportWorkTail] = work
    reportWorkByKey[key] = work
    if not reportWorkScheduled then
        reportWorkScheduled = true
        C_Timer.After(REPORT_WORK_SPACING, processNextReportWork)
    end
end

local function storeIncomingReport(report)
    local lowCpu = iRC:IsPerformanceMode() and C_Timer and C_Timer.After
    local stored = RaceGrid:StoreGuildReport(report, lowCpu)
    if stored and lowCpu then reportWorkDirty = true end
    return stored
end

function RaceGrid:ClearCachedReportsForTesting()
    if not iRC:IsTestAdmin() then return nil end
    local servers = iRCDB and iRCDB.globalRaceGrid and iRCDB.globalRaceGrid.servers
    local removed = 0
    if type(servers) == "table" then
        for _, serverStore in pairs(servers) do
            if type(serverStore) == "table" then
                if type(serverStore.guildReports) == "table" then
                    for _ in pairs(serverStore.guildReports) do removed = removed + 1 end
                end
                serverStore.guildReports = {}
                serverStore.guildActivity = {}
            end
        end
    end
    wipe(reportWorkQueue)
    reportWorkHead, reportWorkTail = 1, 0
    wipe(reportWorkByKey)
    reportWorkDirty = false
    wipe(cacheChunkWorkQueue)
    cacheChunkWorkHead, cacheChunkWorkTail = 1, 0
    wipe(incomingChunks)
    wipe(incomingCacheTransfers)
    wipe(cacheRequests)
    wipe(cacheRequestBySender)
    setCacheUpdating(false)
    if iRC.MainUI then iRC.MainUI:RefreshIfShown() end
    return removed
end

local function cleanCacheState()
    local now = GetTime()
    for sender, request in pairs(cacheRequestBySender) do
        if type(request) ~= "table" or now - (request.receivedAt or 0) > CACHE_TRANSFER_TIMEOUT then
            cacheRequestBySender[sender] = nil
        end
    end
    for requestId, request in pairs(cacheRequests) do
        if type(request) ~= "table" or now - (request.startedAt or 0) > CACHE_TRANSFER_TIMEOUT then cacheRequests[requestId] = nil end
    end
    for requestId, observed in pairs(observedCacheOffers) do
        if type(observed) ~= "table" or now - (observed.startedAt or 0) > CACHE_TRANSFER_TIMEOUT then observedCacheOffers[requestId] = nil end
    end
    for requestId, offered in pairs(offeredCachePayloads) do
        if type(offered) ~= "table" or now - (offered.startedAt or 0) > CACHE_TRANSFER_TIMEOUT then offeredCachePayloads[requestId] = nil end
    end
    local count, oldestKey, oldestAt = 0, nil, nil
    for key, transfer in pairs(incomingCacheTransfers) do
        if type(transfer) ~= "table" or now - (transfer.startedAt or 0) > CACHE_TRANSFER_TIMEOUT then
            incomingCacheTransfers[key] = nil
        else
            count = count + 1
            if not oldestAt or transfer.startedAt < oldestAt then oldestKey, oldestAt = key, transfer.startedAt end
        end
    end
    if count >= MAX_CACHE_PACKAGES and oldestKey then incomingCacheTransfers[oldestKey] = nil end
end

local function sendCacheOffers(requestId, requester)
    if iRC:DeferLowTraffic("traffic:cache-offers", function() sendCacheOffers(requestId, requester) end) then return end
    local store, now = getServerStore(), time()
    observedCacheOffers[requestId] = observedCacheOffers[requestId] or { startedAt = GetTime(), guilds = {} }
    for _, report in pairs(store.guildReports) do
        local timestamp = type(report) == "table" and tonumber(report.timestamp) or 0
        local hasSenderIdentity = type(report) == "table" and type(report.name) == "string" and report.name ~= ""
            and type(report.guid) == "string" and report.guid ~= ""
        if hasSenderIdentity and not isMutedOlympusGuild(report.guildName)
            and timestamp > 0 and now - timestamp <= REPORT_MAX_AGE then
            local snapshot, guildName = report, report.guildName
            local guildKey = normalizeGuildName(guildName)
            local function offer()
                if not iRC:IsGuildConnectionActive() or not iRC:IsGuildMemberName(requester) then return end
                local observed = observedCacheOffers[requestId]
                if not observed or GetTime() - (observed.startedAt or 0) > CACHE_TRANSFER_TIMEOUT then return end
                local payload = serializeGuildReport(snapshot, true)
                local checksum = payloadChecksum(payload)
                local cacheHop = math.max(0, math.min(1, math.floor(tonumber(snapshot.cacheHop) or 0)))
                local reportTimestamp = tonumber(snapshot.timestamp) or 0
                local best = observed.guilds[guildKey]
                if best and (best.timestamp > reportTimestamp
                    or (best.timestamp == reportTimestamp and (best.cacheHop or 1) < cacheHop)
                    or (best.timestamp == reportTimestamp and (best.cacheHop or 1) == cacheHop
                        and fullNameKey(best.sender) < fullNameKey(iRC:GetPlayerName()))) then return end
                if send(PREFIX, table.concat({ "CACHE_OFFER", WIRE_VERSION, requestId, requester, guildName, reportTimestamp, checksum, cacheHop }, SEP), "GUILD") then
                    local offered = offeredCachePayloads[requestId]
                        or { startedAt = GetTime(), requester = requester, guilds = {} }
                    offeredCachePayloads[requestId] = offered
                    offered.requester = requester
                    offered.guilds[guildKey] = {
                        payload = payload, timestamp = reportTimestamp, checksum = checksum, cacheHop = cacheHop,
                    }
                    iRC:DebugMsg(iRC:Text("RACEGRID_CACHE_OFFER_SENT", guildName, requester), 3)
                end
            end
            queueReportWork("cache-offer:" .. requestId .. ":" .. guildKey, offer, timestamp)
        end
    end
end

local function requestBestCacheOffers(requestId)
    if iRC:DeferLowTraffic("traffic:cache-selection", function() requestBestCacheOffers(requestId) end) then return end
    local request = cacheRequests[requestId]
    if not request then return end
    local requested = 0
    for guildKey, offer in pairs(request.offers) do
        local localReport = getServerStore().guildReports[guildKey]
        local localTimestamp = localReport and (tonumber(localReport.timestamp) or 0) or 0
        local recentlyReceived = localReport and (tonumber(localReport.lastSeen) or 0) > time() - RECENT_REPORT_WINDOW
        local localCacheHop = localReport and math.max(0, math.min(1, math.floor(tonumber(localReport.cacheHop) or 0))) or 1
        local shouldRequest = offer.timestamp > localTimestamp
            or (not recentlyReceived and offer.timestamp == localTimestamp and (offer.cacheHop or 1) < localCacheHop)
        if shouldRequest then
            request.selected[guildKey] = offer
            requested = requested + 1
            send(PREFIX, table.concat({ "CACHE_GET", WIRE_VERSION, requestId, offer.guildName, offer.timestamp, offer.checksum }, SEP), "WHISPER", offer.sender)
            iRC:DebugMsg(iRC:Text("RACEGRID_CACHE_REQUEST_SENT", offer.guildName, offer.sender), 3)
        end
    end
    if requested == 0 then
        cacheRequests[requestId] = nil
        setCacheUpdating(false)
    end
end

function RaceGrid:RequestGuildCache()
    if iRC:DeferLowTraffic("traffic:guild-cache-request", function() RaceGrid:RequestGuildCache() end) then return false end
    if not self:IsEnabled() or not iRC:IsGuildConnectionActive() then return false end
    cleanCacheState()
    local requestId = string.format("%x%x", time() % 0xFFFFFF, math.floor(GetTime() * 1000) % 0xFFFF)
    cacheRequests[requestId] = { startedAt = GetTime(), offers = {}, selected = {} }
    if not send(PREFIX, table.concat({ "CACHE_REQUEST", WIRE_VERSION, requestId }, SEP), "GUILD") then
        cacheRequests[requestId] = nil
        return false
    end
    setCacheUpdating(true)
    iRC:DebugMsg(iRC:Text("RACEGRID_CACHE_DISCOVERY_SENT"), 3)
    if C_Timer and C_Timer.After then C_Timer.After(CACHE_REQUEST_WINDOW, function() requestBestCacheOffers(requestId) end) end
    return true
end

function RaceGrid:RequestGuildCacheFromOpen()
    local now = GetTime and GetTime() or 0
    if lastCacheOpenRequestAt and now - lastCacheOpenRequestAt < CACHE_OPEN_REQUEST_COOLDOWN then return false end
    if not self:RequestGuildCache() then return false end
    lastCacheOpenRequestAt = now
    return true
end

local function handleCacheMessage(parts, sender, distribution)
    local kind, requestId = parts[1], parts[3]
    if parts[2] ~= WIRE_VERSION or type(requestId) ~= "string" or not requestId:match("^[0-9a-f]+$")
        or #requestId > 24 or not iRC:IsGuildConnectionActive() or not iRC:IsGuildMemberName(sender) then return true end
    cleanCacheState()
    if kind == "CACHE_REQUEST" and distribution == "GUILD" then
        local senderKey, now = fullNameKey(sender), GetTime()
        local previous = cacheRequestBySender[senderKey]
        if previous and (previous.requestId == requestId
            or now - previous.receivedAt < CACHE_REQUEST_SENDER_COOLDOWN) then return true end
        cacheRequestBySender[senderKey] = { requestId = requestId, receivedAt = now }
        sendCacheOffers(requestId, sender)
        iRC:DebugMsg(iRC:Text("RACEGRID_CACHE_DISCOVERY_RECEIVED", sender), 3)
        return true
    elseif kind == "CACHE_OFFER" and distribution == "GUILD" then
        if not cacheRequests[requestId] and not observedCacheOffers[requestId] then return true end
        local requester, guildName = parts[4], tostring(parts[5] or "")
        local timestamp, checksum = validNumber(parts[6], 0, time() + 300), tostring(parts[7] or ""):lower()
        local cacheHop = validNumber(parts[8] or "0", 0, 1)
        if guildName == "" or #guildName > 80 or isMutedOlympusGuild(guildName) or not timestamp or not cacheHop
            or #checksum ~= 8 or not checksum:match("^[0-9a-f]+$") then return true end
        local guildKey = normalizeGuildName(guildName)
        local observed = observedCacheOffers[requestId] or { startedAt = GetTime(), guilds = {} }
        observedCacheOffers[requestId] = observed
        local current = observed.guilds[guildKey]
        if not current or timestamp > current.timestamp
            or (timestamp == current.timestamp and cacheHop < (current.cacheHop or 1))
            or (timestamp == current.timestamp and cacheHop == (current.cacheHop or 1)
                and fullNameKey(sender) < fullNameKey(current.sender)) then
            observed.guilds[guildKey] = { timestamp = timestamp, cacheHop = cacheHop, sender = sender }
        end
        if iRC:NormalizeName(requester) == iRC:NormalizeName(iRC:GetPlayerName()) then
            local request = cacheRequests[requestId]
            if request then
                local offer = request.offers[guildKey]
                if not offer or timestamp > offer.timestamp
                    or (timestamp == offer.timestamp and cacheHop < (offer.cacheHop or 1))
                    or (timestamp == offer.timestamp and cacheHop == (offer.cacheHop or 1)
                        and fullNameKey(sender) < fullNameKey(offer.sender)) then
                    request.offers[guildKey] = {
                        guildName = guildName, timestamp = timestamp, checksum = checksum,
                        cacheHop = cacheHop, sender = sender,
                    }
                end
            end
        end
        return true
    elseif kind == "CACHE_GET" and distribution == "WHISPER" then
        if iRC:DeferLowTraffic("traffic:cache-data", function()
            handleCacheMessage(parts, sender, distribution)
        end) then return true end
        local guildName, timestamp, checksum = tostring(parts[4] or ""), tonumber(parts[5]), tostring(parts[6] or ""):lower()
        if isMutedOlympusGuild(guildName) then return true end
        local offered = offeredCachePayloads[requestId]
        if not offered or iRC:NormalizeName(offered.requester) ~= iRC:NormalizeName(sender) then return true end
        local snapshot = offered and offered.guilds[normalizeGuildName(guildName)]
        if not snapshot or snapshot.timestamp ~= timestamp or snapshot.checksum ~= checksum then return true end
        local payload = snapshot.payload
        local hex = bytesToHex(payload)
        local total = math.ceil(#hex / CACHE_CHUNK_SIZE)
        if total < 1 or total > MAX_CACHE_PARTS then return true end
        for part = 1, total do
            local chunk = hex:sub((part - 1) * CACHE_CHUNK_SIZE + 1, part * CACHE_CHUNK_SIZE)
            send(PREFIX, table.concat({ "CACHE_DATA", WIRE_VERSION, requestId, guildName, part, total, checksum, chunk }, SEP), "WHISPER", sender)
            iRC:DebugMsg(iRC:Text("RACEGRID_CACHE_PACKAGE_SENT", part, total, guildName, sender), 3)
        end
        return true
    elseif kind == "CACHE_DATA" and distribution == "WHISPER" then
        local guildName = tostring(parts[4] or "")
        if isMutedOlympusGuild(guildName) then return true end
        local part, total = tonumber(parts[5]), tonumber(parts[6])
        if iRC:DeferLowTraffic("traffic:racegrid-cache:" .. iRC:NormalizeName(sender) .. ":"
            .. requestId .. ":" .. tostring(part or ""), function()
                handleCacheMessage(parts, sender, distribution)
            end) then return true end
        local checksum, chunk = tostring(parts[7] or ""):lower(), tostring(parts[8] or "")
        local request = cacheRequests[requestId]
        local selected = request and request.selected[normalizeGuildName(guildName)]
        if not request or not selected or iRC:NormalizeName(selected.sender) ~= iRC:NormalizeName(sender)
            or normalizeGuildName(selected.guildName) ~= normalizeGuildName(guildName)
            or selected.checksum ~= checksum
            or not part or not total or total < 1 or total > MAX_CACHE_PARTS or part < 1 or part > total
            or #checksum ~= 8 or not checksum:match("^[0-9a-f]+$") or not chunk:match("^[0-9a-fA-F]+$") then return true end
        setCacheUpdating(true)
        local key = fullNameKey(sender) .. ":" .. requestId .. ":" .. checksum
        local transfer = incomingCacheTransfers[key]
        if not transfer or transfer.total ~= total then
            transfer = { startedAt = GetTime(), total = total, parts = {}, guildName = guildName, checksum = checksum }
            incomingCacheTransfers[key] = transfer
        end
        transfer.parts[part] = chunk
        iRC:DebugMsg(iRC:Text("RACEGRID_CACHE_PACKAGE_RECEIVED", part, total, guildName, sender), 3)
        for index = 1, total do if not transfer.parts[index] then return true end end
        incomingCacheTransfers[key] = nil
        local payload = hexToBytes(table.concat(transfer.parts))
        if not payload or payloadChecksum(payload) ~= checksum then return true end
        queueReportWork("cache:" .. normalizeGuildName(guildName), function()
            local report = parseGuildReport(split(payload))
            if not report or normalizeGuildName(report.guildName) ~= normalizeGuildName(guildName)
                or tonumber(report.timestamp) ~= selected.timestamp
                or time() - (tonumber(report.timestamp) or 0) > REPORT_MAX_AGE then return end
            report.cacheHop, report.relayedBy = 1, sender
            if storeIncomingReport(report) then
                iRC:CheckForNewVersion(report.addonVersion)
                iRC:DebugMsg(iRC:Text("RACEGRID_CACHE_REPORT_RECEIVED", report.guildName, sender), 3)
            end
        end)
        request.selected[normalizeGuildName(guildName)] = nil
        local pending
        for _ in pairs(request.selected) do pending = true; break end
        if not pending then
            cacheRequests[requestId] = nil
            setCacheUpdating(false)
        end
        return true
    end
    return false
end

handleMessage = function(prefix, message, sender, distribution, queued)
    if prefix ~= PREFIX or not RaceGrid:IsEnabled() then return end
    if iRC:NormalizeName(sender) == iRC:NormalizeName(iRC:GetPlayerName()) then return end
    if distribution == "CHANNEL" and isOwnGuildSender(sender) and message:match("^GUILD_") then return end
    if not queued and distribution == "WHISPER" and message:match("^CACHE_DATA\t")
        and C_Timer and C_Timer.After then
        queueCacheChunk(prefix, message, sender, distribution)
        return
    end
    local publicParts
    if distribution == "CHANNEL" and message:match("^GUILD_REPORT\t") then
        publicParts = split(message)
        if isMutedOlympusGuild(publicParts[5]) then return end
        local guildKey = normalizeGuildName(publicParts[5])
        if guildKey ~= "" then
            local existing = getServerStore().guildReports[guildKey]
            if existing and (tonumber(existing.lastSeen) or 0) > time() - RECENT_REPORT_WINDOW then return end
            if not queued and C_Timer and C_Timer.After then
                queueReportWork("public:" .. guildKey, function()
                    handleMessage(prefix, message, sender, distribution, true)
                end, tonumber(publicParts[11]) or 0)
                return
            end
        end
    end
    if not queued and distribution == "CHANNEL" and message:match("^GUILD_DESC\t")
        and C_Timer and C_Timer.After then
        queueReportWork("public-description:" .. fullNameKey(sender), function()
            handleMessage(prefix, message, sender, distribution, true)
        end, tonumber((split(message))[3]) or 0)
        return
    end
    if (message:match("^GUILD_REPORT") or message:match("^GUILD_DESC")
        or message:match("^GUILD_CLASS_BREAKDOWN"))
        and iRC:DeferLowTraffic("traffic:racegrid-report:" .. iRC:NormalizeName(sender), function()
            handleMessage(prefix, message, sender, distribution)
        end) then return end
    local parts = publicParts or split(message)
    if parts[1] == "ADMIN_PRESENCE_REQUEST" and distribution == "CHANNEL" then
        local requestId, requester = tostring(parts[3] or ""), tostring(parts[4] or "")
        if parts[2] == WIRE_VERSION and requestId:match("^[0-9a-f]+$") and #requestId <= 24
            and iRC:NormalizeName(requester) == iRC:NormalizeName(sender) then
            local senderKey, now = fullNameKey(sender), GetTime and GetTime() or 0
            if not adminProbeBySender[senderKey] or now - adminProbeBySender[senderKey] >= 30 then
                adminProbeBySender[senderKey] = now
                local guildName = GetGuildInfo and GetGuildInfo("player") or ""
                send(PREFIX, table.concat({ "ADMIN_PRESENCE_RESPONSE", WIRE_VERSION, requestId,
                    tostring(iRC.Version or "Unknown"), tostring(guildName or ""):gsub("[%c]", " "):sub(1, 80) }, SEP),
                    "WHISPER", sender)
            end
        end
        return
    elseif parts[1] == "ADMIN_PRESENCE_RESPONSE" and distribution == "WHISPER" then
        if iRC:IsTestAdmin() and parts[2] == WIRE_VERSION
            and tostring(parts[3] or "") == tostring(adminPresence.requestId or "") then
            rememberAdminVersion(sender, parts[4], parts[5])
        end
        return
    end
    if parts[1] and parts[1]:match("^CACHE_") and handleCacheMessage(parts, sender, distribution) then return end
    if parts[1] == "GUILD_DESC" and parts[2] == WIRE_VERSION then
        local timestamp, editedBy, value = tonumber(parts[3]), tostring(parts[4] or ""), tostring(parts[5] or "")
        if timestamp and timestamp > 0 and timestamp <= time() + 300 and #editedBy <= 40 and not editedBy:find("[%c]")
            and #value <= iRC.GuildHomepageDescriptionMaxLength and not value:find("[%c]")
            and not iRC:ContainsProfanity(value) then
            for _, report in pairs(getServerStore().guildReports) do
                if iRC:NormalizeName(report.name) == iRC:NormalizeName(sender)
                    and timestamp > math.floor(tonumber(report.guildDescriptionTimestamp) or 0) then
                    report.guildDescription, report.guildDescriptionTimestamp, report.guildDescriptionEditedBy = value, timestamp, editedBy
                    if iRC.MainUI then iRC.MainUI:RefreshIfShown() end
                    break
                end
            end
        end
        return
    elseif parts[1] == "GUILD_CLASS_BREAKDOWN" and parts[2] == WIRE_VERSION then
        local reportTimestamp = tonumber(parts[3])
        local mode = tostring(parts[4] or "")
        local minLevel, maxLevel = tonumber(parts[5]), tonumber(parts[6])
        local filteredClasses, filteredTotal = {}, 0
        local validClasses = true
        for index, class in ipairs({ "DRUID", "ROGUE", "HUNTER", "WARRIOR", "MAGE", "PRIEST", "WARLOCK", "PALADIN", "SHAMAN" }) do
            local count = tonumber(parts[6 + index])
            if not count or count ~= math.floor(count) or count < 0 then validClasses = false break end
            filteredClasses[class], filteredTotal = count, filteredTotal + count
        end
        if reportTimestamp and (mode == "ALL" or mode == "RANGE" or mode == "MAX")
            and minLevel and minLevel == math.floor(minLevel) and minLevel >= 1 and minLevel <= 60
            and maxLevel and maxLevel == math.floor(maxLevel) and maxLevel >= minLevel and maxLevel <= 60
            and validClasses then
            for _, report in pairs(getServerStore().guildReports) do
                if iRC:NormalizeName(report.name) == iRC:NormalizeName(sender)
                    and tonumber(report.timestamp) == reportTimestamp and filteredTotal <= (tonumber(report.members) or 0) then
                    report.classBreakdownMode = mode
                    report.classBreakdownMinLevel = mode == "MAX" and 60 or mode == "ALL" and 1 or minLevel
                    report.classBreakdownMaxLevel = mode == "MAX" and 60 or mode == "ALL" and 60 or maxLevel
                    report.classBreakdownClasses = filteredClasses
                    local guildHomepageTag = tostring(parts[16] or "NORMAL")
                    report.guildHomepageTag = guildHomepageTag == "PVE" and "PVE"
                        or guildHomepageTag == "PVP" and "PVP" or guildHomepageTag == "RP" and "RP" or "NORMAL"
                    if iRC.MainUI then iRC.MainUI:RefreshIfShown() end
                    break
                end
            end
        end
        return
    end
    local report = parseGuildReport(parts)
    -- WoW may qualify the channel sender with its realm while the profile in
    -- the payload uses the character's short name. Compare them using iRC's
    -- canonical character-name form without weakening the sender check.
    if not report or isMutedOlympusGuild(report.guildName)
        or iRC:NormalizeName(report.name) ~= iRC:NormalizeName(sender) then return end
    rememberAdminVersion(sender, report.addonVersion, report.guildName)
    if distribution == "CHANNEL" then
        local ownGuildName = GetGuildInfo and GetGuildInfo("player")
        if ownGuildName and normalizeGuildName(report.guildName) == normalizeGuildName(ownGuildName) then return end
    end
    iRC:CheckForNewVersion(report.addonVersion)
    storeIncomingReport(report)
    iRC:DebugMsg(iRC:Text("RACEGRID_GUILD_REPORT_RECEIVED", report.guildName, report.activeLevel30 or 0,
        report.activeMembers or 0, report.activePlayers, report.members), 3)
end

function iRC:GetGlobalRaceOverview()
    local serverStore = getServerStore()
    local stored = serverStore.guildReports
    local result = {}
    local now = time()
    for key, report in pairs(stored) do
        local timestamp = type(report) == "table" and tonumber(report.timestamp) or nil
        if not timestamp or timestamp <= 0 or now - timestamp > REPORT_MAX_AGE or isMutedOlympusGuild(report.guildName)
            or (not iRC:IsLowTrafficMode() and iRC:ContainsProfanity(report.guildDescription)) then
            stored[key] = nil
            serverStore.guildActivity[key] = nil
        elseif normalizeRaceToken(report.race) and (tonumber(report.members) or 0) > 0 then
            report.cached = (tonumber(report.cacheHop) or 0) > 0 or now - timestamp > STALE_AFTER
            result[#result + 1] = report
        end
    end
    return result
end

local function guildRank(a, b)
    if (a.activeLevel30 or -1) ~= (b.activeLevel30 or -1) then return (a.activeLevel30 or -1) > (b.activeLevel30 or -1) end
    if (a.activeMembers or -1) ~= (b.activeMembers or -1) then return (a.activeMembers or -1) > (b.activeMembers or -1) end
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
        if not isMutedOlympusGuild(report.guildName) then
            RaceGrid:StoreGuildReport(report, true)
            groups[normalizeGuildName(report.guildName)] = report
        end
    end

    local result = {}
    for _, group in pairs(groups) do
        if group.faction ~= "Alliance" and group.faction ~= "Horde" then
            group.faction = ALLIANCE_RACES[group.race] and "Alliance" or "Horde"
        end
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
frame:RegisterEvent("CHAT_MSG_SYSTEM")
if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid("CHANNEL_ROSTER_UPDATE") then
    frame:RegisterEvent("CHANNEL_ROSTER_UPDATE")
end
if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid("CHAT_MSG_CHANNEL_LIST") then
    frame:RegisterEvent("CHAT_MSG_CHANNEL_LIST")
end
if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid("CHANNEL_UI_UPDATE") then
    frame:RegisterEvent("CHANNEL_UI_UPDATE")
end
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= iRC.Name then return end
        registerPrefix(PREFIX)
    elseif event == "PLAYER_LOGIN" then
        channelJoinStartedAt = GetTime and GetTime() or 0
        if getChannelId() and LeaveChannelByName then
            -- WoW may remember and autojoin a custom channel before addons run.
            -- Release that premature slot so General/Trade can reclaim their
            -- normal numbers, then rejoin through the delayed path below.
            LeaveChannelByName(CHANNEL_NAME)
        end
        RaceGrid:ScheduleChannelJoin(10)
        -- Let WoW finish restoring the player's normal chat channels before
        -- adding any hidden data channels.
        if C_Timer and C_Timer.After then
            C_Timer.After(iRC:GetStartupTrafficDelay(), function()
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
    elseif event == "CHANNEL_UI_UPDATE" then
        if getChannelId() then
            if not channelJoinReady and LeaveChannelByName then
                LeaveChannelByName(CHANNEL_NAME)
            else
                hideChannelFromChatWindows(CHANNEL_NAME)
            end
        elseif not channelJoinReady and channelJoinStartedAt > 0 and hasRestoredServerChannel() then
            -- Wait for the rest of Blizzard's auto-joined channels to settle.
            RaceGrid:ScheduleChannelJoin(3)
        end
    elseif event == "CHANNEL_ROSTER_UPDATE" then
        local displayIndex, rosterCount = ...
        if adminPresence.requestedAt > 0 and time() - adminPresence.requestedAt <= 10 then
            refreshAdminChannelRoster(displayIndex, rosterCount)
        end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, distribution, sender = ...
        handleMessage(prefix, message, sender, distribution)
    elseif event == "CHAT_MSG_CHANNEL_LIST" or event == "CHAT_MSG_SYSTEM" then
        captureAdminChannelList(...)
    elseif event == "CHAT_MSG_CHANNEL" then
        local message, sender = ...
        local channelName = select(9, ...)
        if iRC:NormalizeName(sender) == iRC:NormalizeName(iRC:GetPlayerName()) then return end
        if channelName == CHANNEL_NAME and type(message) == "string" and message:sub(1, #PREFIX + 1) == PREFIX .. ":" then
            local decoded = decodeChannelWire(message, sender)
            -- Same-guild reports are already assembled locally. Admin
            -- presence probes still need to reach every channel member.
            if decoded and (not isOwnGuildSender(sender) or not decoded:match("^GUILD_")) then
                handleMessage(PREFIX, decoded, sender, "CHANNEL")
            end
        end
    end
end)
