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
local guildBankTransfers = {}
local MAX_GUILD_BANKS = 32
local MAX_GUILD_BANK_WIRE = 1200
local GUILD_BANK_CHUNK_SIZE = 80
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
        tostring(rules.guildContacts or ""):gsub("[%c]", " "):sub(1, 140),
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

local function guildBanksWire(members)
    local names = {}
    for name, enabled in pairs(members or {}) do if enabled then names[#names + 1] = tostring(name) end end
    table.sort(names)
    return table.concat(names, ",")
end

local function guildBanksChecksum(names, timestamp, source)
    return rulesBackupChecksum(table.concat({ tostring(names or ""), tostring(timestamp or 0), tostring(source or "") }, SEP))
end

local function validBranchChecksum(value)
    value = tostring(value or ""):lower()
    return value == "root" or value:match("^[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$") ~= nil
end

local function resolutionContains(resolutions, checksum)
    checksum = tostring(checksum or "root"):lower()
    for value in tostring(resolutions or ""):lower():gmatch("[^,]+") do
        if value == checksum then return true end
    end
    return false
end

local function validResolutions(resolutions)
    resolutions = tostring(resolutions or ""):lower()
    if #resolutions > 17 then return false end
    if resolutions == "" then return true end
    local count = 0
    for value in resolutions:gmatch("[^,]+") do
        if not validBranchChecksum(value) then return false end
        count = count + 1
    end
    return count > 0 and count <= 2
end

local function resolvedPair(first, second)
    local values = { tostring(first or "root"):lower(), tostring(second or "root"):lower() }
    table.sort(values)
    return table.concat(values, ",")
end

local function mergeGuildBankNames(first, second)
    local names = {}
    for name in (tostring(first or "") .. "," .. tostring(second or "")):gmatch("[^,]+") do
        if name ~= "" then names[name] = true end
    end
    return guildBanksWire(names)
end

local function showManagementConflict(kind, incomingSource, acceptIncoming, keepCurrent, mergeValues, conflictId, currentValue, incomingValue, mergedValue)
    iRC.PendingManagementConflicts = iRC.PendingManagementConflicts or {}
    local existing = iRC.PendingManagementConflicts[kind]
    if existing and conflictId and existing.id == conflictId then return false end
    iRC.PendingManagementConflicts[kind] = {
        id = conflictId,
        source = incomingSource,
        acceptIncoming = acceptIncoming,
        keepCurrent = keepCurrent,
        mergeValues = mergeValues,
        currentValue = currentValue,
        incomingValue = incomingValue,
        mergedValue = mergedValue,
    }
    local label = iRC:Text(kind == "BANKS" and "MANAGEMENT_CONFLICT_BANKS" or "MANAGEMENT_CONFLICT_WELCOME")
    iRC:Print(iRC.Colors.Yellow .. iRC:Text("MANAGEMENT_CONFLICT_CHAT", label, incomingSource) .. iRC.Colors.Reset)
    if iRC.RefreshOptionsIfShown then iRC:RefreshOptionsIfShown() end
    return true
end

function iRC:GetPendingManagementConflict(kind)
    return self.PendingManagementConflicts and self.PendingManagementConflicts[kind] or nil
end

function iRC:ResolveManagementConflict(kind, action)
    local conflicts = self.PendingManagementConflicts
    local conflict = conflicts and conflicts[kind]
    if not conflict then return false end
    local callback = action == "merge" and conflict.mergeValues
        or (action == true or action == "incoming") and conflict.acceptIncoming
        or conflict.keepCurrent
    if not callback or callback() == false then return false end
    conflicts[kind] = nil
    if self.RefreshOptionsIfShown then self:RefreshOptionsIfShown() end
    return true
end

local function sendManagementConflict(target, kind, value, timestamp, source, checksum, parentChecksum, resolutions)
    if kind == "BANKS" and #tostring(value or "") > 120 then
        local total = math.ceil(#value / GUILD_BANK_CHUNK_SIZE)
        local transferId = tostring(checksum or "") .. tostring(timestamp or 0)
        for index = 1, total do
            send(iRC.Prefix, table.concat({
                "MGMT_BANKS_CHUNK", WIRE_VERSION, transferId, tostring(index), tostring(total),
                tostring(timestamp or 0), tostring(source or ""), tostring(checksum or ""),
                tostring(parentChecksum or "root"), tostring(resolutions or ""),
                value:sub((index - 1) * GUILD_BANK_CHUNK_SIZE + 1, index * GUILD_BANK_CHUNK_SIZE),
            }, SEP), "WHISPER", target)
        end
        return true
    end
    return send(iRC.Prefix, table.concat({
        "MGMT_CONFLICT", WIRE_VERSION, kind, tostring(value or ""), tostring(timestamp or 0),
        tostring(source or ""), tostring(checksum or ""), tostring(parentChecksum or ""), tostring(resolutions or ""),
    }, SEP), "WHISPER", target)
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

function iRC:SendGuildBankMetadata(targetName, onlyName)
    if not self:IsGuildConnectionActive() or not self:IsGuildAdmin() then return false end
    local connection = self:GetConnection()
    local exceptions = connection and connection.guildBankExceptions
    local sentAny = false
    for name, detail in pairs(exceptions and exceptions.details or {}) do
        if exceptions.members[name] and (not onlyName or name == onlyName) then
            local note = tostring(detail.note or ""):gsub("[%c]", " "):sub(1, 80)
            send(self.Prefix, table.concat({
                "GUILD_BANK_NOTE", WIRE_VERSION, name,
                tostring(math.floor(tonumber(detail.addedAt) or 0)),
                tostring(detail.addedBy or ""):gsub("[%c]", " "):sub(1, 40),
                tostring(math.floor(tonumber(detail.updatedAt) or detail.addedAt or 0)), note,
            }, SEP), targetName and "WHISPER" or "GUILD", targetName)
            sentAny = true
        end
    end
    return sentAny
end

function iRC:SendGuildContactMetadata(targetName, onlyName)
    if not self:IsGuildConnectionActive() or not self:IsGuildMaster() then return false end
    local connection = self:GetConnection()
    local contacts = tostring(connection.rules.guildContacts or "")
    local active = {}
    for name in contacts:gmatch("[^,]+") do active[name:gsub("^%s+", ""):gsub("%s+$", "")] = true end
    local sentAny = false
    for name, detail in pairs(connection.guildContactDetails or {}) do
        if active[name] and (not onlyName or name == onlyName) then
            send(self.Prefix, table.concat({ "GUILD_CONTACT_NOTE", WIRE_VERSION, name,
                tostring(math.floor(tonumber(detail.addedAt) or 0)),
                tostring(detail.addedBy or ""):gsub("[%c]", " "):sub(1, 40),
                tostring(math.floor(tonumber(detail.updatedAt) or detail.addedAt or 0)),
                tostring(detail.note or ""):gsub("[%c]", " "):sub(1, 80),
            }, SEP), targetName and "WHISPER" or "GUILD", targetName)
            sentAny = true
        end
    end
    return sentAny
end

function iRC:SetGuildContactNote(name, note)
    if not self:IsGuildConnectionActive() or not self:IsGuildMaster() then return false end
    local connection = self:GetConnection()
    local fullName = self:ResolveGuildMemberFullName(name)
    if not fullName or not tostring(connection.rules.guildContacts or ""):find(fullName, 1, true) then return false end
    local now = GetServerTime and GetServerTime() or time()
    local detail = connection.guildContactDetails[fullName] or { addedAt = now, addedBy = self:GetPlayerName() }
    detail.note = tostring(note or ""):gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 80)
    detail.updatedAt = math.max(math.floor(tonumber(detail.updatedAt) or 0) + 1, now)
    connection.guildContactDetails[fullName] = detail
    self:SendGuildContactMetadata(nil, fullName)
    if self.RefreshOptionsIfShown then self:RefreshOptionsIfShown() end
    return true
end

function iRC:SetGuildBankNote(name, note)
    if not self:IsGuildConnectionActive() or not self:IsGuildAdmin() then return false end
    local connection = self:GetConnection()
    local exceptions = connection.guildBankExceptions
    local fullName = self:ResolveGuildMemberFullName(name)
    if not fullName or not exceptions.members[fullName] then return false end
    note = tostring(note or ""):gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 80)
    local now = GetServerTime and GetServerTime() or time()
    local detail = exceptions.details[fullName] or { addedAt = now, addedBy = self:GetPlayerName() }
    detail.note = note
    detail.updatedAt = math.max(math.floor(tonumber(detail.updatedAt) or 0) + 1, now)
    exceptions.details[fullName] = detail
    self:SendGuildBankMetadata(nil, fullName)
    if self.RefreshOptionsIfShown then self:RefreshOptionsIfShown() end
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

