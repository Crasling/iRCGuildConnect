local iRL = _G.iRaceLocked
if not iRL then return end

local Compatibility = {}
iRL.Compatibility = Compatibility

local LEGACY_SEPARATOR = string.char(31)
local LEGACY_PREFIXES = { "RaceLocked", "RaceLockedForkEU" }
local SELF_FOUND_PREFIX = "RLAddon"
local REQUEST_PAYLOAD = "REQUEST"
local broadcastTicker

local function registerPrefix(prefix)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then return C_ChatInfo.RegisterAddonMessagePrefix(prefix) end
    if RegisterAddonMessagePrefix then return RegisterAddonMessagePrefix(prefix) end
end

local function send(prefix, message, distribution)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then return C_ChatInfo.SendAddonMessage(prefix, message, distribution) end
    if SendAddonMessage then return SendAddonMessage(prefix, message, distribution) end
end

local function split(message)
    local fields = {}
    for value in string.gmatch(tostring(message or ""), "([^" .. LEGACY_SEPARATOR .. "]+)") do fields[#fields + 1] = value end
    return fields
end

local function positiveNumber(value, fallback)
    value = tonumber(value) or fallback or 0
    return value < 0 and 0 or value
end

local function parseLegacyStats(message)
    local fields = split(message)
    if #fields < 5 then return nil end
    local version = fields[1]
    local name, guid, points, level, enemies, dungeons, jumps
    if version == "1" and #fields == 5 then
        name, guid, points, level = fields[2], fields[3], fields[4], fields[5]
        enemies, dungeons, jumps = 0, 0, 0
    elseif version == "2" and #fields == 7 then
        name, guid, points, level, dungeons, jumps = fields[2], fields[3], fields[4], fields[5], fields[6], fields[7]
        enemies = 0
    elseif version == "3" and #fields == 8 then
        name, guid, points, level, enemies, dungeons, jumps = fields[2], fields[3], fields[4], fields[5], fields[6], fields[7], fields[8]
    else
        return nil
    end
    if not name or name == "" or not guid or guid == "" then return nil end
    return {
        name = name, guid = guid, points = positiveNumber(points), level = math.max(1, positiveNumber(level, 1)),
        statistics = { enemiesSlain = positiveNumber(enemies), dungeonBosses = positiveNumber(dungeons), jumps = positiveNumber(jumps) },
    }
end

local function callMetric(functionName, fallback)
    local fn = _G[functionName]
    if type(fn) ~= "function" then return fallback end
    local ok, result = pcall(fn)
    return ok and positiveNumber(result, fallback) or fallback
end

function Compatibility:GetLocalStats(source)
    local profile = iRL:GetLocalProfile()
    local statistics = profile.statistics or {}
    local prefix = source == "RaceLockedForkEU" and "RaceLockedForkEU_" or "RaceLocked_"
    return {
        name = profile.name,
        guid = profile.guid,
        level = profile.level,
        points = callMetric(prefix .. "GetPlayerAchievementPoints", profile.points),
        statistics = {
            enemiesSlain = callMetric(prefix .. "GetPlayerEnemiesSlain", statistics.enemiesSlain),
            dungeonBosses = callMetric(prefix .. "GetPlayerDungeonCompletions", statistics.dungeonBosses),
            jumps = callMetric(prefix .. "GetPlayerJumpCount", statistics.jumps),
        },
    }
end

function Compatibility:StoreStats(source, entry)
    if not entry or not entry.name or not iRL:IsInGuildConnection() then return end
    local connection = iRL:GetConnection()
    connection.compatibilityMembers = connection.compatibilityMembers or {}
    local key = iRL:NormalizeName(entry.name)
    local member = connection.compatibilityMembers[key] or { sources = {} }
    member.name = entry.name
    member.guid = entry.guid or member.guid
    member.sources = member.sources or {}
    member.sources[source] = {
        source = source, name = entry.name, guid = entry.guid, level = entry.level, points = entry.points,
        statistics = entry.statistics, lastSeen = time(),
    }
    connection.compatibilityMembers[key] = member
    if iRL.ConnectionDashboard then iRL.ConnectionDashboard:RefreshIfShown() end
end

function Compatibility:StoreSelfFound(name, selfFound)
    if not name or not iRL:IsInGuildConnection() then return end
    local connection = iRL:GetConnection()
    connection.compatibilityMembers = connection.compatibilityMembers or {}
    local key = iRL:NormalizeName(name)
    local member = connection.compatibilityMembers[key] or { name = name, sources = {} }
    member.name = member.name or name
    member.selfFound = selfFound and true or false
    member.selfFoundLastSeen = time()
    connection.compatibilityMembers[key] = member
    if iRL.ConnectionDashboard then iRL.ConnectionDashboard:RefreshIfShown() end
end

function iRL:GetCompatibilityMember(name)
    local connection = self:GetConnection()
    return connection and connection.compatibilityMembers and connection.compatibilityMembers[self:NormalizeName(name)] or nil
end

function iRL:GetCompatibilityStats(name)
    local member = self:GetCompatibilityMember(name)
    if not member or not member.sources then return nil end
    return member.sources.RaceLockedForkEU or member.sources.RaceLocked
end

function Compatibility:BroadcastStats(prefix)
    if not iRL:IsInGuildConnection() then return end
    local entry = self:GetLocalStats(prefix)
    if not entry.name or entry.name == "" or not entry.guid or entry.guid == "" then return end
    local statistics = entry.statistics or {}
    local payload = table.concat({ "3", entry.name, entry.guid, tostring(entry.points), tostring(entry.level), tostring(statistics.enemiesSlain or 0), tostring(statistics.dungeonBosses or 0), tostring(statistics.jumps or 0) }, LEGACY_SEPARATOR)
    if #payload > 255 then return end
    send(prefix, payload, "GUILD")
    self:StoreStats(prefix, entry)
end

function Compatibility:BroadcastAll()
    for _, prefix in ipairs(LEGACY_PREFIXES) do self:BroadcastStats(prefix) end
    self:BroadcastSelfFound("PING")
end

function Compatibility:BroadcastSelfFound(messageType)
    if not iRL:IsInGuildConnection() then return end
    send(SELF_FOUND_PREFIX, messageType .. "," .. (iRL:GetSelfFoundState() and "1" or "0"), "GUILD")
    self:StoreSelfFound(iRL:GetPlayerName(), iRL:GetSelfFoundState())
end

local function handleSelfFound(message, sender)
    if not iRL:IsGuildMemberName(sender) then return end
    local messageType, value = tostring(message or ""):match("^([^,]+),([01])$")
    if not messageType then return end
    Compatibility:StoreSelfFound(sender, value == "1")
    if messageType == "PING" then Compatibility:BroadcastSelfFound("PONG") end
end

local function handleLegacy(prefix, message, sender)
    if not iRL:IsGuildMemberName(sender) then return end
    if message == REQUEST_PAYLOAD then
        if prefix == "RaceLockedForkEU" then Compatibility:BroadcastStats(prefix) end
        return
    end
    local entry = parseLegacyStats(message)
    if entry and iRL:NormalizeName(entry.name) == iRL:NormalizeName(sender) then Compatibility:StoreStats(prefix, entry) end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName ~= iRL.Name then return end
        registerPrefix(SELF_FOUND_PREFIX)
        for _, prefix in ipairs(LEGACY_PREFIXES) do registerPrefix(prefix) end
    elseif event == "PLAYER_LOGIN" then
        C_Timer.After(4, function() Compatibility:BroadcastAll() end)
        if C_Timer and C_Timer.NewTicker then broadcastTicker = C_Timer.NewTicker(60, function() Compatibility:BroadcastAll() end) end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, _, sender = ...
        if prefix == SELF_FOUND_PREFIX then
            handleSelfFound(message, sender)
        elseif prefix == "RaceLocked" or prefix == "RaceLockedForkEU" then
            handleLegacy(prefix, message, sender)
        end
    end
end)
