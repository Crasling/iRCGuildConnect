local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local AllianceRaces = { HUMAN = true, DWARF = true, NIGHTELF = true, GNOME = true, DRAENEI = true }
local HordeRaces = { ORC = true, SCOURGE = true, TAUREN = true, TROLL = true, BLOODELF = true }
local PRESENCE_TIMEOUT = 135
local reportedPresenceMismatches = {}

local function memberKey(name, guid)
    if guid and guid ~= "" then return "guid:" .. guid end
    return "name:" .. iRC:NormalizeName(name)
end

function iRC:FindConnectionProfile(name)
    local connection = self:GetConnection()
    return connection and connection.members[self:NormalizeName(name)] or nil
end

function iRC:RefreshGuildRoster()
    if SetGuildRosterShowOffline then SetGuildRosterShowOffline(true) end
    if GuildRoster then GuildRoster() end
end

function iRC:GetMemberVerification(name, online, profile)
    if not online then return { state = "offline", label = "Offline" } end
    if self:NormalizeName(name) == self:NormalizeName(self:GetPlayerName()) then
        return { state = "verified", label = "This client" }
    end
    local compatibility = self.GetCompatibilityStats and self:GetCompatibilityStats(name)
    local compatibilityMember = self.GetCompatibilityMember and self:GetCompatibilityMember(name)
    local guildFound = compatibilityMember and compatibilityMember.guildFound
    if not profile and guildFound and guildFound.source == "RaceLocked" and guildFound.lastSeen then
        local guildFoundAge = time() - guildFound.lastSeen
        if guildFoundAge <= PRESENCE_TIMEOUT then
            local status = guildFound.verified and guildFound.clean and "verified" or "not verified"
            return { state = "compatible", label = "RaceLocked Guild Found " .. status .. " " .. math.max(0, math.floor(guildFoundAge)) .. "s ago" }
        end
    end
    if not profile and compatibility and compatibility.lastSeen then
        local compatibilityAge = time() - compatibility.lastSeen
        if compatibilityAge <= PRESENCE_TIMEOUT then
            return { state = "compatible", label = (compatibility.source or "RaceLockedForkEU") .. " data " .. math.max(0, math.floor(compatibilityAge)) .. "s ago" }
        end
    end
    if not profile or not profile.lastSeen then
        return { state = "missing", label = "Addon not detected" }
    end
    local sessionStartedAt = self.ConnectionSessionStartedAt or 0
    if profile.lastSeen < sessionStartedAt then
        return { state = "missing", label = "No live iRC response" }
    end
    local age = time() - profile.lastSeen
    if age > PRESENCE_TIMEOUT then
        return { state = "stale", label = "iRC response expired" }
    end
    return { state = "verified", label = "Verified " .. math.max(0, math.floor(age)) .. "s ago" }
end

function iRC:IsPresenceNotificationLeader()
    if not self:IsGuildAdmin() then return false end
    local candidate, count = nil, GetNumGuildMembers and GetNumGuildMembers(true) or 0
    for index = 1, count do
        local name, _, rankIndex, _, _, _, _, _, online = GetGuildRosterInfo(index)
        if name and online and type(rankIndex) == "number" and rankIndex <= 1 then
            local profile = self:FindConnectionProfile(name)
            if self:NormalizeName(name) == self:NormalizeName(self:GetPlayerName()) then profile = self:GetLocalProfile() end
            local verification = self:GetMemberVerification(name, true, profile)
            if verification.state == "verified" or verification.state == "compatible" then
                if not candidate or rankIndex < candidate.rankIndex or (rankIndex == candidate.rankIndex and self:NormalizeName(name) < self:NormalizeName(candidate.name)) then
                    candidate = { name = name, rankIndex = rankIndex }
                end
            end
        end
    end
    return candidate and self:NormalizeName(candidate.name) == self:NormalizeName(self:GetPlayerName()) or false
end

local function announcePresenceMismatch(member, verification, escalated)
    local reason = verification.label or iRC:Text("PRESENCE_NO_LIVE_RESPONSE")
    local officerMessage = escalated
        and iRC:Text("PRESENCE_OFFICER_ESCALATION", member.name, reason)
        or iRC:Text("PRESENCE_OFFICER_NOTICE", member.name, reason)
    local whisperMessage = escalated
        and iRC:Text("PRESENCE_PLAYER_ESCALATION")
        or iRC:Text("PRESENCE_PLAYER_NOTICE")
    if SendChatMessage then
        SendChatMessage(officerMessage, "OFFICER")
        SendChatMessage(whisperMessage, "WHISPER", nil, member.name)
        if escalated then
            SendChatMessage(iRC:Text("PRESENCE_GUILD_ESCALATION", member.name), "GUILD")
        end
    end
end

