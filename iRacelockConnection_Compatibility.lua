local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local Compatibility = {}
iRC.Compatibility = Compatibility

-- RaceLocked and RaceLockedForkEU use compatible v1-v3 guild-stat payloads.
-- Keep their source identity instead of treating either addon as iRC data.
local FORKEU_SOURCE = "RaceLockedForkEU"
local RACELOCKED_SOURCE = "RaceLocked"
local STATS_PREFIXES = {
    RaceLockedForkEU = FORKEU_SOURCE,
    RaceLocked = RACELOCKED_SOURCE,
}
local SELF_FOUND_PREFIX = "RLAddon"
local GUILD_FOUND_PREFIX = "RLGFRoster"
local SEPARATOR = string.char(31)
local REQUEST_PAYLOAD = "REQUEST"
local pendingRaceLockedTradeRequests = {}

local function registerPrefix(prefix)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then return C_ChatInfo.RegisterAddonMessagePrefix(prefix) end
    if RegisterAddonMessagePrefix then return RegisterAddonMessagePrefix(prefix) end
end

local function send(prefix, message, distribution)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then return C_ChatInfo.SendAddonMessage(prefix, message, distribution) end
    if SendAddonMessage then return SendAddonMessage(prefix, message, distribution) end
end

local function positiveNumber(value, fallback)
    value = tonumber(value) or fallback or 0
    return value < 0 and 0 or value
end

