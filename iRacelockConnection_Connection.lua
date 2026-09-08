local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local SEP = "\t"
local WIRE_VERSION = "9"
local requestNumber = 0
local SECONDS_PER_DAY = 86400
local lastPresencePollAt = 0
local ACTIVATION_REQUEST_COOLDOWN = 10
local lastActivationRequestAt, lastActivationRequestGuild
local guildUpdatePending = false
local ignoreGuildUpdatesUntil = 0
local seenGroupViolations = {}
local RULE_AUTHORITY_TIMEOUT = 135
local incidentUploadAt = {}
local guildFoundAuditUploadAt = {}
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

local function profileWireParts(profile)
    local evidence = profile.selfFoundEvidence or {}
    return {
        iRC.Version, profile.name or "Unknown", profile.guid or "", profile.race or "Unknown", profile.class or "UNKNOWN",
        tostring(profile.level or 1), "0", profile.selfFound and "1" or "0",
        "0", "0", "0",
        "@", "",
        evidence.status or "UNVERIFIED",
        tostring(math.floor((tonumber(evidence.firstSelfFoundAt) or 0) / SECONDS_PER_DAY)),
        tostring(math.floor((tonumber(evidence.endedAt) or 0) / SECONDS_PER_DAY)),
        "0",
        profile.shareGlobalRaceGrid and "1" or "0",
        profile.testGuildMasterOverride and "1" or "0",
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
        level = tonumber(parts[startIndex + 5]) or 1,
        selfFound = parts[startIndex + 7] == "1",
        selfFoundEvidence = {
            status = parts[startIndex + 13] or "UNVERIFIED",
            firstSelfFoundAt = (tonumber(parts[startIndex + 14]) or 0) * SECONDS_PER_DAY,
            endedAt = (tonumber(parts[startIndex + 15]) or 0) * SECONDS_PER_DAY,
        },
        lastSeen = time(),
        shareGlobalRaceGrid = parts[startIndex + 17] == "1",
        testGuildMasterOverride = parts[startIndex + 18] == "1",
    }
end

function iRC:GetLocalProfile()
    local raceName, raceFile = UnitRace("player")
    local _, classFile = UnitClass("player")
    return {
        addonVersion = self.Version, name = self:GetPlayerName() or "Unknown", guid = UnitGUID("player") or "",
        race = raceFile or raceName or "Unknown", class = classFile or "UNKNOWN", level = UnitLevel("player") or 1,
        selfFound = self:GetSelfFoundState(), selfFoundEvidence = self:GetSelfFoundEvidence(),
        shareGlobalRaceGrid = true,
        testGuildMasterOverride = self:IsTestAdminGuildMaster(),
        lastSeen = time(),
    }
end

function iRC:StoreMemberProfile(profile)
    if type(profile) ~= "table" or not profile.name or not self:IsGuildConnectionActive() then return end
    self:CheckForNewVersion(profile.addonVersion)
    local connection = self:GetConnection()
    if not connection then return end
    connection.members[self:NormalizeName(profile.name)] = profile
    if self.MainUI then self.MainUI:RefreshIfShown() end
    if self.ConnectionDashboard then self.ConnectionDashboard:RefreshIfShown() end
end

function iRC:SendHello(targetName)
    if not self:IsGuildConnectionActive() then return end
    local profile = self:GetLocalProfile()
    self:StoreMemberProfile(profile)
    send(self.Prefix, addProfileParts({ "HELLO", WIRE_VERSION }, profile), targetName and "WHISPER" or "GUILD", targetName)
    self:DebugMsg(self:Text("PROFILE_SENT"), 3)
end

function iRC:SendGuildActivation(targetName)
    if not self:IsInGuildConnection() then return end
    local isBroadcaster = self:IsRulesetBroadcaster()
    if not self:IsGuildMaster() and not isBroadcaster then return end
    local distribution = targetName and "WHISPER" or "GUILD"
    send(self.Prefix, table.concat({ "GUILD_ACTIVATION", WIRE_VERSION, self:IsGuildConnectionActive() and "1" or "0" }, SEP), distribution, targetName)
    self:DebugMsg(self:Text("GUILD_ACTIVATION_SENT", self:IsGuildConnectionActive() and self:Text("GUILD_ACTIVE") or self:Text("GUILD_INACTIVE")), 3)
end