function iRC:CheckPresenceMismatches()
    if not self:IsPresenceNotificationLeader() then
        self:DebugMsg(self:Text("PRESENCE_NOTIFICATION_NOT_LEADER"), 3)
        return
    end
    self:DebugMsg(self:Text("PRESENCE_NOTIFICATION_LEADER"), 3)
    for _, member in ipairs(self:GetGuildRosterRows()) do
        local key = self:NormalizeName(member.name)
        local verification = member.verification or { state = "missing" }
        if not member.online then
            reportedPresenceMismatches[key] = nil
        elseif verification.state == "verified" or verification.state == "compatible" then
            if reportedPresenceMismatches[key] then self:DebugMsg(self:Text("PRESENCE_RECOVERED", member.name), 3) end
            reportedPresenceMismatches[key] = nil
        elseif verification.state == "missing" or verification.state == "stale" then
            local report = reportedPresenceMismatches[key]
            if not report then
                report = { reportedAt = time(), escalated = false }
                reportedPresenceMismatches[key] = report
                self:DebugMsg(self:Text("PRESENCE_MISMATCH", member.name, verification.label or ""), 2)
                announcePresenceMismatch(member, verification, false)
                if C_Timer and C_Timer.After then
                    C_Timer.After(300, function()
                        if iRC.CheckPresenceMismatches then iRC:CheckPresenceMismatches() end
                    end)
                end
            elseif not report.escalated and time() - report.reportedAt >= 300 then
                report.escalated = true
                announcePresenceMismatch(member, verification, true)
            end
        end
    end
end

function iRC:CheckNewMemberAddon(memberId)
    local connection = self:GetConnection()
    if not connection then return true end
    connection.newMemberWelcomeNotices = connection.newMemberWelcomeNotices or {}
    connection.newMemberChecks = connection.newMemberChecks or {}
    if connection.newMemberWelcomeNotices[memberId] then return true end
    local newMember
    for _, member in ipairs(self:GetGuildRosterRows()) do
        if memberKey(member.name, member.guid) == memberId then newMember = member break end
    end
    if not newMember or not newMember.online then return true end
    local checkStartedAt = connection.newMemberChecks[memberId] or time()
    if (newMember.profile and newMember.profile.lastSeen and newMember.profile.lastSeen >= checkStartedAt)
        or newMember.compatibility then
        connection.newMemberChecks[memberId] = nil
        return true
    end
    if not self:IsPresenceNotificationLeader() then return false end
    connection.newMemberWelcomeNotices[memberId] = time()
    connection.newMemberChecks[memberId] = nil
    if SendChatMessage then
        SendChatMessage(self:Text("NEW_MEMBER_WELCOME", newMember.name), "GUILD")
    end
    return true
end

function iRC:ScheduleNewMemberAddonCheck(memberId)
    if not C_Timer or not C_Timer.After then return end
    local connection = self:GetConnection()
    if not connection then return end
    connection.newMemberChecks = connection.newMemberChecks or {}
    connection.newMemberChecks[memberId] = time()
    self:DebugMsg(self:Text("NEW_MEMBER_CHECK", memberId), 3)
    C_Timer.After(2, function()
        if iRC:IsPresenceNotificationLeader() then iRC:RequestGuildPresence(true) end
    end)
    C_Timer.After(10, function()
        if iRC.CheckNewMemberAddon then iRC:CheckNewMemberAddon(memberId) end
    end)
end