local function split(message)
    local fields = {}
    for value in string.gmatch(tostring(message or ""), "([^" .. SEPARATOR .. "]+)") do fields[#fields + 1] = value end
    return fields
end

local function parseStats(message, source)
    local fields = split(message)
    local version, name, guid, points, level, enemies, dungeons, jumps = fields[1]
    if version == "1" and #fields == 5 then
        name, guid, points, level = fields[2], fields[3], fields[4], fields[5]
    elseif version == "2" and #fields == 7 then
        name, guid, points, level, dungeons, jumps = fields[2], fields[3], fields[4], fields[5], fields[6], fields[7]
    elseif version == "3" and #fields == 8 then
        name, guid, points, level, enemies, dungeons, jumps = fields[2], fields[3], fields[4], fields[5], fields[6], fields[7], fields[8]
    else
        return nil
    end
    if not name or name == "" or not guid or guid == "" then return nil end
    return {
        source = source or FORKEU_SOURCE,
        name = name,
        guid = guid,
        points = positiveNumber(points),
        level = math.max(1, positiveNumber(level, 1)),
        statistics = {
            enemiesSlain = positiveNumber(enemies),
            dungeonBosses = positiveNumber(dungeons),
            jumps = positiveNumber(jumps),
        },
    }
end

local function readExternalMetric(functionName, fallback)
    local functionReference = _G[functionName]
    if type(functionReference) ~= "function" then return fallback end
    local ok, value = pcall(functionReference)
    return ok and positiveNumber(value, fallback) or fallback
end

function Compatibility:GetLocalStats(source)
    local profile = iRC:GetLocalProfile()
    local statistics = profile.statistics or {}
    local apiPrefix = source == RACELOCKED_SOURCE and "RaceLocked_" or "RaceLockedForkEU_"
    return {
        source = source or FORKEU_SOURCE,
        name = profile.name,
        guid = profile.guid,
        level = profile.level,
        points = readExternalMetric(apiPrefix .. "GetPlayerAchievementPoints", profile.points),
        statistics = {
            enemiesSlain = readExternalMetric(apiPrefix .. "GetPlayerEnemiesSlain", statistics.enemiesSlain),
            dungeonBosses = readExternalMetric(apiPrefix .. "GetPlayerDungeonCompletions", statistics.dungeonBosses),
            jumps = readExternalMetric(apiPrefix .. "GetPlayerJumpCount", statistics.jumps),
        },
    }
end

function Compatibility:StoreStats(entry)
    if not entry or not entry.name or not iRC:IsInGuildConnection() then return end
    local connection = iRC:GetConnection()
    connection.compatibilityMembers = connection.compatibilityMembers or {}
    local key = iRC:NormalizeName(entry.name)
    local member = connection.compatibilityMembers[key] or { name = entry.name }
    member.name = entry.name
    member.guid = entry.guid or member.guid
    member.stats = entry
    member.stats.lastSeen = time()
    connection.compatibilityMembers[key] = member
    if iRC.ConnectionDashboard then iRC.ConnectionDashboard:RefreshIfShown() end
end

function Compatibility:StoreSelfFound(name, selfFound, source)
    if not name or not iRC:IsInGuildConnection() then return end
    local connection = iRC:GetConnection()
    connection.compatibilityMembers = connection.compatibilityMembers or {}
    local key = iRC:NormalizeName(name)
    local member = connection.compatibilityMembers[key] or { name = name }
    member.name = member.name or name
    member.selfFound = selfFound and true or false
    member.selfFoundLastSeen = time()
    member.presence = {
        source = source or FORKEU_SOURCE,
        lastSeen = member.selfFoundLastSeen,
    }
    connection.compatibilityMembers[key] = member
    if iRC.ConnectionDashboard then iRC.ConnectionDashboard:RefreshIfShown() end
end

function Compatibility:StoreGuildFoundVerification(name, verified, clean, source)
    if not name or not iRC:IsInGuildConnection() then return end
    local connection = iRC:GetConnection()
    connection.compatibilityMembers = connection.compatibilityMembers or {}
    local key = iRC:NormalizeName(name)
    local member = connection.compatibilityMembers[key] or { name = name }
    member.name = member.name or name
    member.guildFound = {
        verified = verified and true or false,
        clean = clean and true or false,
        source = source or RACELOCKED_SOURCE,
        lastSeen = time(),
    }
    connection.compatibilityMembers[key] = member
    if iRC.ConnectionDashboard then iRC.ConnectionDashboard:RefreshIfShown() end
end

function iRC:GetCompatibilityMember(name)
    local connection = self:GetConnection()
    return connection and connection.compatibilityMembers and connection.compatibilityMembers[self:NormalizeName(name)] or nil
end

function iRC:GetCompatibilityStats(name)
    local member = self:GetCompatibilityMember(name)
    return member and member.stats or nil
end

function Compatibility:BroadcastStats()
    if not iRC:IsInGuildConnection() then return end
    for prefix, source in pairs(STATS_PREFIXES) do
        local entry = self:GetLocalStats(source)
        if entry.name and entry.name ~= "" and entry.guid and entry.guid ~= "" then
            local statistics = entry.statistics or {}
            local payload = table.concat({
                "3", entry.name, entry.guid, tostring(entry.points), tostring(entry.level),
                tostring(statistics.enemiesSlain or 0), tostring(statistics.dungeonBosses or 0), tostring(statistics.jumps or 0),
            }, SEPARATOR)
            if #payload <= 255 then send(prefix, payload, "GUILD") end
            self:StoreStats(entry)
        end
    end
end

function Compatibility:BroadcastSelfFound(messageType)
    if not iRC:IsInGuildConnection() then return end
    send(SELF_FOUND_PREFIX, messageType .. "," .. (iRC:GetSelfFoundState() and "1" or "0"), "GUILD")
    self:StoreSelfFound(iRC:GetPlayerName(), iRC:GetSelfFoundState(), "iRC")
end

function Compatibility:BroadcastAll()
    if not iRC:IsInGuildConnection() then return end
    self:BroadcastStats()
    send("RaceLockedForkEU", REQUEST_PAYLOAD, "GUILD")
    self:BroadcastSelfFound("PING")
    iRC:DebugMsg(iRC:Text("FORKEU_REFRESH_SENT"), 3)
end

function iRC:RequestRaceLockedTradeVerification(targetName)
    if not self:IsInGuildConnection() or type(targetName) ~= "string" or targetName == "" then return false end
    local targetKey = self:NormalizeName(targetName)
    local requestedAt = pendingRaceLockedTradeRequests[targetKey]
    if requestedAt and time() - requestedAt < 6 then return true end
    local evidence = self:GetSelfFoundEvidence()
    local isVerified = (UnitLevel("player") or 0) >= 60
        and (evidence.status == "VERIFIED" or evidence.status == "LEVEL_60_EXCEPTION")
    pendingRaceLockedTradeRequests[targetKey] = time()
    send("RaceLocked", "TV:" .. (isVerified and "1" or "0"), "WHISPER", targetName)
    return true
end

local function handleStats(message, sender, source)
    if not iRC:IsGuildMemberName(sender) then return end
    if message == REQUEST_PAYLOAD and source == FORKEU_SOURCE then
        Compatibility:BroadcastStats()
        return
    end
    local entry = parseStats(message, source)
    if entry and iRC:NormalizeName(entry.name) == iRC:NormalizeName(sender) then Compatibility:StoreStats(entry) end
end

local function handleSelfFound(message, sender)
    if not iRC:IsGuildMemberName(sender) then return end
    local messageType, value = tostring(message or ""):match("^([^,]+),([01])$")
    if not messageType then return end
    Compatibility:StoreSelfFound(sender, value == "1", FORKEU_SOURCE)
    if messageType == "PING" then Compatibility:BroadcastSelfFound("PONG") end
end

local function handleGuildFoundRoster(message, sender)
    if not iRC:IsGuildMemberName(sender) or type(message) ~= "string" then return end
    local name, verified, clean = message:match("^S:([^,]+),([01]),([01]),")
    if name and iRC:NormalizeName(name) == iRC:NormalizeName(sender) then
        Compatibility:StoreGuildFoundVerification(name, verified == "1", clean == "1", RACELOCKED_SOURCE)
    end
end

local function handleTradeVerification(message, sender)
    if not iRC:IsGuildMemberName(sender) or type(message) ~= "string" then return end
    local verified = message:match("^TV:([01])$")
    if not verified then return end
    local senderKey = iRC:NormalizeName(sender)
    local requestedAt = pendingRaceLockedTradeRequests[senderKey]
    if requestedAt and time() - requestedAt <= 6 then
        pendingRaceLockedTradeRequests[senderKey] = nil
    else
        local evidence = iRC:GetSelfFoundEvidence()
        local localVerified = (UnitLevel("player") or 0) >= 60
            and (evidence.status == "VERIFIED" or evidence.status == "LEVEL_60_EXCEPTION")
        send("RaceLocked", "TV:" .. (localVerified and "1" or "0"), "WHISPER", sender)
    end
    Compatibility:StoreGuildFoundVerification(sender, verified == "1", verified == "1", RACELOCKED_SOURCE)
    local member = iRC:GetCompatibilityMember(sender)
    if member and member.guildFound then member.guildFound.tradeHandshakeAt = time() end
    if iRC.Enforcement and iRC.Enforcement.CheckTradeRestriction then iRC.Enforcement:CheckTradeRestriction() end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= iRC.Name then return end
        for prefix in pairs(STATS_PREFIXES) do registerPrefix(prefix) end
        registerPrefix(SELF_FOUND_PREFIX)
        registerPrefix(GUILD_FOUND_PREFIX)
    elseif event == "PLAYER_LOGIN" then
        if C_Timer and C_Timer.After then C_Timer.After(4, function() Compatibility:BroadcastAll() end) end
        if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(60, function() Compatibility:BroadcastAll() end) end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, _, sender = ...
        if STATS_PREFIXES[prefix] then
            if prefix == "RaceLocked" then handleTradeVerification(message, sender) end
            handleStats(message, sender, STATS_PREFIXES[prefix])
        elseif prefix == SELF_FOUND_PREFIX then
            handleSelfFound(message, sender)
        elseif prefix == GUILD_FOUND_PREFIX then
            handleGuildFoundRoster(message, sender)
        end
    end
end)
