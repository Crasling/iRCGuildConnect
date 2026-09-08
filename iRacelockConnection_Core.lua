local addonName, private = ...
local iRC = LibStub("AceAddon-3.0"):NewAddon("iRC")
private.iRC = iRC

iRC.Name = addonName or "iRacelockConnection"
iRC.DisplayName = "iRacelockConnection"
iRC.Version = "0.2.13"
iRC.IconPath = "Interface\\AddOns\\iRacelockConnection\\Images\\Logo_iRC"
-- Dedicated iRC prefix for guild connection traffic.
iRC.Prefix = "iRCConnV1"
-- Testing-only controls are restricted to these exact character/realm pairs.
iRC.TestAdminNames = {
    "Crasling-Soulseeker",
    "Crasjin-Soulseeker",
    "Crasblight-Soulseeker",
}
iRC.Frame = CreateFrame("Frame")
iRC.GameVersion, iRC.GameBuild, iRC.GameBuildDate, iRC.GameTocVersion = GetBuildInfo()
iRC.Colors = {
    iRC = "|cffff9716",
    White = "|cFFFFFFFF",
    Red = "|cFFFF0000",
    Green = "|cFF00FF00",
    Yellow = "|cFFFFFF00",
    Orange = "|cFFFFA500",
    Gray = "|cFF808080",
    Reset = "|r",
}
iRC.ColorValues = {
    Orange = { 1, 0.59, 0.09 },
    Green = { 0, 1, 0 },
    Yellow = { 1, 1, 0 },
    Gray = { 0.50, 0.50, 0.50 },
}

local DEFAULT_SETTINGS = {
    mainWindowScale = 1,
    shareGlobalRaceGrid = true,
    debugMode = false,
    testGuildMasterOverride = false,
    suppressPresenceWarnings = false,
    showOfficerSettingsForTesting = false,
}

iRC.DefaultConnectionRules = {
    guildRace = "",
    nativeTongueOnly = false,
    selfFoundOnly = false,
    level60GuildFound = false,
    allowLevel60WithoutSelfFound = false,
    sameRaceGroupsOnly = false,
    sameRaceMinimumLevel = 1,
    allowLevel60MixedRaceGroups = false,
    guildGroupsOnly = false,
    guildGroupsMinimumLevel = 1,
    guildContacts = "",
}

iRC.GuildRaceOrder = { "HUMAN", "DWARF", "NIGHTELF", "GNOME", "ORC", "SCOURGE", "TAUREN", "TROLL" }
iRC.GuildRaceTBCOrder = { "DRAENEI", "BLOODELF" }
local GuildRaceLookup = {}
for _, race in ipairs(iRC.GuildRaceOrder) do GuildRaceLookup[race] = true end
for _, race in ipairs(iRC.GuildRaceTBCOrder) do GuildRaceLookup[race] = true end

iRC.LDBroker = LibStub and LibStub("LibDataBroker-1.1", true)
iRC.LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)

local getMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
if getMetadata then
    iRC.Version = getMetadata(iRC.Name, "Version") or iRC.Version
end

function iRC:Print(message)
    print(self.Colors.iRC .. "[iRC]: " .. self.Colors.Reset .. tostring(message))
end

function iRC:DebugMsg(message, level)
    if not self:GetSettings().debugMode then return end
    local L = self.L or {}
    local prefix = level == 3 and L.DEBUG_INFO or (level == 2 and L.DEBUG_WARNING or L.DEBUG_ERROR)
    print((prefix or "") .. tostring(message) .. (L.DEBUG_RESET or ""))
end

function iRC:Text(key, ...)
    local value = self.L and self.L[key] or key
    if select("#", ...) > 0 then return string.format(value, ...) end
    return value
end

function iRC:GetDisplayVersion()
    return self.Version
end

local newestVersionSeen