function iRC:CheckGuildRosterForNewMembers()
    local connection = self:GetConnection()
    local count = GetNumGuildMembers and GetNumGuildMembers(true) or 0
    if not connection or count < 1 or not GetGuildRosterInfo then return end
    local previous = connection.rosterMembers or {}
    local current, newMembers = {}, {}
    local hasBaseline = connection.rosterBaselineReady and true or false
    for index = 1, count do
        local name, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(index)
        if name then
            local id = memberKey(name, guid)
            current[id] = true
            if hasBaseline and not previous[id] then newMembers[#newMembers + 1] = id end
        end
    end
    connection.rosterMembers = current
    connection.rosterBaselineReady = true
    for _, memberId in ipairs(newMembers) do self:ScheduleNewMemberAddonCheck(memberId) end
end

local function getRaceFromGuid(guid)
    if not guid or not GetPlayerInfoByGUID then return nil end
    local _, _, localizedRace, raceFile = GetPlayerInfoByGUID(guid)
    return raceFile or localizedRace
end

function iRC:GetGuildRosterRows()
    local rows, count = {}, GetNumGuildMembers and GetNumGuildMembers(true) or 0
    local selfName = self:GetPlayerName()
    for index = 1, count do
        local name, _, rankIndex, level, className, _, _, _, online, _, classFile, _, _, _, _, _, guid = GetGuildRosterInfo(index)
        if name then
            local profile = self:FindConnectionProfile(name)
            local compatibility = self.GetCompatibilityStats and self:GetCompatibilityStats(name) or nil
            local compatibilityMember = self.GetCompatibilityMember and self:GetCompatibilityMember(name) or nil
            local race = profile and profile.race or getRaceFromGuid(guid) or "Unknown"
            if self:NormalizeName(name) == self:NormalizeName(selfName) then
                profile = self:GetLocalProfile()
                race = profile.race
                guid = profile.guid
            end
            local verification = self:GetMemberVerification(name, online and true or false, profile)
            local combinedSource = profile and compatibility and ("iRC + " .. (compatibility.source or "RaceLocked")) or nil
            rows[#rows + 1] = {
                name = name, guid = guid or (profile and profile.guid) or "", rankIndex = rankIndex or 99,
                level = (profile and profile.level) or (compatibility and compatibility.level) or level or 1, class = (profile and profile.class) or classFile or className or "UNKNOWN",
                race = race, online = online and true or false, profile = profile,
                compatibility = compatibility,
                -- A member has exactly one canonical row. iRC is preferred when
                -- present; compatible counters only fill missing data and are
                -- never added to iRC counters.
                points = (profile and profile.points) or (compatibility and compatibility.points) or 0,
                selfFound = profile and profile.selfFound or (compatibilityMember and compatibilityMember.selfFound) or false,
                addonVersion = profile and profile.addonVersion or nil,
                statistics = (profile and profile.statistics) or (compatibility and compatibility.statistics) or nil,
                source = combinedSource or (profile and "iRC") or (compatibility and compatibility.source) or nil,
                verification = verification,
            }
        end
    end
    if #rows == 0 and self:IsInGuildConnection() then
        local profile = self:GetLocalProfile()
        rows[1] = { name = profile.name, guid = profile.guid, rankIndex = 0, level = profile.level, class = profile.class, race = profile.race, online = true, profile = profile, points = profile.points, selfFound = profile.selfFound, addonVersion = profile.addonVersion, statistics = profile.statistics, verification = self:GetMemberVerification(profile.name, true, profile) }
    end
    table.sort(rows, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
    return rows
end

function iRC:GetRaceOverview()
    local groups = {}
    local connection = self:GetConnection()
    for _, row in ipairs(self:GetGuildRosterRows()) do
        local race = row.race or "Unknown"
        local group = groups[race]
        if not group then
            group = {
                race = race,
                faction = AllianceRaces[race] and "Alliance" or (HordeRaces[race] and "Horde" or "Unknown"),
                guildName = connection and connection.guildName or "No guild",
                members = 0,
                totalLevel = 0,
                points = 0,
                addonUsers = 0,
                selfFound = 0,
                classes = {},
            }
            groups[race] = group
        end
        group.members = group.members + 1
        group.totalLevel = group.totalLevel + (row.level or 1)
        group.points = group.points + (row.points or 0)
        if row.profile or row.compatibility then group.addonUsers = group.addonUsers + 1 end
        if row.selfFound then group.selfFound = group.selfFound + 1 end
        group.classes[row.class or "UNKNOWN"] = (group.classes[row.class or "UNKNOWN"] or 0) + 1
    end
    local result = {}
    for _, group in pairs(groups) do
        group.averageLevel = group.members > 0 and math.floor((group.totalLevel / group.members) * 10 + 0.5) / 10 or 0
        result[#result + 1] = group
    end
    table.sort(result, function(a, b)
        if a.faction ~= b.faction then return a.faction < b.faction end
        return a.race < b.race
    end)
    return result
end

function iRC:GetChampions()
    local _, playerRace = UnitRace("player")
    local champions = {}
    for _, row in ipairs(self:GetGuildRosterRows()) do
        if row.race == playerRace then champions[#champions + 1] = row end
    end
    table.sort(champions, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        if a.points ~= b.points then return a.points > b.points end
        return string.lower(a.name) < string.lower(b.name)
    end)
    return champions
end

function iRC:GetLeaderboard()
    local leaders = {}
    for _, row in ipairs(self:GetGuildRosterRows()) do
        if row.profile or row.compatibility then
            row.leaderboard = {
                source = row.source or "iRC", points = row.points, level = row.level, statistics = row.statistics or {},
            }
            leaders[#leaders + 1] = row
        end
    end
    table.sort(leaders, function(a, b)
        if a.leaderboard.level ~= b.leaderboard.level then return a.leaderboard.level > b.leaderboard.level end
        return string.lower(a.name) < string.lower(b.name)
    end)
    return leaders
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(3, function() iRC:RefreshGuildRoster() end)
        if C_Timer and C_Timer.NewTicker then
            C_Timer.NewTicker(15, function()
                if iRC.ConnectionDashboard then iRC.ConnectionDashboard:RefreshIfShown() end
            end)
        end
    elseif event == "GUILD_ROSTER_UPDATE" then
        iRC:CheckGuildRosterForNewMembers()
        if iRC.ConnectionDashboard then iRC.ConnectionDashboard:RefreshIfShown() end
    end
end)