function iRC:RequestGuildActivation()
    if not self:IsInGuildConnection() or self:IsGuildConnectionActive() or self:IsGuildMaster() then return false end
    local guildKey, now = self:GetGuildKey(), GetTime()
    if lastActivationRequestGuild == guildKey and lastActivationRequestAt
        and now - lastActivationRequestAt < ACTIVATION_REQUEST_COOLDOWN then return false end
    lastActivationRequestGuild, lastActivationRequestAt = guildKey, now
    send(self.Prefix, table.concat({ "GUILD_ACTIVATION_REQUEST", WIRE_VERSION }, SEP), "GUILD")
    self:DebugMsg(self:Text("GUILD_ACTIVATION_REQUESTED"), 3)
    return true
end

local function getRosterRank(name)
    if type(name) ~= "string" or not GetNumGuildMembers or not GetGuildRosterInfo then return nil end
    local wanted = iRC:NormalizeName(name)
    for index = 1, GetNumGuildMembers(true) do
        local memberName, _, rankIndex = GetGuildRosterInfo(index)
        if iRC:NormalizeName(memberName) == wanted then return tonumber(rankIndex) end
    end
end

local function getRulesRank(name, connection)
    local key = iRC:NormalizeName(name)
    local profile = connection and connection.members and connection.members[key]
    if key == iRC:NormalizeName(iRC:GetPlayerName()) and iRC:IsTestAdminGuildMaster() then return 0 end
    if profile and profile.testGuildMasterOverride == true and iRC:IsTestAdminName(name) then return 0 end
    local rankIndex = getRosterRank(name)
    return type(rankIndex) == "number" and rankIndex >= 0 and rankIndex or nil
end

local function getRulesAuthority()
    local connection = iRC:GetConnection()
    if not connection or connection.active ~= true then return nil end
    local ownName, now = iRC:GetPlayerName(), time()
    local bestName, bestRank = nil, nil
    local function consider(name, rank)
        if rank and (not bestRank or rank < bestRank
            or (rank == bestRank and iRC:NormalizeName(name) < iRC:NormalizeName(bestName))) then
            bestName, bestRank = name, rank
        end
    end
    consider(ownName, getRulesRank(ownName, connection))
    local count = GetNumGuildMembers and GetGuildRosterInfo and GetNumGuildMembers(true) or 0
    for index = 1, count do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(index)
        if name and online and iRC:NormalizeName(name) ~= iRC:NormalizeName(ownName) then
            local profile = connection.members[iRC:NormalizeName(name)]
            local lastSeen = profile and tonumber(profile.lastSeen)
            if lastSeen and lastSeen >= (iRC.ConnectionSessionStartedAt or 0)
                and lastSeen <= now and now - lastSeen <= RULE_AUTHORITY_TIMEOUT then
                consider(name, getRulesRank(name, connection))
            end
        end
    end
    return bestName, bestRank
end

local function rulesBackupFingerprint(rules, timestampHex, timestampSource)
    rules = rules or {}
    return table.concat({
        rules.nativeTongueOnly and "1" or "0",
        rules.selfFoundOnly and "1" or "0",
        rules.level60GuildFound and "1" or "0",
        rules.allowLevel60WithoutSelfFound and "1" or "0",
        rules.sameRaceGroupsOnly and "1" or "0",
        rules.allowLevel60MixedRaceGroups and "1" or "0",
        iRC:NormalizeGuildRace(rules.guildRace),
        tostring(math.max(1, math.min(60, math.floor(tonumber(rules.sameRaceMinimumLevel) or 1)))),
        rules.guildGroupsOnly and "1" or "0",
        tostring(math.max(1, math.min(60, math.floor(tonumber(rules.guildGroupsMinimumLevel) or 1)))),
        tostring(rules.guildContacts or ""):gsub("[%c]", " "):sub(1, 60),
        tostring(timestampHex or "0"):lower(),
        tostring(timestampSource or ""):gsub("[%c]", " "):sub(1, 80),
    }, SEP)
end

local function rulesBackupChecksum(value)
    local first, second = 1, 0
    for index = 1, #value do
        first = (first + value:byte(index)) % 65521
        second = (second + first) % 65521
    end
    return string.format("%04x%04x", second, first)
end

local function guildSettingsChecksum(enabled, timestamp, source)
    return rulesBackupChecksum(table.concat({ enabled and "1" or "0", tostring(timestamp or 0), tostring(source or "") }, SEP))
end