local function versionParts(version)
    local parts = {}
    for value in tostring(version or ""):gmatch("%d+") do
        parts[#parts + 1] = tonumber(value) or 0
        if #parts == 3 then break end
    end
    return #parts == 3 and parts or nil
end

local function isNewerVersion(candidate, current)
    local candidateParts, currentParts = versionParts(candidate), versionParts(current)
    if not candidateParts or not currentParts then return false end
    for index = 1, 3 do
        if candidateParts[index] ~= currentParts[index] then
            return candidateParts[index] > currentParts[index]
        end
    end
    return false
end

function iRC:CheckForNewVersion(version)
    if not isNewerVersion(version, self.Version) then return false end
    if newestVersionSeen and not isNewerVersion(version, newestVersionSeen) then return false end
    newestVersionSeen = version
    self:Print(self.Colors.Yellow .. self:Text("NEW_VERSION_AVAILABLE", version) .. self.Colors.Reset)
    return true
end

function iRC:PrintLoaded()
    print(self:Text("ADDON_PREFIX") .. self:Text("LOADED", self.DisplayName, self:GetDisplayVersion()))
end

function iRC:CloseWindowsExcept(keptFrame)
    local windows = {
        self.SettingsFrame,
        self.MainUI and self.MainUI.frame,
        self.ConnectionDashboard and self.ConnectionDashboard.frame,
    }
    for _, window in ipairs(windows) do
        if window and window ~= keptFrame and window.IsShown and window:IsShown() then window:Hide() end
    end
end

function iRC:CloseAllWindows()
    self:CloseWindowsExcept(nil)
end

function iRC:NormalizeName(name)
    if type(name) ~= "string" or name == "" then return "" end
    return string.lower((name:match("^([^-]+)") or name))
end

function iRC:SupportsTBCPlayableRaces()
    return (tonumber(self.GameTocVersion) or 0) >= 20000
end

function iRC:GetSelfFoundState()
    if not UnitBuff then return false end
    for index = 1, 40 do
        local auraName, _, _, _, _, _, _, _, _, spellId = UnitBuff("player", index)
        if not auraName then break end
        if spellId == 431567 then return true end
    end
    return false
end

function iRC:GetSelfFoundHistory()
    iRCCharDB = iRCCharDB or {}
    iRCCharDB.selfFoundHistory = iRCCharDB.selfFoundHistory or {}
    return iRCCharDB.selfFoundHistory
end

function iRC:RecordSelfFoundState()
    local history = self:GetSelfFoundHistory()
    local now, level = time(), UnitLevel("player") or 1
    local active = self:GetSelfFoundState()
    history.firstObservedAt = history.firstObservedAt or now
    history.firstObservedLevel = history.firstObservedLevel or level
    history.lastObservedAt = now
    history.lastObservedLevel = level
    history.currentlyActive = active and true or false

    if active then
        -- Self-Found cannot be restored after it is genuinely removed.  An
        -- active aura therefore proves an older Broken record was a transient
        -- load-screen read and can safely be repaired.
        history.firstEndedAt = nil
        history.firstEndedLevel = nil
        history.endedWithLevel60Exception = nil
        history.pendingEndAt = nil
        history.firstSelfFoundAt = history.firstSelfFoundAt or now
        history.firstSelfFoundLevel = history.firstSelfFoundLevel or level
        history.lastSelfFoundAt = now
    elseif history.firstSelfFoundAt and not history.firstEndedAt and self.SelfFoundAuraReady and not history.pendingEndAt then
        -- UnitBuff can briefly return an incomplete aura list while entering
        -- the world.  Require a delayed, second absent reading before the
        -- irreversible history flag is written.
        history.pendingEndAt = now
        if C_Timer and C_Timer.After then
            C_Timer.After(3, function() iRC:ConfirmSelfFoundEnded(now) end)
        end
    end
    return history
end

function iRC:ConfirmSelfFoundEnded(expectedAt)
    local history = self:GetSelfFoundHistory()
    if history.pendingEndAt ~= expectedAt then return end
    history.pendingEndAt = nil
    if not self.SelfFoundAuraReady or self:GetSelfFoundState() then return end
    if history.firstSelfFoundAt and not history.firstEndedAt then
        local now, level = time(), UnitLevel("player") or 1
        local rules = self:GetConnectionRules()
        local allowedAtMaxLevel = level >= 60 and rules and (rules.level60GuildFound or rules.allowLevel60WithoutSelfFound)
        history.firstEndedAt = now
        history.firstEndedLevel = level
        history.endedWithLevel60Exception = allowedAtMaxLevel and true or false
    end
end

function iRC:GetSelfFoundEvidence()
    local history = self:RecordSelfFoundState()
    local active = history.currentlyActive and true or false
    local evidence = {
        active = active,
        firstObservedAt = history.firstObservedAt,
        firstObservedLevel = history.firstObservedLevel,
        firstSelfFoundAt = history.firstSelfFoundAt,
        firstSelfFoundLevel = history.firstSelfFoundLevel,
        endedAt = history.firstEndedAt,
        endedAtLevel = history.firstEndedLevel,
        endedWithLevel60Exception = history.endedWithLevel60Exception and true or false,
    }
    if history.firstEndedAt and not history.endedWithLevel60Exception then
        evidence.status = "BROKEN"
    elseif history.firstSelfFoundAt and history.firstSelfFoundLevel == 1 then
        evidence.status = active and "VERIFIED" or "LEVEL_60_EXCEPTION"
    elseif history.firstSelfFoundAt then
        evidence.status = active and "TRACKED" or "LEVEL_60_EXCEPTION"
    else
        evidence.status = "UNVERIFIED"
    end
    return evidence
end

function iRC:GetPlayerName()
    if GetUnitName then return GetUnitName("player", true) or UnitName("player") end
    return UnitName("player")
end

function iRC:GetGuildKey()
    local guildName = GetGuildInfo and GetGuildInfo("player")
    if type(guildName) ~= "string" or guildName == "" then return nil end
    local realmName = GetRealmName and GetRealmName() or ""
    return string.lower(guildName .. "@" .. realmName)
end

function iRC:IsInGuildConnection()
    return self:GetGuildKey() ~= nil
end

function iRC:GetSettings()
    iRCDB = iRCDB or {}
    iRCDB.settings = iRCDB.settings or {}
    for key, value in pairs(DEFAULT_SETTINGS) do
        if iRCDB.settings[key] == nil then
            iRCDB.settings[key] = value
        end
    end
    -- Public guild discovery is a core connection feature, not an optional
    -- preference. Migrate previously disabled profiles immediately.
    iRCDB.settings.shareGlobalRaceGrid = true
    iRCDB.settings.minimapButton = iRCDB.settings.minimapButton or {}
    if iRCDB.settings.minimapButton.hide == nil then
        iRCDB.settings.minimapButton.hide = iRCDB.settings.showMinimapButton == false
    end
    if iRCDB.settings.minimapButton.minimapPos == nil then
        iRCDB.settings.minimapButton.minimapPos = -30
    end
    return iRCDB.settings
end

local function decodeRulesTimestamp(value)
    value = tostring(value or ""):lower()
    if value == "" or #value > 12 or not value:match("^[0-9a-f]+$") then return 0 end
    return tonumber(value, 16) or 0
end

function iRC:StampConnectionRules(connection)
    if not self:IsGuildMaster() then return false end
    connection = connection or self:GetConnection()
    if not connection then return false end
    local stamp = math.max(time(), decodeRulesTimestamp(connection.rulesTimestampHex) + 1)
    connection.rulesTimestampHex = string.format("%x", stamp)
    connection.rulesTimestampSource = self:GetPlayerName()
    return true
end

function iRC:EnsureConnectionRulesTimestamp(connection)
    connection = connection or self:GetConnection()
    if not connection then return "0", "" end
    if (not connection.rulesTimestampHex or connection.rulesTimestampHex == "") and self:IsGuildMaster() then
        self:StampConnectionRules(connection)
    end
    return connection.rulesTimestampHex or "0", connection.rulesTimestampSource or ""
end

function iRC:GetConnection()
    local key = self:GetGuildKey()
    -- Dropdown initialization can read rules before ADDON_LOADED restores the DB.
    -- Let callers use defaults until then, without creating early saved state.
    if not key or not iRCDB then return nil end
    iRCDB.connections = iRCDB.connections or {}
    local connection = iRCDB.connections[key]
    if not connection then
        connection = { key = key, guildName = GetGuildInfo("player"), rulesVersion = 1, active = false, members = {} }
        iRCDB.connections[key] = connection
    end
    if connection.active == nil then connection.active = false end
    connection.members = connection.members or {}
    connection.rules = connection.rules or {}
    for key, value in pairs(self.DefaultConnectionRules) do
        if connection.rules[key] == nil then connection.rules[key] = value end
    end
    if connection.rules.guildRace == "" and self:IsGuildMaster() then
        local _, raceFile = UnitRace("player")
        connection.rules.guildRace = self:NormalizeGuildRace(raceFile)
        self:StampConnectionRules(connection)
    end
    return connection
end

function iRC:IsGuildAdmin()
    if self:IsGuildMaster() then return true end
    if not GetGuildInfo then return false end
    local _, _, rankIndex = GetGuildInfo("player")
    return type(rankIndex) == "number" and rankIndex <= 1
end

function iRC:IsGuildMaster()
    if self:IsTestGuildMaster() or self:IsTestAdminGuildMaster() then return true end
    if not GetGuildInfo then return false end
    local _, _, rankIndex = GetGuildInfo("player")
    return rankIndex == 0
end

function iRC:IsTestGuildMasterName(name)
    if type(name) ~= "string" or name == "" then return false end

    local configuredName = self.TestGuildMasterName
    if type(configuredName) ~= "string" or configuredName == "" then return false end
    if string.lower(name) == string.lower(configuredName) then return true end

    -- The local player name can omit the realm. Only accept that short form when
    -- it resolves to the exact configured realm, never just a matching name.
    local testName, testRealm = configuredName:match("^(.+)%-(.+)$")
    if not testName or name:find("-", 1, true) or string.lower(name) ~= string.lower(testName) then
        return false
    end

    return GetRealmName and string.lower(GetRealmName()) == string.lower(testRealm) or false
end

function iRC:IsTestAdminName(name)
    if type(name) ~= "string" or name == "" then return false end
    local configuredNames = self.TestAdminNames or {}
    -- Retained as a test harness override; production uses TestAdminNames.
    if type(self.TestAdminName) == "string" and self.TestAdminName ~= "" then
        configuredNames = { self.TestAdminName }
    end
    for _, configuredName in ipairs(configuredNames) do
        if type(configuredName) == "string" and configuredName ~= "" then
            if string.lower(name) == string.lower(configuredName) then return true end
            local testName, testRealm = configuredName:match("^(.+)%-(.+)$")
            if testName and not name:find("-", 1, true) and string.lower(name) == string.lower(testName)
                and GetRealmName and string.lower(GetRealmName()) == string.lower(testRealm) then return true end
        end
    end
    return false
end

function iRC:IsTestGuildMaster()
    return self:IsTestGuildMasterName(self:GetPlayerName())
end

function iRC:IsTestAdmin()
    return self:IsTestAdminName(self:GetPlayerName())
end

function iRC:IsTestAdminGuildMaster()
    return self:IsTestAdmin() and self:GetSettings().testGuildMasterOverride == true
end

function iRC:SuppressesPresenceWarnings()
    return self:IsTestAdmin() and self:GetSettings().suppressPresenceWarnings == true
end

function iRC:ActivateGuildForTesting()
    if not self:IsTestAdmin() then return false end
    self:GetSettings().testGuildMasterOverride = true
    return self:SetGuildConnectionActive(true)
end

function iRC:IsGuildMasterName(name)
    if self:IsTestGuildMasterName(name) or self:IsTestAdminName(name) then return true end
    if type(name) ~= "string" or not GetNumGuildMembers or not GetGuildRosterInfo then return false end
    for index = 1, GetNumGuildMembers(true) do
        local memberName, _, rankIndex = GetGuildRosterInfo(index)
        if self:NormalizeName(memberName) == self:NormalizeName(name) then return rankIndex == 0 end
    end
    return false
end

function iRC:IsGuildMemberName(name)
    if type(name) ~= "string" or not GetNumGuildMembers or not GetGuildRosterInfo then return false end
    for index = 1, GetNumGuildMembers(true) do
        local memberName = GetGuildRosterInfo(index)
        if self:NormalizeName(memberName) == self:NormalizeName(name) then return true end
    end
    return false
end

function iRC:GetGuildFoundTradeStatus(name)
    if type(name) ~= "string" or name == "" then return false, "Choose a guild member first." end
    if not self:IsGuildMemberName(name) then
        return false, name .. " is not in your guild."
    end

    local profile = self:FindConnectionProfile(name)
    local verification = self.GetMemberVerification and self:GetMemberVerification(name, true, profile) or nil
    if not profile or not verification or verification.state ~= "verified" then
        return false, name .. " does not have a current iRC response."
    end

    if self.RaceLockedSync then
        local ownVerified, ownClean = self.RaceLockedSync:GetLocalRawStatus()
        local own = self.RaceLockedSync:GetStatus(self:GetPlayerName())
        if own then
            if own.verified ~= nil then ownVerified = own.verified end
            if own.clean ~= nil then ownClean = own.clean end
        end
        if not ownVerified or not ownClean then return false, self:Text("RL_LOCAL_INELIGIBLE") end
        local status = self.RaceLockedSync:GetStatus(name)
        if status and status.lastSeen then
            if status.verified == true and status.clean == true then return true end
            return false, self:Text("RL_MEMBER_INELIGIBLE", name)
        end
    end

    local evidence = profile.selfFoundEvidence or nil
    local status = evidence and evidence.status or "UNVERIFIED"
    if status == "VERIFIED" or status == "LEVEL_60_EXCEPTION" then return true end
    return false, name .. " does not have verified Self-Found history (" .. string.lower(status) .. ")."
end

function iRC:IsGuildOnlyGroup()
    if not self:IsGuildConnectionActive() then return false end
    local inRaid = IsInRaid and IsInRaid()
    local memberCount = inRaid and (GetNumGroupMembers and GetNumGroupMembers() or 0) or (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0)
    if memberCount < 1 then return false end
    for index = 1, memberCount do
        local unit = inRaid and "raid" .. index or "party" .. index
        if (not UnitIsUnit or not UnitIsUnit(unit, "player")) and not self:IsGuildMemberName(UnitName(unit)) then return false end
    end
    return true
end

function iRC:NormalizeGuildRace(race)
    local token = tostring(race or ""):upper():gsub("%s+", "")
    if token == "UNDEAD" then token = "SCOURGE" end
    return GuildRaceLookup[token] and token or ""
end

function iRC:GetAvailableGuildRaces()
    local races = {}
    for _, race in ipairs(self.GuildRaceOrder) do races[#races + 1] = race end
    if self:SupportsTBCPlayableRaces() then
        for _, race in ipairs(self.GuildRaceTBCOrder) do races[#races + 1] = race end
    end
    return races
end

function iRC:GetGuildRace()
    return self:NormalizeGuildRace(self:GetConnectionRules().guildRace)
end

function iRC:SetGuildRace(race)
    if not self:IsGuildMaster() then return false end
    local normalizedRace = self:NormalizeGuildRace(race)
    if normalizedRace == "" then return false end
    local connection = self:GetConnection()
    if not connection then return false end
    connection.rules.guildRace = normalizedRace
    self:StampConnectionRules(connection)
    if self.SendConnectionRules then self:SendConnectionRules() end
    if self.RefreshOptionsIfShown then self:RefreshOptionsIfShown() end
    return true
end

function iRC:IsGuildConnectionActive()
    local connection = self:GetConnection()
    return connection and connection.active == true or false
end

function iRC:SetGuildConnectionActive(active, receivedFromGuild)
    if not receivedFromGuild and not self:IsGuildMaster() then return false end
    local connection = self:GetConnection()
    if not connection then return false end
    active = active and true or false
    if connection.active == active then return false end
    connection.active = active
    if active and not receivedFromGuild and self:GetGuildRace() == "" then
        local _, raceFile = UnitRace("player")
        connection.rules.guildRace = self:NormalizeGuildRace(raceFile)
        self:StampConnectionRules(connection)
    end
    if not active then
        if self.ResetPresenceNotificationChecks then self:ResetPresenceNotificationChecks() end
        connection.attentionSince = {}
        connection.newMemberChecks = {}
    end
    if not receivedFromGuild and self.SendGuildActivation then self:SendGuildActivation() end
    if active and not receivedFromGuild then
        if self.SendConnectionRules then self:SendConnectionRules() end
        if self.SendHello then self:SendHello() end
        if self.Compatibility and self.Compatibility.BroadcastAll then self.Compatibility:BroadcastAll() end
    end
    if active and self.RaceLockedSync then self.RaceLockedSync:Broadcast() end
    if active and self.RefreshGuildRoster then self:RefreshGuildRoster() end
    if self.Enforcement then self.Enforcement:Refresh() end
    if self.RefreshOptionsIfShown then self:RefreshOptionsIfShown() end
    return true
end

function iRC:GetConnectionRules()
    local connection = self:GetConnection()
    return connection and connection.rules or self.DefaultConnectionRules
end

function iRC:MarkGuildFoundRequired(connection)
    connection = connection or self:GetConnection()
    local guildKey = self:GetGuildKey()
    if not connection or not guildKey then return false end
    connection.guildFoundEverActive = true
    iRCCharDB = iRCCharDB or {}
    iRCCharDB.guildFoundGuilds = iRCCharDB.guildFoundGuilds or {}
    iRCCharDB.guildFoundGuilds[guildKey] = true
    return true
end

function iRC:IsGuildFoundRequired()
    local connection = self:GetConnection()
    local guildKey = self:GetGuildKey()
    if not connection or not guildKey then return false end
    local rules = connection.rules or self.DefaultConnectionRules
    if rules.selfFoundOnly == true and rules.level60GuildFound == true then
        self:MarkGuildFoundRequired(connection)
        return true
    end
    return connection.guildFoundEverActive == true
        or (iRCCharDB and iRCCharDB.guildFoundGuilds and iRCCharDB.guildFoundGuilds[guildKey] == true)
end

function iRC:SetConnectionRule(key, value)
    if not self:IsGuildMaster() or self.DefaultConnectionRules[key] == nil then return false end
    local connection = self:GetConnection()
    if not connection then return false end
    connection.rules[key] = value and true or false
    if value and key == "level60GuildFound" then
        connection.rules.allowLevel60WithoutSelfFound = false
    elseif value and key == "allowLevel60WithoutSelfFound" then
        connection.rules.level60GuildFound = false
    end
    if connection.rules.selfFoundOnly and connection.rules.level60GuildFound then self:MarkGuildFoundRequired(connection) end
    self:StampConnectionRules(connection)
    if self.SendConnectionRules then self:SendConnectionRules() end
    if self.RefreshOptionsIfShown then self:RefreshOptionsIfShown() end
    if self.Enforcement then self.Enforcement:Refresh() end
    return true
end

function iRC:SetSameRaceMinimumLevel(value)
    if not self:IsGuildMaster() then return false end
    local connection = self:GetConnection()
    if not connection then return false end
    connection.rules.sameRaceMinimumLevel = math.max(1, math.min(60, math.floor(tonumber(value) or 1)))
    self:StampConnectionRules(connection)
    if self.SendConnectionRules then self:SendConnectionRules() end
    if self.RefreshOptionsIfShown then self:RefreshOptionsIfShown() end
    if self.Enforcement then self.Enforcement:Refresh() end
    return true
end

function iRC:SetGuildGroupsMinimumLevel(value)
    if not self:IsGuildMaster() then return false end
    local connection = self:GetConnection()
    if not connection then return false end
    connection.rules.guildGroupsMinimumLevel = math.max(1, math.min(60, math.floor(tonumber(value) or 1)))
    self:StampConnectionRules(connection)
    if self.SendConnectionRules then self:SendConnectionRules() end
    if self.RefreshOptionsIfShown then self:RefreshOptionsIfShown() end
    if self.Enforcement then self.Enforcement:Refresh() end
    return true
end

function iRC:SetGuildContacts(value)
    if not self:IsGuildMaster() then return false end
    local connection = self:GetConnection()
    if not connection then return false end
    value = tostring(value or ""):gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s%s+", " ")
    connection.rules.guildContacts = value:sub(1, 60)
    self:StampConnectionRules(connection)
    if self.SendConnectionRules then self:SendConnectionRules() end
    if self.RefreshOptionsIfShown then self:RefreshOptionsIfShown() end
    return true
end

iRC.Frame:RegisterEvent("ADDON_LOADED")
iRC.Frame:RegisterEvent("PLAYER_LOGIN")
iRC.Frame:RegisterEvent("PLAYER_REGEN_DISABLED")
iRC.Frame:SetScript("OnEvent", function(_, event, loadedName)
    if event == "ADDON_LOADED" then
        if loadedName ~= iRC.Name then return end
        iRCDB = iRCDB or {}
        iRCDB.connections = iRCDB.connections or {}
        iRC:GetSettings()
        iRCCharDB = iRCCharDB or {}
    elseif event == "PLAYER_LOGIN" then
        iRC:DebugMsg(iRC:Text("DEBUG_MODE"), 3)
        iRC:PrintLoaded()
    elseif event == "PLAYER_REGEN_DISABLED" then
        iRC:CloseAllWindows()
    end
end)
