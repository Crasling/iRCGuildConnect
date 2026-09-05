local addonName, private = ...
local iRC = LibStub("AceAddon-3.0"):NewAddon("iRC")
private.iRC = iRC

iRC.Name = addonName or "iRacelockConnection"
iRC.DisplayName = "iRacelockConnection"
iRC.Version = "0.2.1"
iRC.IconPath = "Interface\\AddOns\\iRacelockConnection\\Images\\Logo_iRC"
-- Dedicated iRC prefix for guild connection traffic.
iRC.Prefix = "iRCConnV1"
-- Testing-only authority override. Remove this before a public release.
iRC.TestGuildMasterName = "Jujukhan-Soulseeker"
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
    showAchievementNotifications = true,
    achievementScale = 1,
    shareGlobalRaceGrid = false,
    debugMode = false,
}

iRC.DefaultConnectionRules = {
    nativeTongueOnly = false,
    selfFoundOnly = false,
    level60GuildFound = false,
    allowLevel60WithoutSelfFound = false,
    sameRaceGroupsOnly = false,
    allowLevel60MixedRaceGroups = false,
}

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

function iRC:PrintLoaded()
    print(self:Text("ADDON_PREFIX") .. self:Text("LOADED", self.DisplayName, self.Version))
end

function iRC:CloseWindowsExcept(keptFrame)
    local windows = {
        self.SettingsFrame,
        self.AchievementsUI and self.AchievementsUI.frame,
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
        history.firstSelfFoundAt = history.firstSelfFoundAt or now
        history.firstSelfFoundLevel = history.firstSelfFoundLevel or level
        history.lastSelfFoundAt = now
    elseif history.firstSelfFoundAt and not history.firstEndedAt then
        local rules = self:GetConnectionRules()
        local allowedAtMaxLevel = level >= 60 and rules and (rules.level60GuildFound or rules.allowLevel60WithoutSelfFound)
        history.firstEndedAt = now
        history.firstEndedLevel = level
        history.endedWithLevel60Exception = allowedAtMaxLevel and true or false
    end
    return history
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

function iRC:HasHardcoreAchievements()
    local isAddonLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    return isAddonLoaded and isAddonLoaded("HardcoreAchievements") and true or false
end

function iRC:GetHardcoreAchievementPoints()
    if not self:HasHardcoreAchievements() then return 0 end
    local panel = _G.AchievementPanel
    if panel and panel.TotalPoints and panel.TotalPoints.GetText then
        local value = tonumber(((panel.TotalPoints:GetText() or ""):gsub(",", "")))
        if value and value >= 0 then return value end
    end
    local globalData = _G.G or _G
    local database = globalData.HardcoreAchievementsDB or _G.HardcoreAchievementsDB
    local guid = UnitGUID and UnitGUID("player")
    local character = database and database.chars and guid and database.chars[guid]
    if type(character) ~= "table" or type(character.achievements) ~= "table" then return 0 end
    local total = 0
    for _, achievement in pairs(character.achievements) do
        if type(achievement) == "table" and achievement.completed then total = total + (tonumber(achievement.points) or 0) end
    end
    return total
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
    iRCDB.settings.minimapButton = iRCDB.settings.minimapButton or {}
    if iRCDB.settings.minimapButton.hide == nil then
        iRCDB.settings.minimapButton.hide = iRCDB.settings.showMinimapButton == false
    end
    if iRCDB.settings.minimapButton.minimapPos == nil then
        iRCDB.settings.minimapButton.minimapPos = -30
    end
    return iRCDB.settings
end

function iRC:GetConnection()
    local key = self:GetGuildKey()
    if not key then return nil end
    iRCDB.connections = iRCDB.connections or {}
    local connection = iRCDB.connections[key]
    if not connection then
        connection = { key = key, guildName = GetGuildInfo("player"), rulesVersion = 1, members = {} }
        iRCDB.connections[key] = connection
    end
    connection.members = connection.members or {}
    connection.rules = connection.rules or {}
    for key, value in pairs(self.DefaultConnectionRules) do
        if connection.rules[key] == nil then connection.rules[key] = value end
    end
    return connection
end

function iRC:IsGuildAdmin()
    if self:IsTestGuildMaster() then return true end
    local _, _, rankIndex = GetGuildInfo and GetGuildInfo("player")
    return type(rankIndex) == "number" and rankIndex <= 1
end

function iRC:IsGuildMaster()
    if self:IsTestGuildMaster() then return true end
    local _, _, rankIndex = GetGuildInfo and GetGuildInfo("player")
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

function iRC:IsTestGuildMaster()
    return self:IsTestGuildMasterName(self:GetPlayerName())
end

function iRC:IsGuildMasterName(name)
    if self:IsTestGuildMasterName(name) then return true end
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
    if profile and verification and verification.state == "verified" then
        local evidence = profile.selfFoundEvidence or nil
        local status = evidence and evidence.status or "UNVERIFIED"
        if status == "VERIFIED" or status == "LEVEL_60_EXCEPTION" then return true end
        return false, name .. " does not have verified Self-Found history (" .. string.lower(status) .. ")."
    end

    -- RaceLocked has its own verified-and-clean Guild Found roster. Treat that
    -- as a compatible source, never as an iRC profile, so both addons can run
    -- together without replacing or overwriting each other's data.
    local compatibility = self.GetCompatibilityMember and self:GetCompatibilityMember(name) or nil
    local guildFound = compatibility and compatibility.guildFound
    if guildFound and guildFound.source == "RaceLocked" and guildFound.verified and guildFound.clean
        and time() - (tonumber(guildFound.lastSeen) or 0) <= 600 then
        return true
    end
    return false, name .. " does not have a current iRC or RaceLocked Guild Found verification."
end

function iRC:IsGuildOnlyGroup()
    if not self:IsInGuildConnection() then return false end
    local inRaid = IsInRaid and IsInRaid()
    local memberCount = inRaid and (GetNumGroupMembers and GetNumGroupMembers() or 0) or (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0)
    if memberCount < 1 then return false end
    for index = 1, memberCount do
        local unit = inRaid and "raid" .. index or "party" .. index
        if (not UnitIsUnit or not UnitIsUnit(unit, "player")) and not self:IsGuildMemberName(UnitName(unit)) then return false end
    end
    return true
end

function iRC:GetConnectionRules()
    local connection = self:GetConnection()
    return connection and connection.rules or self.DefaultConnectionRules
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
    if self.SendConnectionRules then self:SendConnectionRules() end
    if self.RefreshOptionsIfShown then self:RefreshOptionsIfShown() end
    if self.Enforcement then self.Enforcement:Refresh() end
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
        iRCCharDB.achievements = iRCCharDB.achievements or {}
    elseif event == "PLAYER_LOGIN" then
        iRC:DebugMsg(iRC:Text("DEBUG_MODE"), 3)
        iRC:PrintLoaded()
    elseif event == "PLAYER_REGEN_DISABLED" then
        iRC:CloseAllWindows()
    end
end)