function iRC:SendGuildBankExceptions(targetName)
    if not self:IsGuildConnectionActive() or not self:IsGuildAdmin() then return false end
    local connection = self:GetConnection()
    local exceptions = connection and connection.guildBankExceptions
    local timestamp = exceptions and math.floor(tonumber(exceptions.timestamp) or 0) or 0
    local source = exceptions and tostring(exceptions.source or ""):gsub("[%c]", ""):sub(1, 40) or ""
    if timestamp <= 0 or source == "" then return false end
    local names = guildBanksWire(exceptions.members)
    if #names > MAX_GUILD_BANK_WIRE then return false end
    local checksum = guildBanksChecksum(names, timestamp, source)
    if exceptions.checksum and exceptions.checksum ~= checksum then
        self:DebugMsg(self:Text("GUILD_BANKS_RELAY_BLOCKED"), 2)
        return false
    end
    local distribution = targetName and "WHISPER" or "GUILD"
    if #names <= 120 then
        send(self.Prefix, table.concat({
            "GUILD_BANKS", WIRE_VERSION, names, tostring(timestamp), source,
            checksum, tostring(exceptions.parentChecksum or "root"), tostring(exceptions.resolutions or ""),
        }, SEP), distribution, targetName)
    else
        local total = math.ceil(#names / GUILD_BANK_CHUNK_SIZE)
        local transferId = checksum .. tostring(timestamp)
        for index = 1, total do
            send(self.Prefix, table.concat({
                "GUILD_BANKS_CHUNK", WIRE_VERSION, transferId, tostring(index), tostring(total),
                tostring(timestamp), source, checksum, tostring(exceptions.parentChecksum or "root"),
                tostring(exceptions.resolutions or ""),
                names:sub((index - 1) * GUILD_BANK_CHUNK_SIZE + 1, index * GUILD_BANK_CHUNK_SIZE),
            }, SEP), distribution, targetName)
        end
    end
    self:DebugMsg(self:Text("GUILD_BANKS_SENT"), 3)
    if targetName then self:SendGuildBankMetadata(targetName) end
    return true
end

function iRC:SetGuildBankExceptions(value, resolutions)
    if not self:IsGuildConnectionActive() or not self:IsGuildAdmin() then return false end
    local members, count = {}, 0
    for entry in tostring(value or ""):gmatch("[^,;\r\n]+") do
        entry = entry:gsub("^%s+", ""):gsub("%s+$", "")
        if entry ~= "" then
            local fullName = self:ResolveGuildMemberFullName(entry)
            if not fullName then
                self:Print(self.Colors.Red .. self:Text("GUILD_BANK_INVALID_MEMBER", entry) .. self.Colors.Reset)
                return false
            end
            if not members[fullName] then count = count + 1 end
            if count > MAX_GUILD_BANKS then
                self:Print(self.Colors.Red .. self:Text("GUILD_BANK_TOO_MANY") .. self.Colors.Reset)
                return false
            end
            members[fullName] = true
        end
    end
    local connection = self:GetConnection()
    local exceptions = connection.guildBankExceptions
    if #guildBanksWire(members) > MAX_GUILD_BANK_WIRE then
        self:Print(self.Colors.Red .. self:Text("GUILD_BANK_TOO_LONG") .. self.Colors.Reset)
        return false
    end
    local parentChecksum = exceptions.checksum or "root"
    local now = GetServerTime and GetServerTime() or time()
    local previousMembers = exceptions.members or {}
    local previousDetails = exceptions.details or {}
    local details = {}
    for name in pairs(members) do
        details[name] = previousDetails[name]
        if not details[name] and not previousMembers[name] then
            details[name] = { addedAt = now, addedBy = self:GetPlayerName(), updatedAt = now, note = "" }
        end
    end
    exceptions.members = members
    exceptions.details = details
    exceptions.timestamp = math.max(math.floor(tonumber(exceptions.timestamp) or 0) + 1, now)
    exceptions.source = self:GetPlayerName()
    exceptions.parentChecksum = parentChecksum
    exceptions.resolutions = tostring(resolutions or ""):lower():sub(1, 17)
    exceptions.checksum = guildBanksChecksum(guildBanksWire(members), exceptions.timestamp, exceptions.source)
    self:SendGuildBankExceptions()
    self:SendGuildBankMetadata()
    if self.RefreshOptionsIfShown then self:RefreshOptionsIfShown() end
    self:Print(self:Text("GUILD_BANK_SAVED", count))
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
        tostring(rules.guildContacts or ""):gsub("[%c]", " "):sub(1, 140),
        timestampHex,
        tostring(timestampSource or ""):gsub("[%c]", " "):sub(1, 80),
        rulesBackupChecksum(backup),
    }, SEP), distribution, targetName)
    if self:IsGuildMaster() and self.SendGuildContactMetadata then self:SendGuildContactMetadata(targetName) end
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
    if ((UnitLevel("player") or 0) < 60 and not self:IsGuildBankException(self:GetPlayerName())) or not self:IsGuildFoundRequired()
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
    if (kind == "GUILD_BANKS_CHUNK" or kind == "MGMT_BANKS_CHUNK") and parts[2] == WIRE_VERSION
        and iRC:IsGuildMemberName(sender) then
        local transferId = tostring(parts[3] or "")
        local index, total = tonumber(parts[4]), tonumber(parts[5])
        local timestamp, source = tonumber(parts[6]), tostring(parts[7] or "")
        local checksum, parentChecksum = tostring(parts[8] or ""):lower(), tostring(parts[9] or "root"):lower()
        local resolutions, chunk = tostring(parts[10] or ""):lower(), tostring(parts[11] or "")
        if transferId == "" or #transferId > 32 or not index or not total or index < 1 or index > total
            or total > 20 or #chunk > GUILD_BANK_CHUNK_SIZE or not timestamp or timestamp <= 0
            or #source > 40 or source == "" or not validBranchChecksum(parentChecksum)
            or not validResolutions(resolutions) then return end
        local key = iRC:NormalizeName(sender) .. ":" .. kind .. ":" .. transferId
        local transfer = guildBankTransfers[key]
        if not transfer or transfer.total ~= total or transfer.checksum ~= checksum then
            transfer = { total = total, checksum = checksum, chunks = {}, received = 0, createdAt = time() }
            guildBankTransfers[key] = transfer
        end
        if not transfer.chunks[index] then
            transfer.chunks[index] = chunk
            transfer.received = transfer.received + 1
        end
        if transfer.received == total then
            local names = table.concat(transfer.chunks)
            guildBankTransfers[key] = nil
            if #names > MAX_GUILD_BANK_WIRE then return end
            local rebuilt = kind == "GUILD_BANKS_CHUNK"
                and table.concat({ "GUILD_BANKS", WIRE_VERSION, names, tostring(timestamp), source, checksum, parentChecksum, resolutions }, SEP)
                or table.concat({ "MGMT_CONFLICT", WIRE_VERSION, "BANKS", names, tostring(timestamp), source, checksum, parentChecksum, resolutions }, SEP)
            handleMessage(prefix, rebuilt, distribution, sender)
        end
        for savedKey, saved in pairs(guildBankTransfers) do
            if time() - (saved.createdAt or 0) > 30 then guildBankTransfers[savedKey] = nil end
        end
        return
    end
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
            iRC:SendGuildBankExceptions(sender)
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
        iRC:SendGuildBankExceptions(sender)
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
            local currentEnabled = settings.welcomeNewMembers == true
            if timestamp == savedTimestamp and enabled ~= currentEnabled then
                local currentChecksum = guildSettingsChecksum(currentEnabled, savedTimestamp, savedSource)
                sendManagementConflict(sender, "WELCOME", currentEnabled and "1" or "0", savedTimestamp, savedSource, currentChecksum)
                showManagementConflict("WELCOME", source, function()
                    iRC:SetNewMemberWelcomeEnabled(enabled)
                end, function()
                    iRC:SetNewMemberWelcomeEnabled(currentEnabled)
                end)
            elseif timestamp > savedTimestamp then
                settings.welcomeNewMembers = enabled
                settings.timestamp = math.floor(timestamp)
                settings.source = source
                iRC:DebugMsg(iRC:Text("GUILD_SETTINGS_RECEIVED", sender), 3)
                if iRC.RefreshOptionsIfShown then iRC:RefreshOptionsIfShown() end
            end
        end
    elseif kind == "GUILD_CONTACT_NOTE" and parts[2] == WIRE_VERSION and iRC:IsGuildMemberName(sender) then
        local connection = iRC:GetConnection()
        local senderRank = getRulesRank(sender, connection)
        local name, addedAt = tostring(parts[3] or ""), tonumber(parts[4])
        local addedBy = tostring(parts[5] or ""):gsub("[%c]", ""):sub(1, 40)
        local updatedAt, note = tonumber(parts[6]), tostring(parts[7] or "")
        local fullName = iRC:ResolveGuildMemberFullName(name)
        local now = GetServerTime and GetServerTime() or time()
        if senderRank == 0 and fullName == name and addedAt and addedAt > 0 and addedAt <= now + 300
            and updatedAt and updatedAt >= addedAt and updatedAt <= now + 300 and addedBy ~= ""
            and #note <= 80 and not note:find("[%c]") then
            connection.guildContactDetails = connection.guildContactDetails or {}
            local current = connection.guildContactDetails[name]
            if not current or updatedAt > math.floor(tonumber(current.updatedAt) or 0) then
                connection.guildContactDetails[name] = { addedAt = math.floor(addedAt), addedBy = addedBy,
                    updatedAt = math.floor(updatedAt), note = note }
                if iRC.RefreshOptionsIfShown then iRC:RefreshOptionsIfShown() end
            end
        end
    elseif kind == "GUILD_BANK_NOTE" and parts[2] == WIRE_VERSION and iRC:IsGuildMemberName(sender) then
        local connection = iRC:GetConnection()
        local senderRank = getRulesRank(sender, connection)
        local name = tostring(parts[3] or "")
        local addedAt = tonumber(parts[4])
        local addedBy = tostring(parts[5] or ""):gsub("[%c]", ""):sub(1, 40)
        local updatedAt = tonumber(parts[6])
        local note = tostring(parts[7] or "")
        local fullName = iRC:ResolveGuildMemberFullName(name)
        local now = GetServerTime and GetServerTime() or time()
        if senderRank and senderRank <= 1 and fullName == name and addedAt and addedAt > 0 and addedAt <= now + 300
            and updatedAt and updatedAt >= addedAt and updatedAt <= now + 300 and addedBy ~= ""
            and #note <= 80 and not note:find("[%c]") then
            local exceptions = connection.guildBankExceptions
            exceptions.details = exceptions.details or {}
            local current = exceptions.details[name]
            if not current or updatedAt > math.floor(tonumber(current.updatedAt) or 0) then
                exceptions.details[name] = { addedAt = math.floor(addedAt), addedBy = addedBy,
                    updatedAt = math.floor(updatedAt), note = note }
                if iRC.RefreshOptionsIfShown then iRC:RefreshOptionsIfShown() end
            end
        end
    elseif kind == "GUILD_BANKS" and parts[2] == WIRE_VERSION and iRC:IsGuildMemberName(sender) then
        local connection = iRC:GetConnection()
        local senderRank = getRulesRank(sender, connection)
        local names = tostring(parts[3] or "")
        local timestamp = tonumber(parts[4])
        local source = tostring(parts[5] or ""):gsub("[%c]", ""):sub(1, 40)
        local checksum = tostring(parts[6] or ""):lower()
        local parentChecksum = tostring(parts[7] or "root"):lower()
        local resolutions = tostring(parts[8] or ""):lower()
        local sourceRank = getRulesRank(source, connection)
        local now = GetServerTime and GetServerTime() or time()
        if senderRank and senderRank <= 1 and #names <= MAX_GUILD_BANK_WIRE and timestamp and timestamp > 0 and timestamp <= now + 300
            and source ~= "" and sourceRank ~= nil and sourceRank <= 1
            and validBranchChecksum(parentChecksum) and validResolutions(resolutions)
            and checksum == guildBanksChecksum(names, timestamp, source) then
            local members, valid, count = {}, true, 0
            for name in names:gmatch("[^,]+") do
                local fullName = iRC:ResolveGuildMemberFullName(name)
                if not fullName or fullName ~= name then valid = false; break end
                if not members[fullName] then count = count + 1 end
                if count > MAX_GUILD_BANKS then valid = false; break end
                members[fullName] = true
            end
            local exceptions = connection.guildBankExceptions
            local savedTimestamp = math.floor(tonumber(exceptions.timestamp) or 0)
            local currentNames = guildBanksWire(exceptions.members)
            local currentChecksum = tostring(exceptions.checksum or "root"):lower()
            local incomingResolvesCurrent = resolutionContains(resolutions, currentChecksum)
            local incomingIsChild = parentChecksum == currentChecksum
            local incomingIsAncestor = tostring(exceptions.parentChecksum or "root"):lower() == checksum
            local function applyIncoming()
                local previousDetails = exceptions.details or {}
                local details = {}
                for name in pairs(members) do
                    details[name] = previousDetails[name] or {
                        addedAt = math.floor(timestamp), addedBy = source,
                        updatedAt = math.floor(timestamp), note = "",
                    }
                end
                exceptions.members = members
                exceptions.details = details
                exceptions.timestamp = math.floor(timestamp)
                exceptions.source = source
                exceptions.checksum = checksum
                exceptions.parentChecksum = parentChecksum
                exceptions.resolutions = resolutions
                if incomingResolvesCurrent and iRC.PendingManagementConflicts then
                    iRC.PendingManagementConflicts.BANKS = nil
                end
                iRC:DebugMsg(iRC:Text("GUILD_BANKS_RECEIVED", sender), 3)
                if iRC.RefreshOptionsIfShown then iRC:RefreshOptionsIfShown() end
            end
            if valid and checksum == currentChecksum then
                return
            elseif valid and timestamp >= savedTimestamp and (incomingResolvesCurrent or incomingIsChild) then
                applyIncoming()
            elseif valid and incomingIsAncestor then
                return
            elseif valid then
                local pair = resolvedPair(currentChecksum, checksum)
                local merged = mergeGuildBankNames(currentNames, names)
                local conflictId = pair
                local isNewConflict = showManagementConflict("BANKS", source,
                    function() iRC:SetGuildBankExceptions(names, pair) end,
                    function() iRC:SetGuildBankExceptions(currentNames, pair) end,
                    function() iRC:SetGuildBankExceptions(merged, pair) end,
                    conflictId, currentNames, names, merged)
                if isNewConflict then
                    sendManagementConflict(sender, "BANKS", currentNames, savedTimestamp,
                        tostring(exceptions.source or ""), currentChecksum,
                        tostring(exceptions.parentChecksum or "root"), tostring(exceptions.resolutions or ""))
                end
            end
        end
    elseif kind == "MGMT_CONFLICT" and parts[2] == WIRE_VERSION and iRC:IsGuildMemberName(sender) then
        local senderRank = getRulesRank(sender, iRC:GetConnection())
        local settingKind, value = parts[3], tostring(parts[4] or "")
        local timestamp, source = tonumber(parts[5]), tostring(parts[6] or ""):gsub("[%c]", ""):sub(1, 80)
        local checksum = tostring(parts[7] or ""):lower()
        local now = GetServerTime and GetServerTime() or time()
        if senderRank and senderRank <= 1 and timestamp and timestamp > 0 and timestamp <= now + 300 and source ~= "" then
            local connection = iRC:GetConnection()
            if settingKind == "WELCOME" and (value == "0" or value == "1")
                and checksum == guildSettingsChecksum(value == "1", timestamp, source) then
                local settings, incoming = connection.guildNotifications, value == "1"
                local current = settings.welcomeNewMembers == true
                if timestamp == math.floor(tonumber(settings.timestamp) or 0) and incoming ~= current then
                    showManagementConflict("WELCOME", source, function()
                        iRC:SetNewMemberWelcomeEnabled(incoming)
                    end, function() iRC:SetNewMemberWelcomeEnabled(current) end)
                end
            elseif settingKind == "BANKS" and #value <= MAX_GUILD_BANK_WIRE
                and checksum == guildBanksChecksum(value, timestamp, source) then
                local parentChecksum = tostring(parts[8] or "root"):lower()
                local resolutions = tostring(parts[9] or ""):lower()
                local members, valid, count = {}, true, 0
                for name in value:gmatch("[^,]+") do
                    local fullName = iRC:ResolveGuildMemberFullName(name)
                    if not fullName or fullName ~= name then valid = false; break end
                    if not members[fullName] then count = count + 1 end
                    if count > MAX_GUILD_BANKS then valid = false; break end
                    members[fullName] = true
                end
                local exceptions = connection.guildBankExceptions
                local currentNames = guildBanksWire(exceptions.members)
                local currentChecksum = tostring(exceptions.checksum or "root"):lower()
                local incomingAlreadyResolved = resolutionContains(exceptions.resolutions, checksum)
                    or tostring(exceptions.parentChecksum or "root"):lower() == checksum
                if valid and validBranchChecksum(parentChecksum) and validResolutions(resolutions)
                    and checksum ~= currentChecksum and not incomingAlreadyResolved then
                    local pair = resolvedPair(currentChecksum, checksum)
                    local merged = mergeGuildBankNames(currentNames, value)
                    showManagementConflict("BANKS", source,
                        function() iRC:SetGuildBankExceptions(value, pair) end,
                        function() iRC:SetGuildBankExceptions(currentNames, pair) end,
                        function() iRC:SetGuildBankExceptions(merged, pair) end,
                        pair, currentNames, value, merged)
                end
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
            guildContacts = tostring(parts[13] or ""):sub(1, 140),
        }
        local incomingContactCount = 0
        for contact in incomingRules.guildContacts:gmatch("[^,]+") do
            if contact:gsub("%s+", "") ~= "" then incomingContactCount = incomingContactCount + 1 end
        end
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
        if connection and senderIsAuthority and incomingContactCount <= 5 and validTimestamp and incomingTimestamp <= time() + 300
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
            iRC:SendGuildBankExceptions()
        end)
        if C_Timer and C_Timer.NewTicker then
            C_Timer.NewTicker(60, function()
                iRC:SendGuildActivation()
                iRC:RequestGuildActivation()
                iRC:SendHello()
                iRC:SendConnectionRules()
                iRC:SendGuildManagementSettings()
                iRC:SendGuildBankExceptions()
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
            iRC:SendGuildBankExceptions()
        end)
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, distribution, sender = ...
        handleMessage(prefix, message, distribution, sender)
    end
end)
