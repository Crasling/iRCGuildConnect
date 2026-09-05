local iRL = _G.iRaceLocked
if not iRL then return end

local SEP = "\t"
local WIRE_VERSION = "2"
local requestNumber = 0

local function registerPrefix(prefix)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then return C_ChatInfo.RegisterAddonMessagePrefix(prefix) end
    if RegisterAddonMessagePrefix then return RegisterAddonMessagePrefix(prefix) end
end

local function send(prefix, message, distribution, target)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then return C_ChatInfo.SendAddonMessage(prefix, message, distribution, target) end
    if SendAddonMessage then return SendAddonMessage(prefix, message, distribution, target) end
end

local function split(message)
    local values = {}
    message = tostring(message or "") .. SEP
    for value in message:gmatch("(.-)" .. SEP) do values[#values + 1] = value end
    return values
end

local function completedFromWire(value)
    if not value or value == "" then return {} end
    return { strsplit(",", value) }
end

local function profileWireParts(profile)
    local stats = profile.statistics or {}
    return {
        iRL.Version, profile.name or "Unknown", profile.guid or "", profile.race or "Unknown", profile.class or "UNKNOWN",
        tostring(profile.level or 1), tostring(profile.points or 0), profile.selfFound and "1" or "0",
        tostring(stats.enemiesSlain or 0), tostring(stats.dungeonBosses or 0), tostring(stats.jumps or 0),
        table.concat(profile.completed or {}, ","),
    }
end

local function addProfileParts(parts, profile)
    for _, value in ipairs(profileWireParts(profile)) do parts[#parts + 1] = value end
    local message = table.concat(parts, SEP)
    if #message > 250 then
        parts[#parts] = ""
        message = table.concat(parts, SEP)
    end
    return message
end

local function profileFromWire(parts, startIndex)
    local name = parts[startIndex + 1]
    if not name or name == "" then return nil end
    return {
        addonVersion = parts[startIndex] or "Unknown", name = name, guid = parts[startIndex + 2] or "",
        race = parts[startIndex + 3] or "Unknown", class = parts[startIndex + 4] or "UNKNOWN",
        level = tonumber(parts[startIndex + 5]) or 1, points = tonumber(parts[startIndex + 6]) or 0,
        selfFound = parts[startIndex + 7] == "1",
        statistics = {
            enemiesSlain = tonumber(parts[startIndex + 8]) or 0,
            dungeonBosses = tonumber(parts[startIndex + 9]) or 0,
            jumps = tonumber(parts[startIndex + 10]) or 0,
        },
        completed = completedFromWire(parts[startIndex + 11]), lastSeen = time(),
    }
end

function iRL:GetLocalProfile()
    local raceName, raceFile = UnitRace("player")
    local _, classFile = UnitClass("player")
    return {
        addonVersion = self.Version, name = self:GetPlayerName() or "Unknown", guid = UnitGUID("player") or "",
        race = raceFile or raceName or "Unknown", class = classFile or "UNKNOWN", level = UnitLevel("player") or 1,
        points = self.Achievements and self.Achievements:GetPoints() or 0, selfFound = self:GetSelfFoundState(),
        statistics = self.Statistics and self.Statistics:GetSnapshot() or {},
        completed = self.Achievements and self.Achievements:GetCompletedIds() or {}, lastSeen = time(),
    }
end

function iRL:StoreMemberProfile(profile)
    if type(profile) ~= "table" or not profile.name then return end
    local connection = self:GetConnection()
    if not connection then return end
    connection.members[self:NormalizeName(profile.name)] = profile
    if self.AchievementsUI then self.AchievementsUI:RefreshIfShown() end
    if self.ConnectionDashboard then self.ConnectionDashboard:RefreshIfShown() end
end

function iRL:SendHello()
    if not self:IsInGuildConnection() then return end
    local profile = self:GetLocalProfile()
    self:StoreMemberProfile(profile)
    send(self.Prefix, addProfileParts({ "HELLO", WIRE_VERSION }, profile), "GUILD")
end

function iRL:RequestInspection(targetName)
    if not self:IsInGuildConnection() or type(targetName) ~= "string" or targetName == "" then return false end
    requestNumber = requestNumber + 1
    send(self.Prefix, table.concat({ "INSPECT_REQUEST", WIRE_VERSION, tostring(time()) .. "-" .. tostring(requestNumber) }, SEP), "WHISPER", targetName)
    return true
end

function iRL:SendInspection(targetName, requestId)
    if not self:IsInGuildConnection() or not requestId then return end
    send(self.Prefix, addProfileParts({ "INSPECT_DATA", WIRE_VERSION, requestId }, self:GetLocalProfile()), "WHISPER", targetName)
end

local function senderIsKnown(sender)
    local connection = iRL:GetConnection()
    return connection and connection.members[iRL:NormalizeName(sender)] ~= nil
end

local function handleMessage(prefix, message, sender)
    if prefix ~= iRL.Prefix or not iRL:IsInGuildConnection() then return end
    local parts, kind = split(message), nil
    kind = parts[1]
    if kind == "HELLO" then
        local profile
        if parts[2] == WIRE_VERSION then
            profile = profileFromWire(parts, 3)
        elseif parts[3] then
            profile = { name = parts[3], guid = parts[4], race = parts[5], class = parts[6], level = tonumber(parts[7]) or 1, points = tonumber(parts[8]) or 0, completed = completedFromWire(parts[9]), lastSeen = time() }
        end
        if profile and iRL:NormalizeName(profile.name) == iRL:NormalizeName(sender) then iRL:StoreMemberProfile(profile) end
    elseif kind == "INSPECT_REQUEST" then
        local requestId = parts[2] == WIRE_VERSION and parts[3] or parts[2]
        if requestId and senderIsKnown(sender) then iRL:SendInspection(sender, requestId) end
    elseif kind == "INSPECT_DATA" then
        local profile
        if parts[2] == WIRE_VERSION then
            profile = profileFromWire(parts, 4)
        elseif parts[3] then
            profile = { name = parts[3], guid = parts[4], race = parts[5], class = parts[6], level = tonumber(parts[7]) or 1, points = tonumber(parts[8]) or 0, completed = completedFromWire(parts[9]), lastSeen = time() }
        end
        if profile and senderIsKnown(sender) and iRL:NormalizeName(profile.name) == iRL:NormalizeName(sender) then iRL:StoreMemberProfile(profile) end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_GUILD_UPDATE")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        registerPrefix(iRL.Prefix)
        C_Timer.After(2, function() iRL:SendHello() end)
        if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(60, function() iRL:SendHello() end) end
    elseif event == "PLAYER_GUILD_UPDATE" then
        C_Timer.After(1, function()
            if iRL.Achievements then iRL.Achievements:Evaluate() end
            iRL:SendHello()
        end)
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, _, sender = ...
        handleMessage(prefix, message, sender)
    end
end)
