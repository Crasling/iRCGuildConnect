local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local AllianceRaces = { HUMAN = true, DWARF = true, NIGHTELF = true, GNOME = true, DRAENEI = true }
local HordeRaces = { ORC = true, SCOURGE = true, TAUREN = true, TROLL = true, BLOODELF = true }
local PRESENCE_TIMEOUT = 135
-- RaceLocked only broadcasts its guild-sync data at login and then every five
-- minutes.  Do not apply iRC's much shorter active-poll timeout to that source.
local COMPATIBILITY_TIMEOUT = 360
local reportedPresenceMismatches = {}
local pendingPresenceChecks = {}
local presenceConnection, reviewTicket, reviewAt, selectedOfficer
local PROBE_INTERVAL, LOGIN_GRACE = 15, 60
local sessionStartedAt = time()

function iRC:ResetPresenceNotificationChecks()
    reportedPresenceMismatches, pendingPresenceChecks = {}, {}
    presenceConnection, reviewTicket, reviewAt, selectedOfficer = nil, nil, nil, nil
end

local function queuePresenceReview(delay)
    if not C_Timer or not C_Timer.After then return end
    local at = time() + math.max(1, delay)
    if reviewAt and reviewAt <= at then return end
    local ticket = {}
    reviewTicket, reviewAt = ticket, at
    C_Timer.After(math.max(1, delay), function()
        if reviewTicket ~= ticket then return end
        reviewTicket, reviewAt = nil, nil
        iRC:CheckPresenceMismatches()
    end)
end

local function memberKey(name, guid)
    if guid and guid ~= "" then return "guid:" .. guid end
    return "name:" .. iRC:NormalizeName(name)
end

function iRC:GetMemberAttentionSince(name, verification, connection)
    if connection == nil then connection = self:GetConnection() end
    if not connection or connection.active ~= true then return nil end
    connection.attentionSince = connection.attentionSince or {}
    local key = self:NormalizeName(name)
    local state = verification and verification.state
    if state == "missing" or state == "stale" then
        local record = connection.attentionSince[key]
        if not record then
            record = { since = time(), state = state }
            connection.attentionSince[key] = record
        else
            record.state = state
        end
        return record.since
    end
    connection.attentionSince[key] = nil
    return nil
end

function iRC:FindConnectionProfile(name)
    local connection = self:GetConnection()
    return connection and connection.members[self:NormalizeName(name)] or nil
end

function iRC:RefreshGuildRoster()
    if SetGuildRosterShowOffline then SetGuildRosterShowOffline(true) end
    if GuildRoster then GuildRoster() end
end

function iRC:GetMemberVerification(name, online, profile, context)
    if not online then return { state = "offline", label = "Offline" } end
    local connection
    if context then connection = context.connection else connection = self:GetConnection() end
    if not connection or connection.active ~= true then return { state = "inactive", label = self:Text("GUILD_VERIFICATION_INACTIVE") } end
    local key = self:NormalizeName(name)
    if key == (context and context.selfKey or self:NormalizeName(self:GetPlayerName())) then
        return { state = "verified", label = "This client" }
    end
    local compatibilityMember = (connection.compatibilityMembers or {})[key]
    local compatibility = compatibilityMember and compatibilityMember.stats
    local synced = self.RaceLockedSync and (connection.guildFoundRoster or {})[key]
    local guildFound = compatibilityMember and compatibilityMember.guildFound
    local compatiblePresence = compatibilityMember and compatibilityMember.presence
    local sessionStartedAt = self.ConnectionSessionStartedAt or 0
    if profile and profile.lastSeen and profile.lastSeen >= sessionStartedAt then
        local profileAge = time() - profile.lastSeen
        if profileAge <= PRESENCE_TIMEOUT then
            return { state = "verified", label = "Verified " .. math.max(0, math.floor(profileAge)) .. "s ago" }
        end
    end
    if synced and synced.source == "RaceLocked" and synced.lastSeen and time() - synced.lastSeen <= COMPATIBILITY_TIMEOUT then
        return { state = "compatible", label = self:Text("RL_ROSTER_PRESENT") }
    end
    if guildFound and guildFound.source == "RaceLocked" and guildFound.lastSeen then
        local guildFoundAge = time() - guildFound.lastSeen
        if guildFoundAge <= COMPATIBILITY_TIMEOUT then
            local status = guildFound.verified and guildFound.clean and "verified" or "not verified"
            return { state = "compatible", label = "RaceLocked Guild Found " .. status .. " " .. math.max(0, math.floor(guildFoundAge)) .. "s ago" }
        end
    end
    if compatiblePresence and compatiblePresence.lastSeen then
        local presenceAge = time() - compatiblePresence.lastSeen
        if presenceAge <= PRESENCE_TIMEOUT then
            return { state = "compatible", label = (compatiblePresence.source or "RaceLockedForkEU") .. " presence " .. math.max(0, math.floor(presenceAge)) .. "s ago" }
        end
    end
    if compatibility and compatibility.lastSeen then
        local compatibilityAge = time() - compatibility.lastSeen
        if compatibilityAge <= COMPATIBILITY_TIMEOUT then
            return { state = "compatible", label = (compatibility.source or "RaceLockedForkEU") .. " data " .. math.max(0, math.floor(compatibilityAge)) .. "s ago" }
        end
    end
    if not profile or not profile.lastSeen then
        return { state = "missing", label = "Addon not detected" }
    end
    if profile.lastSeen < sessionStartedAt then
        return { state = "missing", label = "No live iRC response" }
    end
    local age = time() - profile.lastSeen
    return { state = "stale", label = "iRC response expired " .. math.max(0, math.floor(age)) .. "s ago" }
