local addonName = ...

local iRL = {}
_G.iRaceLocked = iRL

iRL.Name = addonName or "iRaceLocked"
iRL.DisplayName = "iRacelockConnection"
iRL.Version = "0.2.0"
iRL.IconPath = "Interface\\AddOns\\iRaceLocked\\Images\\Logo_iRC"
-- Kept separate from the RaceLocked family of prefixes (for example
-- RaceLocked, RLGuildAch, and RLRaceGridV1) so all addons can coexist.
iRL.Prefix = "iRCConnV1"
iRL.Frame = CreateFrame("Frame")
iRL.Colors = {
    iRC = "|cffff9716",
    White = "|cFFFFFFFF",
    Red = "|cFFFF0000",
    Green = "|cFF00FF00",
    Yellow = "|cFFFFFF00",
    Orange = "|cFFFFA500",
    Gray = "|cFF808080",
    Reset = "|r",
}
iRL.ColorValues = {
    Orange = { 1, 0.59, 0.09 },
    Green = { 0, 1, 0 },
    Yellow = { 1, 1, 0 },
    Gray = { 0.50, 0.50, 0.50 },
}

local DEFAULT_SETTINGS = {
    showAchievementNotifications = true,
    achievementScale = 1,
}

iRL.DefaultConnectionRules = {
    nativeTongueOnly = false,
    selfFoundOnly = false,
    allowLevel60WithoutSelfFound = false,
    sameRaceGroupsOnly = false,
}

iRL.LDBroker = LibStub and LibStub("LibDataBroker-1.1", true)
iRL.LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)

local getMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
if getMetadata then
    iRL.Version = getMetadata(iRL.Name, "Version") or iRL.Version
end

function iRL:Print(message)
    print(self.Colors.iRC .. "[iRC]: " .. self.Colors.Reset .. tostring(message))
end

function iRL:PrintLoaded()
    print(self.Colors.iRC .. "[iRC]: " .. self.DisplayName .. " " .. self.Colors.Green .. "v" .. self.Version .. self.Colors.Reset .. " Loaded.")
end

function iRL:NormalizeName(name)
    if type(name) ~= "string" or name == "" then return "" end
    return string.lower((name:match("^([^-]+)") or name))
end

function iRL:GetSelfFoundState()
    if not UnitBuff then return false end
    for index = 1, 40 do
        local auraName, _, _, _, _, _, _, _, _, spellId = UnitBuff("player", index)
        if not auraName then break end
        if spellId == 431567 then return true end
    end
    return false
end

function iRL:GetPlayerName()
    if GetUnitName then return GetUnitName("player", true) or UnitName("player") end
    return UnitName("player")
end

function iRL:GetGuildKey()
    local guildName = GetGuildInfo and GetGuildInfo("player")
    if type(guildName) ~= "string" or guildName == "" then return nil end
    local realmName = GetRealmName and GetRealmName() or ""
    return string.lower(guildName .. "@" .. realmName)
end

function iRL:IsInGuildConnection()
    return self:GetGuildKey() ~= nil
end

function iRL:GetSettings()
    iRLDB = iRLDB or {}
    iRLDB.settings = iRLDB.settings or {}
    for key, value in pairs(DEFAULT_SETTINGS) do
        if iRLDB.settings[key] == nil then
            iRLDB.settings[key] = value
        end
    end
    iRLDB.settings.minimapButton = iRLDB.settings.minimapButton or {}
    if iRLDB.settings.minimapButton.hide == nil then
        iRLDB.settings.minimapButton.hide = iRLDB.settings.showMinimapButton == false
    end
    if iRLDB.settings.minimapButton.minimapPos == nil then
        iRLDB.settings.minimapButton.minimapPos = -30
    end
    return iRLDB.settings
end

function iRL:GetConnection()
    local key = self:GetGuildKey()
    if not key then return nil end
    iRLDB.connections = iRLDB.connections or {}
    local connection = iRLDB.connections[key]
    if not connection then
        connection = { key = key, guildName = GetGuildInfo("player"), rulesVersion = 1, members = {} }
        iRLDB.connections[key] = connection
    end
    connection.members = connection.members or {}
    connection.rules = connection.rules or {}
    for key, value in pairs(self.DefaultConnectionRules) do
        if connection.rules[key] == nil then connection.rules[key] = value end
    end
    return connection
end

function iRL:IsGuildAdmin()
    local _, _, rankIndex = GetGuildInfo and GetGuildInfo("player")
    return type(rankIndex) == "number" and rankIndex <= 1
end

function iRL:IsGuildMaster()
    local _, _, rankIndex = GetGuildInfo and GetGuildInfo("player")
    return rankIndex == 0
end

function iRL:IsGuildMasterName(name)
    if type(name) ~= "string" or not GetNumGuildMembers or not GetGuildRosterInfo then return false end
    for index = 1, GetNumGuildMembers(true) do
        local memberName, _, rankIndex = GetGuildRosterInfo(index)
        if self:NormalizeName(memberName) == self:NormalizeName(name) then return rankIndex == 0 end
    end
    return false
end

function iRL:IsGuildMemberName(name)
    if type(name) ~= "string" or not GetNumGuildMembers or not GetGuildRosterInfo then return false end
    for index = 1, GetNumGuildMembers(true) do
        local memberName = GetGuildRosterInfo(index)
        if self:NormalizeName(memberName) == self:NormalizeName(name) then return true end
    end
    return false
end

function iRL:IsGuildOnlyGroup()
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

function iRL:GetConnectionRules()
    local connection = self:GetConnection()
    return connection and connection.rules or self.DefaultConnectionRules
end

function iRL:SetConnectionRule(key, value)
    if not self:IsGuildMaster() or self.DefaultConnectionRules[key] == nil then return false end
    local connection = self:GetConnection()
    if not connection then return false end
    connection.rules[key] = value and true or false
    if self.SendConnectionRules then self:SendConnectionRules() end
    if self.RefreshOptionsIfShown then self:RefreshOptionsIfShown() end
    if self.Enforcement then self.Enforcement:Refresh() end
    return true
end

iRL.Frame:RegisterEvent("ADDON_LOADED")
iRL.Frame:RegisterEvent("PLAYER_LOGIN")
iRL.Frame:SetScript("OnEvent", function(_, event, loadedName)
    if event == "ADDON_LOADED" then
        if loadedName ~= iRL.Name then return end
        iRLDB = iRLDB or {}
        iRLDB.connections = iRLDB.connections or {}
        iRL:GetSettings()
        iRLCharDB = iRLCharDB or {}
        iRLCharDB.achievements = iRLCharDB.achievements or {}
    elseif event == "PLAYER_LOGIN" then
        iRL:PrintLoaded()
    end
end)
