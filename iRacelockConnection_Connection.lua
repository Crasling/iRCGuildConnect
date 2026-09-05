local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local SEP = "\t"
local WIRE_VERSION = "7"
local requestNumber = 0
local BASE36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local SECONDS_PER_DAY = 86400
local lastPresencePollAt = 0
iRC.ConnectionSessionStartedAt = time()

local function registerPrefix(prefix)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then return C_ChatInfo.RegisterAddonMessagePrefix(prefix) end
    if RegisterAddonMessagePrefix then return RegisterAddonMessagePrefix(prefix) end
end

local function send(prefix, message, distribution, target)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then return C_ChatInfo.SendAddonMessage(prefix, message, distribution, target) end
    if SendAddonMessage then return SendAddonMessage(prefix, message, distribution, target) end
end

local function schedulePresenceReview()
    if not C_Timer or not C_Timer.After then return end
    C_Timer.After(5, function()
        if iRC.CheckPresenceMismatches then iRC:CheckPresenceMismatches() end
    end)
end

local function split(message)
    local values = {}
    message = tostring(message or "") .. SEP
    for value in message:gmatch("(.-)" .. SEP) do values[#values + 1] = value end
    return values
end

local function completedLookup(completed)
    local lookup = {}
    for key, value in pairs(completed or {}) do
        if type(key) == "string" then lookup[key] = value else lookup[value] = true end
    end
    return lookup
end

local function encodeBase36(value, digits)
    value = math.max(0, math.floor(tonumber(value) or 0))
    local output = {}
    for index = digits, 1, -1 do
        output[index] = BASE36:sub((value % 36) + 1, (value % 36) + 1)
        value = math.floor(value / 36)
    end
    return table.concat(output)
end

local function decodeBase36(value)
    return value and tonumber(value, 36) or nil
end

local function completedFromWire(value, dates)
    if not value or value == "" then return {} end
    if value:sub(1, 1) ~= "@" then return {} end
    local catalog = iRC.Achievements and iRC.Achievements.Catalog
    if not catalog then return {} end
    local completed = {}
    local bits = value:sub(2)
    local baseDay = dates and decodeBase36(dates:sub(1, 3)) or nil
    local currentDay = math.floor(time() / SECONDS_PER_DAY)
    for index = 1, #bits do
        if bits:sub(index, index) == "1" and catalog[index] then
            local dateStart = 4 + (index - 1) * 2
            local dateOffset = dates and decodeBase36(dates:sub(dateStart, dateStart + 1)) or nil
            local earnedDay = baseDay and dateOffset and dateOffset > 0 and baseDay + dateOffset - 1 or nil
            completed[catalog[index].id] = {
                earnedAt = earnedDay and earnedDay <= currentDay and earnedDay * SECONDS_PER_DAY or nil,
                verifiedAt = time(),
            }
        end
    end
    return completed
end

local function completedToCompactWire(completed)
    local catalog = iRC.Achievements and iRC.Achievements.Catalog
    if not catalog then return nil end
    local completedById, bits = completedLookup(completed), {}
    for index, achievement in ipairs(catalog) do
        bits[index] = completedById[achievement.id] and "1" or "0"
    end
    return "@" .. table.concat(bits)
end

local function completedDatesToWire(completed)
    local catalog = iRC.Achievements and iRC.Achievements.Catalog
    if not catalog then return nil end
    local completedById, days = completedLookup(completed), {}
    local baseDay
    for _, achievement in ipairs(catalog) do
        local record = completedById[achievement.id]
        local earnedAt = type(record) == "table" and tonumber(record.earnedAt) or nil
        if earnedAt and earnedAt > 0 then
            local earnedDay = math.floor(earnedAt / SECONDS_PER_DAY)
            baseDay = not baseDay and earnedDay or math.min(baseDay, earnedDay)
        end
    end
    if not baseDay then return "" end
    days[1] = encodeBase36(baseDay, 3)
    for index, achievement in ipairs(catalog) do
        local record = completedById[achievement.id]
        local earnedAt = type(record) == "table" and tonumber(record.earnedAt) or nil
        local offset = earnedAt and math.floor(earnedAt / SECONDS_PER_DAY) - baseDay + 1 or 0
        days[index + 1] = offset > 0 and offset < 1296 and encodeBase36(offset, 2) or "00"
    end
    return table.concat(days)
end

local function profileWireParts(profile)
    local stats = profile.statistics or {}
    local evidence = profile.selfFoundEvidence or {}
    return {
        iRC.Version, profile.name or "Unknown", profile.guid or "", profile.race or "Unknown", profile.class or "UNKNOWN",
        tostring(profile.level or 1), tostring(profile.points or 0), profile.selfFound and "1" or "0",
        tostring(stats.enemiesSlain or 0), tostring(stats.dungeonBosses or 0), tostring(stats.jumps or 0),
        completedToCompactWire(profile.completed) or "@",
        completedDatesToWire(profile.completionRecords or profile.completed) or "",
        evidence.status or "UNVERIFIED",
        tostring(math.floor((tonumber(evidence.firstSelfFoundAt) or 0) / SECONDS_PER_DAY)),
        tostring(math.floor((tonumber(evidence.endedAt) or 0) / SECONDS_PER_DAY)),
    }
end

local function addProfileParts(parts, profile)
    for _, value in ipairs(profileWireParts(profile)) do parts[#parts + 1] = value end
    return table.concat(parts, SEP)
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
        completed = completedFromWire(parts[startIndex + 11], parts[startIndex + 12]),
        selfFoundEvidence = {
            status = parts[startIndex + 13] or "UNVERIFIED",
            firstSelfFoundAt = (tonumber(parts[startIndex + 14]) or 0) * SECONDS_PER_DAY,
            endedAt = (tonumber(parts[startIndex + 15]) or 0) * SECONDS_PER_DAY,
        },
        lastSeen = time(),
    }
end

function iRC:GetLocalProfile()
    local raceName, raceFile = UnitRace("player")
    local _, classFile = UnitClass("player")
    local completionRecords = self.Achievements and self.Achievements:GetCompleted() or {}
    return {
        addonVersion = self.Version, name = self:GetPlayerName() or "Unknown", guid = UnitGUID("player") or "",
        race = raceFile or raceName or "Unknown", class = classFile or "UNKNOWN", level = UnitLevel("player") or 1,
        points = self.Achievements and self.Achievements:GetPoints() or 0, selfFound = self:GetSelfFoundState(), selfFoundEvidence = self:GetSelfFoundEvidence(),
        statistics = self.Statistics and self.Statistics:GetSnapshot() or {},
        completed = self.Achievements and self.Achievements:GetCompletedIds() or {}, completionRecords = completionRecords, lastSeen = time(),
    }
end

function iRC:StoreMemberProfile(profile)
    if type(profile) ~= "table" or not profile.name then return end
    local connection = self:GetConnection()
    if not connection then return end
    connection.members[self:NormalizeName(profile.name)] = profile
    if self.AchievementsUI then self.AchievementsUI:RefreshIfShown() end
    if self.ConnectionDashboard then self.ConnectionDashboard:RefreshIfShown() end
end

function iRC:SendHello()
    if not self:IsInGuildConnection() then return end
    local profile = self:GetLocalProfile()
    self:StoreMemberProfile(profile)
    send(self.Prefix, addProfileParts({ "HELLO", WIRE_VERSION }, profile), "GUILD")
    self:DebugMsg(self:Text("PROFILE_SENT"), 3)
end

function iRC:SendConnectionRules()
    if not self:IsInGuildConnection() or not self:IsGuildMaster() then return end
    local rules = self:GetConnectionRules()
    send(self.Prefix, table.concat({
        "RULES", WIRE_VERSION,
        rules.nativeTongueOnly and "1" or "0",
        rules.selfFoundOnly and "1" or "0",
        rules.level60GuildFound and "1" or "0",
        rules.allowLevel60WithoutSelfFound and "1" or "0",
        rules.sameRaceGroupsOnly and "1" or "0",
        rules.allowLevel60MixedRaceGroups and "1" or "0",
    }, SEP), "GUILD")
    self:DebugMsg(self:Text("RULES_SENT"), 3)
end

function iRC:RequestGuildPresence(isOfficerPoll)
    if not self:IsInGuildConnection() then return false end
    if isOfficerPoll then lastPresencePollAt = time() end
    send(self.Prefix, table.concat({ "PRESENCE_REQUEST", WIRE_VERSION, isOfficerPoll and "OFFICER_POLL" or "REQUEST" }, SEP), "GUILD")
    self:DebugMsg(self:Text("PRESENCE_POLL_SENT"), 3)
    if isOfficerPoll then schedulePresenceReview() end
    return true
end

function iRC:PollGuildPresence()
    if not self:IsGuildAdmin() or time() - lastPresencePollAt < 105 then return false end
    if self:IsGuildMaster() then self:SendConnectionRules() end
    return self:RequestGuildPresence(true)
end

function iRC:RequestInspection(targetName)
    if not self:IsInGuildConnection() or type(targetName) ~= "string" or targetName == "" then return false end
    requestNumber = requestNumber + 1
    send(self.Prefix, table.concat({ "INSPECT_REQUEST", WIRE_VERSION, tostring(time()) .. "-" .. tostring(requestNumber) }, SEP), "WHISPER", targetName)
    return true
end

function iRC:SendInspection(targetName, requestId)
    if not self:IsInGuildConnection() or not requestId then return end
    send(self.Prefix, addProfileParts({ "INSPECT_DATA", WIRE_VERSION, requestId }, self:GetLocalProfile()), "WHISPER", targetName)
end

local function senderIsKnown(sender)
    local connection = iRC:GetConnection()
    return connection and connection.members[iRC:NormalizeName(sender)] ~= nil
end

local function handleMessage(prefix, message, sender)
    if prefix ~= iRC.Prefix or not iRC:IsInGuildConnection() then return end
    local parts, kind = split(message), nil
    kind = parts[1]
    if kind == "HELLO" and parts[2] == WIRE_VERSION then
        local profile = profileFromWire(parts, 3)
        if profile and iRC:NormalizeName(profile.name) == iRC:NormalizeName(sender) then
            iRC:StoreMemberProfile(profile)
            iRC:DebugMsg(iRC:Text("PROFILE_RECEIVED", sender), 3)
        end
    elseif kind == "PRESENCE_REQUEST" and parts[2] == WIRE_VERSION and iRC:IsGuildMemberName(sender) then
        if parts[3] == "OFFICER_POLL" then
            lastPresencePollAt = time()
            schedulePresenceReview()
            if iRC:IsGuildMaster() then iRC:SendConnectionRules() end
        end
        iRC:DebugMsg(iRC:Text("PRESENCE_POLL_RECEIVED", sender), 3)
        iRC:SendHello()
    elseif kind == "INSPECT_REQUEST" then
        local requestId = parts[2] == WIRE_VERSION and parts[3] or nil
        if requestId and senderIsKnown(sender) then iRC:SendInspection(sender, requestId) end
    elseif kind == "INSPECT_DATA" and parts[2] == WIRE_VERSION then
        local profile = profileFromWire(parts, 4)
        if profile and senderIsKnown(sender) and iRC:NormalizeName(profile.name) == iRC:NormalizeName(sender) then iRC:StoreMemberProfile(profile) end
    elseif kind == "RULES" and parts[2] == WIRE_VERSION and iRC:IsGuildMasterName(sender) then
        local connection = iRC:GetConnection()
        if connection then
            connection.rules.nativeTongueOnly = parts[3] == "1"
            connection.rules.selfFoundOnly = parts[4] == "1"
            connection.rules.level60GuildFound = parts[5] == "1"
            connection.rules.allowLevel60WithoutSelfFound = parts[6] == "1"
            connection.rules.sameRaceGroupsOnly = parts[7] == "1"
            connection.rules.allowLevel60MixedRaceGroups = parts[8] == "1"
            if iRC.RefreshOptionsIfShown then iRC:RefreshOptionsIfShown() end
            if iRC.Enforcement then iRC.Enforcement:Refresh() end
            iRC:DebugMsg(iRC:Text("RULES_RECEIVED", sender), 3)
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_GUILD_UPDATE")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        registerPrefix(iRC.Prefix)
        C_Timer.After(2, function()
            iRC:SendHello()
            if iRC:IsGuildAdmin() then iRC:PollGuildPresence() else iRC:RequestGuildPresence() end
            iRC:SendConnectionRules()
        end)
        if C_Timer and C_Timer.NewTicker then
            C_Timer.NewTicker(60, function()
                iRC:SendHello()
                iRC:SendConnectionRules()
            end)
            C_Timer.NewTicker(120, function()
                iRC:PollGuildPresence()
            end)
        end
    elseif event == "PLAYER_GUILD_UPDATE" then
        C_Timer.After(1, function()
            if iRC.Achievements then iRC.Achievements:Evaluate() end
            iRC:SendHello()
            if iRC:IsGuildAdmin() then iRC:PollGuildPresence() else iRC:RequestGuildPresence() end
            iRC:SendConnectionRules()
        end)
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, _, sender = ...
        handleMessage(prefix, message, sender)
    end
end)