end

function iRC:IsPresenceNotificationLeader()
    local connection = self:GetConnection()
    if not connection or connection.active ~= true or not self:IsGuildAdmin() then return false end
    local ownName = self:NormalizeName(self:GetPlayerName())
    -- This running client is known to have iRC. IsGuildAdmin includes the
    -- enabled testing overrides, even when the game roster shows member rank.
    local candidate = { name = self:GetPlayerName(), rankIndex = self:IsGuildMaster() and 0 or 1 }
    local count = GetNumGuildMembers and GetGuildRosterInfo and GetNumGuildMembers(true) or 0
    local now, sessionStartedAt = time(), self.ConnectionSessionStartedAt or 0
    for index = 1, count do
        local name, _, rankIndex, _, _, _, _, _, online = GetGuildRosterInfo(index)
        if name and online and self:NormalizeName(name) ~= ownName then
            local profile = connection.members[self:NormalizeName(name)]
            local lastSeen = profile and tonumber(profile.lastSeen)
            -- Compatible presence proves RaceLocked/ForkEU is running, not
            -- iRC's notification handler. Only direct, current-session iRC
            -- profiles can participate in this election.
            if lastSeen and lastSeen >= sessionStartedAt and lastSeen <= now and now - lastSeen <= PRESENCE_TIMEOUT then
                if self:IsTestGuildMasterName(name)
                    or (self:IsTestAdminName(name) and profile.testGuildMasterOverride == true) then rankIndex = 0 end
                if type(rankIndex) == "number" and rankIndex >= 0 and rankIndex <= 1
                    and (rankIndex < candidate.rankIndex or (rankIndex == candidate.rankIndex and self:NormalizeName(name) < self:NormalizeName(candidate.name))) then
                    candidate = { name = name, rankIndex = rankIndex }
                end
            end
        end
    end
    return self:NormalizeName(candidate.name) == ownName, candidate.name
end

local function announcePresenceMismatch(member, verification, escalated)
    -- Re-elect immediately before publishing, not just when the probes began.
    if not iRC:IsPresenceNotificationLeader() or not SendChatMessage then return false end
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
    return true
end