function iRC:SendGuildManagementSettings(targetName)
    if not self:IsGuildConnectionActive() or not self:IsGuildAdmin() then return false end
    local connection = self:GetConnection()
    local settings = connection and connection.guildNotifications
    if not settings then return false end
    local timestamp = math.floor(tonumber(settings.timestamp) or 0)
    local source = tostring(settings.source or ""):gsub("[%c]", ""):sub(1, 80)
    -- No officer may invent a timestamp for the default. Only an explicit
    -- rank 0/1 change creates the first package; afterwards either rank may
    -- relay the exact newest value it has received.
    if timestamp <= 0 or source == "" then
        return false
    end
    local enabled = settings.welcomeNewMembers ~= false
    local distribution = targetName and "WHISPER" or "GUILD"
    send(self.Prefix, table.concat({
        "GUILD_SETTINGS", WIRE_VERSION, enabled and "1" or "0", tostring(timestamp), source,
        guildSettingsChecksum(enabled, timestamp, source),
    }, SEP), distribution, targetName)
    self:DebugMsg(self:Text("GUILD_SETTINGS_SENT"), 3)
    return true
end

function iRC:SetNewMemberWelcomeEnabled(enabled)
    if not self:IsGuildConnectionActive() or not self:IsGuildAdmin() then return false end
    local connection = self:GetConnection()
    local settings = connection.guildNotifications
    local now = GetServerTime and GetServerTime() or time()
    settings.welcomeNewMembers = enabled and true or false
    settings.timestamp = math.max(math.floor(tonumber(settings.timestamp) or 0) + 1, now)
    settings.source = self:GetPlayerName()
    self:SendGuildManagementSettings()
    if self.RefreshOptionsIfShown then self:RefreshOptionsIfShown() end
    return true
end

function iRC:IsRulesetBroadcaster()
    local name, rank = getRulesAuthority()
    return name ~= nil and self:NormalizeName(name) == self:NormalizeName(self:GetPlayerName()), name, rank
end

function iRC:SendConnectionRules(targetName)
    local isBroadcaster = self:IsRulesetBroadcaster()
    if not self:IsGuildConnectionActive() or not isBroadcaster then return end
    local rules = self:GetConnectionRules()
    local connection = self:GetConnection()
    local timestampHex, timestampSource = self:EnsureConnectionRulesTimestamp(connection)
    -- A non-GM client may only relay the exact ruleset it previously received.
    -- This prevents a same-rank elected broadcaster from propagating locally
    -- edited values while retaining the Guild Master's timestamp and source.
    if not self:IsGuildMaster()
        and (connection.receivedRulesBackupVersion ~= 1
            or connection.receivedRulesBackup ~= rulesBackupFingerprint(rules, timestampHex, timestampSource)) then
        self:DebugMsg(self:Text("RULES_RELAY_BLOCKED_BACKUP"), 2)
        return false
    end
    local distribution = targetName and "WHISPER" or "GUILD"
    local backup = rulesBackupFingerprint(rules, timestampHex, timestampSource)
    send(self.Prefix, table.concat({
        "RULES", WIRE_VERSION,
        rules.nativeTongueOnly and "1" or "0",
        rules.selfFoundOnly and "1" or "0",
        rules.level60GuildFound and "1" or "0",
        rules.allowLevel60WithoutSelfFound and "1" or "0",
        rules.sameRaceGroupsOnly and "1" or "0",
        rules.allowLevel60MixedRaceGroups and "1" or "0",
        iRC:NormalizeGuildRace(rules.guildRace),
        tostring(math.max(1, math.min(60, math.floor(tonumber(rules.sameRaceMinimumLevel) or 1)))),
        rules.guildGroupsOnly and "1" or "0",
        tostring(math.max(1, math.min(60, math.floor(tonumber(rules.guildGroupsMinimumLevel) or 1)))),
        tostring(rules.guildContacts or ""):gsub("[%c]", " "):sub(1, 60),
        timestampHex,
        tostring(timestampSource or ""):gsub("[%c]", " "):sub(1, 80),
        rulesBackupChecksum(backup),
    }, SEP), distribution, targetName)
    self:DebugMsg(self:Text("RULES_SENT"), 3)
end

function iRC:RequestGuildPresence(isOfficerPoll)
    if not self:IsGuildConnectionActive() then return false end
    if not ((C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage) then return false end
    if isOfficerPoll then lastPresencePollAt = time() end
    send(self.Prefix, table.concat({ "PRESENCE_REQUEST", WIRE_VERSION, isOfficerPoll and "OFFICER_POLL" or "REQUEST" }, SEP), "GUILD")
    self:DebugMsg(self:Text("PRESENCE_POLL_SENT"), 3)
    if isOfficerPoll then schedulePresenceReview() end
    return true
end

function iRC:PollGuildPresence()
    if not self:IsGuildConnectionActive() or not self:IsGuildAdmin() or time() - lastPresencePollAt < 105 then return false end
    return self:RequestGuildPresence(true)
end

function iRC:RequestInspection(targetName)
    if not self:IsGuildConnectionActive() or type(targetName) ~= "string" or targetName == "" then return false end
    requestNumber = requestNumber + 1
    send(self.Prefix, table.concat({ "INSPECT_REQUEST", WIRE_VERSION, tostring(time()) .. "-" .. tostring(requestNumber) }, SEP), "WHISPER", targetName)
    return true
end

function iRC:SendInspection(targetName, requestId)
    if not self:IsGuildConnectionActive() or not requestId then return end
    send(self.Prefix, addProfileParts({ "INSPECT_DATA", WIRE_VERSION, requestId }, self:GetLocalProfile()), "WHISPER", targetName)
end

local function cleanWireText(value, limit)
    return tostring(value or ""):gsub("[%c]", " "):sub(1, limit)
end

local GUILD_FOUND_AUDIT_ACTIONS = {
    TRADE_BLOCKED = true,
    MAIL_BLOCKED = true,
    INBOX_BLOCKED = true,
    AUCTION_HOUSE_BLOCKED = true,
}

function iRC:StoreGuildFoundAudit(record)
    if type(record) ~= "table" or not GUILD_FOUND_AUDIT_ACTIONS[record.action] then return false end
    local connection = self:GetConnection()
    if not connection then return false end
    connection.guildFoundAudit = connection.guildFoundAudit or {}
    local id = cleanWireText(record.id, 100)
    if id == "" then return false end
    for _, existing in ipairs(connection.guildFoundAudit) do
        if existing.id == id then return false end
    end
    connection.guildFoundAudit[#connection.guildFoundAudit + 1] = {
        id = id,
        player = cleanWireText(record.player, 80),
        occurredAt = math.floor(tonumber(record.occurredAt) or time()),
        action = record.action,
        target = cleanWireText(record.target, 80),
        receivedAt = time(),
    }
    while #connection.guildFoundAudit > 200 do table.remove(connection.guildFoundAudit, 1) end
    if self.RefreshOptionsIfShown then self:RefreshOptionsIfShown() end
    return true
end

function iRC:GetGuildFoundAuditRecords()
    local connection = self:GetConnection()
    return connection and connection.guildFoundAudit or {}
end

function iRC:RecordGuildFoundAudit(action, target)
    if (UnitLevel("player") or 0) < 60 or not self:IsGuildFoundRequired()
        or not GUILD_FOUND_AUDIT_ACTIONS[action] then return false end
    local occurredAt = time()
    local player = self:GetPlayerName()
    local id = table.concat({ self:NormalizeName(player), occurredAt, action, cleanWireText(target, 40) }, ":")
    self:StoreGuildFoundAudit({ id = id, player = player, occurredAt = occurredAt, action = action, target = target })
    send(self.Prefix, table.concat({ "GF_AUDIT", WIRE_VERSION, id, tostring(occurredAt), action, cleanWireText(target, 80) }, SEP), "GUILD")
    self:DebugMsg(self:Text("GUILDFOUND_AUDIT_SENT", action), 3)
    return true
end

function iRC:UploadGuildFoundAudit(targetName)
    local targetRank = getRosterRank(targetName)
    if targetRank == nil or targetRank > 1 then return false end
    local key, now = self:NormalizeName(targetName), time()
    if guildFoundAuditUploadAt[key] and now - guildFoundAuditUploadAt[key] < 300 then return false end
    guildFoundAuditUploadAt[key] = now
    local records, sentCount = self:GetGuildFoundAuditRecords(), 0
    for index = #records, math.max(1, #records - 19), -1 do
        local record = records[index]
        if record.player and self:NormalizeName(record.player) == self:NormalizeName(self:GetPlayerName())
            and now - (tonumber(record.occurredAt) or 0) <= 604800 then
            send(self.Prefix, table.concat({
                "GF_AUDIT", WIRE_VERSION, cleanWireText(record.id, 100), tostring(record.occurredAt),
                record.action, cleanWireText(record.target, 80),
            }, SEP), "WHISPER", targetName)
            sentCount = sentCount + 1
        end
    end
    if sentCount > 0 then self:DebugMsg(self:Text("GUILDFOUND_AUDIT_HISTORY_SENT", sentCount, targetName), 3) end
    return sentCount > 0
end

function iRC:SendGroupViolation(record)
    if not self:IsGuildConnectionActive() or type(record) ~= "table" then return false end
    local occurredAt = math.floor(tonumber(record.occurredAt) or time())
    local instanceName = cleanWireText(record.instanceName, 60)
    local players = cleanWireText(table.concat(record.players or {}, ", "), 100)
    local violationId = record.id or (self:NormalizeName(self:GetPlayerName()) .. ":" .. occurredAt)
    record.id = violationId
    send(self.Prefix, table.concat({ "GROUP_VIOLATION", WIRE_VERSION, violationId, tostring(occurredAt), instanceName, players }, SEP), "GUILD")
    local locallyReported = false
    if self:IsPresenceNotificationLeader() and SendChatMessage and not seenGroupViolations[violationId] then
        seenGroupViolations[violationId] = true
        record.reporter = record.reporter or self:GetPlayerName()
        self:StoreOfficerIncident(record)
        SendChatMessage(self:Text("GROUP_VIOLATION_OFFICER", self:GetPlayerName(), instanceName, players), "OFFICER")
        locallyReported = true
    end
    return locallyReported
end

function iRC:StoreOfficerIncident(record)
    if type(record) ~= "table" or not record.id then return false end
    local connection = self:GetConnection()
    if not connection then return false end
    connection.officerIncidents = connection.officerIncidents or {}
    for _, existing in ipairs(connection.officerIncidents) do
        if existing.id == record.id then return false end
    end
    connection.officerIncidents[#connection.officerIncidents + 1] = {
        id = record.id,
        reporter = cleanWireText(record.reporter, 80),
        occurredAt = math.floor(tonumber(record.occurredAt) or time()),
        instanceName = cleanWireText(record.instanceName, 60),
        players = type(record.players) == "table" and cleanWireText(table.concat(record.players, ", "), 100)
            or cleanWireText(record.players, 100),
        reason = cleanWireText(record.reason, 160),
        receivedAt = time(),
    }
    while #connection.officerIncidents > 100 do table.remove(connection.officerIncidents, 1) end
    if self.ConnectionDashboard then self.ConnectionDashboard:RefreshIfShown() end
    return true
end

function iRC:UploadOfficerIncidentsToGM(targetName)
    local _, _, ownRankIndex = GetGuildInfo and GetGuildInfo("player")
    if ownRankIndex ~= 1 or getRosterRank(targetName) ~= 0 then return false end
    local targetKey, now = self:NormalizeName(targetName), time()
    if incidentUploadAt[targetKey] and now - incidentUploadAt[targetKey] < 300 then return false end
    incidentUploadAt[targetKey] = now
    local connection = self:GetConnection()
    local uploaded = false
    for _, record in ipairs(connection and connection.officerIncidents or {}) do
        if now - (tonumber(record.occurredAt) or 0) <= 86400 then
            send(self.Prefix, table.concat({
                "INCIDENT_UPLOAD", WIRE_VERSION,
                cleanWireText(record.id, 70), cleanWireText(record.reporter, 60),
                tostring(math.floor(tonumber(record.occurredAt) or now)),
                cleanWireText(record.instanceName, 45), cleanWireText(record.players, 60),
            }, SEP), "WHISPER", targetName)
            uploaded = true
        end
    end
    if uploaded then self:DebugMsg(self:Text("INCIDENTS_UPLOADED_TO_GM", targetName), 3) end
    return uploaded
end

local function senderIsKnown(sender)
    local connection = iRC:GetConnection()
    return connection and connection.members[iRC:NormalizeName(sender)] ~= nil
end

local function handleMessage(prefix, message, distribution, sender)
    if prefix ~= iRC.Prefix or not iRC:IsInGuildConnection() then return end
    if iRC:NormalizeName(sender) == iRC:NormalizeName(iRC:GetPlayerName()) then return end
    local parts, kind = split(message), nil
    kind = parts[1]
    if kind == "GUILD_ACTIVATION" and parts[2] == WIRE_VERSION and iRC:IsGuildMemberName(sender) then
        local active = parts[3] == "1"
        -- Any elected rank may relay an active connection to a new member, but
        -- only the actual Guild Master may turn an established guild off.
        if not active and not iRC:IsGuildMasterName(sender) then return end
        local changed = iRC:SetGuildConnectionActive(active, true)
        if active and changed then iRC:SendHello() end
        iRC:DebugMsg(iRC:Text("GUILD_ACTIVATION_RECEIVED", sender, active and iRC:Text("GUILD_ACTIVE") or iRC:Text("GUILD_INACTIVE")), 3)
        return
    elseif kind == "GUILD_ACTIVATION_REQUEST" and parts[2] == WIRE_VERSION and iRC:IsRulesetBroadcaster()
        and (distribution == "GUILD" or iRC:IsGuildMemberName(sender)) then
        -- Bootstrap the requesting client directly. A guild broadcast can be
        -- missed while its roster and addon-message state are still loading,
        -- leaving that client inactive and therefore unable to send HELLO.
        iRC:SendGuildActivation(sender)
        if iRC:IsGuildConnectionActive() then
            iRC:SendConnectionRules(sender)
            iRC:SendGuildManagementSettings(sender)
            send(iRC.Prefix, table.concat({ "PRESENCE_REQUEST", WIRE_VERSION, "REQUEST" }, SEP), "WHISPER", sender)
        end
        return
    end
    if not iRC:IsGuildConnectionActive() then return end
    if kind == "HELLO" and parts[2] == WIRE_VERSION then
        local profile = profileFromWire(parts, 3)
        if profile and iRC:NormalizeName(profile.name) == iRC:NormalizeName(sender) then
            iRC:StoreMemberProfile(profile)
            iRC:DebugMsg(iRC:Text("PROFILE_RECEIVED", sender), 3)
            iRC:UploadOfficerIncidentsToGM(sender)
            iRC:UploadGuildFoundAudit(sender)
        end
    elseif kind == "PRESENCE_REQUEST" and parts[2] == WIRE_VERSION and iRC:IsGuildMemberName(sender) then
        if parts[3] == "OFFICER_POLL" then
            lastPresencePollAt = time()
            schedulePresenceReview()
        end
        iRC:DebugMsg(iRC:Text("PRESENCE_POLL_RECEIVED", sender), 3)
        iRC:SendHello(sender)
        iRC:SendConnectionRules(sender)
        iRC:SendGuildManagementSettings(sender)
    elseif kind == "GROUP_VIOLATION" and parts[2] == WIRE_VERSION and iRC:IsGuildMemberName(sender) then
        local violationId, occurredAt = parts[3], tonumber(parts[4])
        local instanceName, players = cleanWireText(parts[5], 60), cleanWireText(parts[6], 100)
        if violationId and violationId ~= "" and #violationId <= 100 and occurredAt
            and occurredAt <= time() + 300 and occurredAt >= time() - 86400
            and iRC:IsPresenceNotificationLeader() and SendChatMessage then
            if not seenGroupViolations[violationId] then
                seenGroupViolations[violationId] = true
                iRC:StoreOfficerIncident({
                    id = violationId, reporter = sender, occurredAt = occurredAt,
                    instanceName = instanceName, players = players,
                })
                SendChatMessage(iRC:Text("GROUP_VIOLATION_OFFICER", sender, instanceName, players), "OFFICER")
            end
            -- Always acknowledge a valid repeat. The first acknowledgement may
            -- have been lost even though the officer notice was already sent.
            send(iRC.Prefix, table.concat({ "GROUP_VIOLATION_ACK", WIRE_VERSION, violationId }, SEP), "WHISPER", sender)
        end
    elseif kind == "GROUP_VIOLATION_ACK" and parts[2] == WIRE_VERSION and iRC:IsGuildMemberName(sender) then
        if iRC.MarkGroupViolationReported then iRC:MarkGroupViolationReported(parts[3]) end
    elseif kind == "GF_AUDIT" and parts[2] == WIRE_VERSION and iRC:IsGuildMemberName(sender) and iRC:IsGuildAdmin() then
        local occurredAt, action = tonumber(parts[4]), parts[5]
        if occurredAt and occurredAt <= time() + 300 and occurredAt >= time() - 604800
            and GUILD_FOUND_AUDIT_ACTIONS[action] then
            iRC:StoreGuildFoundAudit({
                id = cleanWireText(parts[3], 100), player = sender, occurredAt = occurredAt,
                action = action, target = cleanWireText(parts[6], 80),
            })
            iRC:DebugMsg(iRC:Text("GUILDFOUND_AUDIT_RECEIVED", action, sender), 3)
        end
    elseif kind == "INCIDENT_UPLOAD" and parts[2] == WIRE_VERSION and iRC:IsGuildMemberName(sender) then
        local _, _, ownRankIndex = GetGuildInfo and GetGuildInfo("player")
        local occurredAt = tonumber(parts[5])
        if ownRankIndex == 0 and getRosterRank(sender) == 1 and parts[3] and parts[3] ~= "" and occurredAt
            and occurredAt <= time() + 300 and occurredAt >= time() - 86400 then
            iRC:StoreOfficerIncident({
                id = cleanWireText(parts[3], 70), reporter = cleanWireText(parts[4], 60),
                occurredAt = occurredAt, instanceName = cleanWireText(parts[6], 45),
                players = cleanWireText(parts[7], 60),
            })
        end
    elseif kind == "INSPECT_REQUEST" then
        local requestId = parts[2] == WIRE_VERSION and parts[3] or nil
        if requestId and senderIsKnown(sender) then iRC:SendInspection(sender, requestId) end
    elseif kind == "INSPECT_DATA" and parts[2] == WIRE_VERSION then
        local profile = profileFromWire(parts, 4)
        if profile and senderIsKnown(sender) and iRC:NormalizeName(profile.name) == iRC:NormalizeName(sender) then iRC:StoreMemberProfile(profile) end
    elseif kind == "GUILD_SETTINGS" and parts[2] == WIRE_VERSION and iRC:IsGuildMemberName(sender) then
        local senderRank = getRulesRank(sender, iRC:GetConnection())
        local enabled = parts[3] == "1"
        local timestamp = tonumber(parts[4])
        local source = tostring(parts[5] or ""):gsub("[%c]", ""):sub(1, 80)
        local checksum = tostring(parts[6] or ""):lower()
        local now = GetServerTime and GetServerTime() or time()
        if senderRank and senderRank <= 1 and timestamp and timestamp > 0 and timestamp <= now + 300
            and source ~= "" and checksum == guildSettingsChecksum(enabled, timestamp, source) then
            local connection = iRC:GetConnection()
            local settings = connection.guildNotifications
            local savedTimestamp = math.floor(tonumber(settings.timestamp) or 0)
            local savedSource = tostring(settings.source or "")
            if timestamp > savedTimestamp or (timestamp == savedTimestamp and string.lower(source) > string.lower(savedSource)) then
                settings.welcomeNewMembers = enabled
                settings.timestamp = math.floor(timestamp)
                settings.source = source
                iRC:DebugMsg(iRC:Text("GUILD_SETTINGS_RECEIVED", sender), 3)
                if iRC.RefreshOptionsIfShown then iRC:RefreshOptionsIfShown() end
            end
        end
    elseif kind == "RULES_ACK" and parts[2] == WIRE_VERSION and iRC:IsGuildMemberName(sender) then
        local connection = iRC:GetConnection()
        local timestampHex, timestampSource = iRC:EnsureConnectionRulesTimestamp(connection)
        local expected = rulesBackupChecksum(rulesBackupFingerprint(iRC:GetConnectionRules(), timestampHex, timestampSource))
        if tostring(parts[3] or ""):lower() == tostring(timestampHex):lower()
            and tostring(parts[4] or ""):lower() == expected then
            iRC:DebugMsg(iRC:Text("RULES_CHECKSUM_VERIFIED", sender, timestampHex), 3)
        else
            iRC:DebugMsg(iRC:Text("RULES_CHECKSUM_ACK_MISMATCH", sender), 1)
        end
    elseif kind == "RULES" and parts[2] == WIRE_VERSION then
        local connection = iRC:GetConnection()
        local timestampHex = tostring(parts[14] or "0"):lower()
        local timestampSource = tostring(parts[15] or ""):sub(1, 80)
        local validTimestamp = #timestampHex <= 12 and timestampHex:match("^[0-9a-f]+$") ~= nil
        local incomingTimestamp = validTimestamp and (tonumber(timestampHex, 16) or 0) or -1
        local savedHex = tostring(connection and connection.rulesTimestampHex or "0"):lower()
        local savedTimestamp = savedHex:match("^[0-9a-f]+$") and (tonumber(savedHex, 16) or 0) or 0
        local senderRank = getRulesRank(sender, connection)
        if senderRank == 0 then timestampSource = sender end
        local timestampSourceValid = incomingTimestamp == 0
            or (timestampSource ~= "" and iRC:IsGuildMasterName(timestampSource))
        local incomingRules = {
            nativeTongueOnly = parts[3] == "1",
            selfFoundOnly = parts[4] == "1",
            level60GuildFound = parts[5] == "1",
            allowLevel60WithoutSelfFound = parts[6] == "1",
            sameRaceGroupsOnly = parts[7] == "1",
            allowLevel60MixedRaceGroups = parts[8] == "1",
            guildRace = iRC:NormalizeGuildRace(parts[9]),
            sameRaceMinimumLevel = math.max(1, math.min(60, math.floor(tonumber(parts[10]) or 1))),
            guildGroupsOnly = parts[11] == "1",
            guildGroupsMinimumLevel = math.max(1, math.min(60, math.floor(tonumber(parts[12]) or 1))),
            guildContacts = tostring(parts[13] or ""):sub(1, 60),
        }
        local incomingBackup = rulesBackupFingerprint(incomingRules, timestampHex, timestampSource)
        local incomingChecksum = tostring(parts[16] or ""):lower()
        local checksumValid = incomingChecksum == "" or incomingChecksum == rulesBackupChecksum(incomingBackup)
        local sameStampMatches = incomingTimestamp ~= savedTimestamp or not connection
            or connection.receivedRulesBackupVersion ~= 1 or not connection.receivedRulesBackup
            or connection.receivedRulesBackup == incomingBackup
        local authorityName, authorityRank = getRulesAuthority()
        local senderIsAuthority = senderRank ~= nil and (authorityRank == nil or senderRank < authorityRank
            or (senderRank == authorityRank and (not authorityName
                or distribution == "WHISPER"
                or iRC:NormalizeName(authorityName) == iRC:NormalizeName(sender))))
        local timestampAccepted = senderRank == 0 or incomingTimestamp >= savedTimestamp
        if connection and senderIsAuthority and validTimestamp and incomingTimestamp <= time() + 300
            and timestampSourceValid and timestampAccepted and checksumValid and sameStampMatches then
            for key, value in pairs(incomingRules) do connection.rules[key] = value end
            connection.rulesTimestampHex = timestampHex
            connection.rulesTimestampSource = timestampSource
            connection.receivedRulesBackup = incomingBackup
            connection.receivedRulesBackupVersion = 1
            connection.receivedRulesChecksum = rulesBackupChecksum(incomingBackup)
            if incomingRules.selfFoundOnly and incomingRules.level60GuildFound then iRC:MarkGuildFoundRequired(connection) end
            if iRC.RefreshOptionsIfShown then iRC:RefreshOptionsIfShown() end
            if iRC.Enforcement then iRC.Enforcement:Refresh() end
            iRC:DebugMsg(iRC:Text("RULES_RECEIVED", sender), 3)
            send(iRC.Prefix, table.concat({ "RULES_ACK", WIRE_VERSION, timestampHex, connection.receivedRulesChecksum }, SEP), "WHISPER", sender)
        elseif connection and senderRank ~= nil then
            if not checksumValid or not sameStampMatches then
                iRC:DebugMsg(iRC:Text("RULES_CHECKSUM_MISMATCH", sender, timestampHex), 1)
            end
            iRC:DebugMsg(iRC:Text("RULES_IGNORED_LOWER_AUTHORITY", sender), 3)
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
        ignoreGuildUpdatesUntil = GetTime() + 8
        C_Timer.After(2, function()
            iRC:SendGuildActivation()
            iRC:RequestGuildActivation()
            iRC:SendHello()
            if iRC:IsGuildAdmin() then iRC:PollGuildPresence() else iRC:RequestGuildPresence() end
            iRC:SendConnectionRules()
            iRC:SendGuildManagementSettings()
        end)
        if C_Timer and C_Timer.NewTicker then
            C_Timer.NewTicker(60, function()
                iRC:SendGuildActivation()
                iRC:RequestGuildActivation()
                iRC:SendHello()
                iRC:SendConnectionRules()
                iRC:SendGuildManagementSettings()
            end)
            C_Timer.NewTicker(120, function()
                iRC:PollGuildPresence()
            end)
        end
    elseif event == "PLAYER_GUILD_UPDATE" then
        local unit = ...
        if unit ~= "player" or guildUpdatePending or GetTime() < ignoreGuildUpdatesUntil then return end
        guildUpdatePending = true
        C_Timer.After(1, function()
            guildUpdatePending = false
            iRC:SendGuildActivation()
            iRC:RequestGuildActivation()
            iRC:SendHello()
            if iRC:IsGuildAdmin() then iRC:PollGuildPresence() else iRC:RequestGuildPresence() end
            iRC:SendConnectionRules()
            iRC:SendGuildManagementSettings()
        end)
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, distribution, sender = ...
        handleMessage(prefix, message, distribution, sender)
    end
end)