function iRC:CheckPresenceMismatches()
    local connection = self:GetConnection()
    if not connection or connection.active ~= true then self:ResetPresenceNotificationChecks(); return end
    if presenceConnection ~= connection then
        self:ResetPresenceNotificationChecks()
        presenceConnection = connection
    end
    local isLeader, leaderName = self:IsPresenceNotificationLeader()
    local leaderKey = leaderName and self:NormalizeName(leaderName)
    if selectedOfficer ~= leaderKey then
        selectedOfficer, pendingPresenceChecks = leaderKey, {}
        if leaderName then self:DebugMsg(self:Text("PRESENCE_OFFICER_SELECTED", leaderName), 3) end
    end
    if not isLeader then
        pendingPresenceChecks, reviewTicket, reviewAt = {}, nil, nil
        self:DebugMsg(leaderName and self:Text("PRESENCE_NOTIFICATION_NOT_LEADER", leaderName)
            or self:Text("PRESENCE_NOTIFICATION_INELIGIBLE"), 3)
        return
    end
    self:DebugMsg(self:Text("PRESENCE_NOTIFICATION_LEADER"), 3)
    local now, probeBatch, currentMembers = time(), {}, {}
    local loginReadyAt = (self.ConnectionSessionStartedAt or sessionStartedAt) + LOGIN_GRACE
    connection.newMemberChecks = connection.newMemberChecks or {}
    connection.newMemberWelcomeNotices = connection.newMemberWelcomeNotices or {}
    for _, member in ipairs(self:GetGuildRosterRows()) do
        local key = self:NormalizeName(member.name)
        local id = memberKey(member.name, member.guid)
        currentMembers[key] = true
        local verification = member.verification or { state = "missing" }
        if not member.online then
            reportedPresenceMismatches[key], pendingPresenceChecks[key] = nil, nil
        elseif verification.state == "verified" or verification.state == "compatible" then
            if reportedPresenceMismatches[key] then self:DebugMsg(self:Text("PRESENCE_RECOVERED", member.name), 3) end
            reportedPresenceMismatches[key], pendingPresenceChecks[key] = nil, nil
            connection.newMemberChecks[id] = nil
        elseif verification.state == "missing" or verification.state == "stale" then
            local report = reportedPresenceMismatches[key]
            -- Begin the escalation's fresh probes 30 seconds before it is due.
            local dueAt = report and report.reportedAt + 300 or now
            if not report or (not report.escalated and now >= dueAt - 2 * PROBE_INTERVAL) then
                local check = pendingPresenceChecks[key]
                if not check then
                    check = { attempts = 0, nextAt = now }
                    pendingPresenceChecks[key] = check
                    self:DebugMsg(self:Text("PRESENCE_CONFIRM_PENDING", member.name), 3)
                end
                if check.attempts < 2 then
                    if now >= check.nextAt then probeBatch[#probeBatch + 1] = check
                    else queuePresenceReview(check.nextAt - now) end
                else
                    local readyAt = math.max(check.nextAt, loginReadyAt, dueAt)
                    if now < readyAt then queuePresenceReview(readyAt - now)
                    else
                        pendingPresenceChecks[key] = nil
                        if report then
                            if not announcePresenceMismatch(member, verification, true) then queuePresenceReview(1); return end
                            report.escalated = true
                        else
                            if not announcePresenceMismatch(member, verification, false) then queuePresenceReview(1); return end
                            reportedPresenceMismatches[key] = { reportedAt = now, escalated = false }
                            self:DebugMsg(self:Text("PRESENCE_MISMATCH", member.name, verification.label or ""), 2)
                            if connection.newMemberChecks[id] and not connection.newMemberWelcomeNotices[id] and SendChatMessage and self:IsPresenceNotificationLeader() then
                                connection.newMemberWelcomeNotices[id] = now
                                SendChatMessage(self:Text("NEW_MEMBER_WELCOME", member.name), "GUILD")
                            end
                            connection.newMemberChecks[id] = nil
                            queuePresenceReview(300 - 2 * PROBE_INTERVAL)
                        end
                    end
                end
            elseif not report.escalated then
                queuePresenceReview(dueAt - 2 * PROBE_INTERVAL - now)
            end
        end
    end
    for key in pairs(pendingPresenceChecks) do if not currentMembers[key] then pendingPresenceChecks[key] = nil end end
    for key in pairs(reportedPresenceMismatches) do if not currentMembers[key] then reportedPresenceMismatches[key] = nil end end
    if #probeBatch > 0 then
        -- One guild-wide batch covers all pending members. A poll merely
        -- received from another client is not evidence that we tried a probe.
        local ircSent = self:RequestGuildPresence(false)
        local compatibleSent = self.Compatibility and self.Compatibility.RequestPresenceCheck and self.Compatibility:RequestPresenceCheck()
        for _, check in ipairs(probeBatch) do
            if ircSent and compatibleSent then check.attempts = check.attempts + 1 end
            check.nextAt = now + PROBE_INTERVAL
        end
        self:DebugMsg(self:Text(ircSent and compatibleSent and "PRESENCE_CONFIRM_PROBE" or "PRESENCE_CONFIRM_UNAVAILABLE", #probeBatch), 3)
        queuePresenceReview(PROBE_INTERVAL)
    end
end

function iRC:CheckNewMemberAddon(memberId)
    if not self:IsGuildConnectionActive() then return true end
    local connection = self:GetConnection()
    if not connection then return true end
    if connection.newMemberWelcomeNotices and connection.newMemberWelcomeNotices[memberId] then return true end
    connection.newMemberChecks = connection.newMemberChecks or {}
    connection.newMemberChecks[memberId] = connection.newMemberChecks[memberId] or time()
    self:CheckPresenceMismatches()
    return connection.newMemberChecks[memberId] == nil
end

function iRC:ScheduleNewMemberAddonCheck(memberId)
    if not self:IsGuildConnectionActive() or not C_Timer or not C_Timer.After then return end
    local connection = self:GetConnection()
    if not connection then return end
    connection.newMemberChecks = connection.newMemberChecks or {}
    connection.newMemberChecks[memberId] = time()
    self:DebugMsg(self:Text("NEW_MEMBER_CHECK", memberId), 3)
    queuePresenceReview(2)
end

function iRC:CheckGuildRosterForNewMembers()
    if not self:IsGuildConnectionActive() then return end
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
    -- One connection snapshot for this synchronous pass; do not cache across
    -- events, so incoming presence/rules and guild changes apply immediately.
    local connection = self:GetConnection()
    local active = connection and connection.active == true
    local profiles = connection and connection.members or {}
    local compatibleMembers = active and connection.compatibilityMembers or {}
    local context = { connection = connection, selfKey = self:NormalizeName(selfName) }
    for index = 1, count do
        local name, _, rankIndex, level, className, _, _, _, online, _, classFile, _, _, _, _, _, guid = GetGuildRosterInfo(index)
        if name then
            local key = self:NormalizeName(name)
            local profile = profiles[key]
            local compatibilityMember = compatibleMembers[key]
            local compatibility = compatibilityMember and compatibilityMember.stats
            local syncedStatus = active and self.RaceLockedSync and self.RaceLockedSync:GetStatus(name, connection)
            local race = profile and profile.race or getRaceFromGuid(guid) or "Unknown"
            if self:NormalizeName(name) == self:NormalizeName(selfName) then
                profile = self:GetLocalProfile()
                race = profile.race
                guid = profile.guid
            end
            local verification = self:GetMemberVerification(name, online and true or false, profile, context)
            local attentionSince = self:GetMemberAttentionSince(name, verification, connection or false)
            local combinedSource = profile and compatibility and ("iRC + " .. (compatibility.source or "RaceLocked")) or nil
            rows[#rows + 1] = {
                name = name, guid = guid or (profile and profile.guid) or "", rankIndex = rankIndex or 99,
                level = (profile and profile.level) or (compatibility and compatibility.level) or level or 1, class = (profile and profile.class) or classFile or className or "UNKNOWN",
                race = race, online = online and true or false, profile = profile,
                compatibility = compatibility,
                compatibilityMember = compatibilityMember,
                raceLockedStatus = syncedStatus or false,
                hasParticipationSnapshot = true,
                -- A member has exactly one canonical row. iRC is preferred when
                -- present; compatible counters only fill missing data and are
                -- never added to iRC counters.
                points = 0,
                hardcorePoints = nil,
                selfFound = profile and profile.selfFound or (compatibilityMember and compatibilityMember.selfFound) or false,
                addonVersion = profile and profile.addonVersion or nil,
                statistics = (profile and profile.statistics) or (compatibility and compatibility.statistics) or nil,
                source = combinedSource or (profile and "iRC") or (compatibility and compatibility.source) or (syncedPoints and "RaceLocked") or nil,
                verification = verification,
                attentionSince = attentionSince,
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
        return string.lower(a.name) < string.lower(b.name)
    end)
    return champions
end

function iRC:GetLeaderboard()
    local leaders = {}
    for _, row in ipairs(self:GetGuildRosterRows()) do
        if row.profile or row.compatibility then
            row.leaderboard = {
                source = row.source or "iRC", level = row.level, statistics = row.statistics or {},
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
                -- Detect expired iRC presence even if WoW still lists the
                -- previous notifier online (for example, addon disabled).
                if iRC:IsGuildConnectionActive() and iRC:IsGuildAdmin() then queuePresenceReview(1) end
            end)
        end
    elseif event == "GUILD_ROSTER_UPDATE" then
        iRC:CheckGuildRosterForNewMembers()
        if iRC:IsGuildConnectionActive() and iRC:IsGuildAdmin() then queuePresenceReview(1) end
        if iRC.ConnectionDashboard then iRC.ConnectionDashboard:RefreshIfShown() end
    end
end)
