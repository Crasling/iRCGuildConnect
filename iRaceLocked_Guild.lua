local iRL = _G.iRaceLocked
if not iRL then return end

local AllianceRaces = { HUMAN = true, DWARF = true, NIGHTELF = true, GNOME = true, DRAENEI = true }
local HordeRaces = { ORC = true, SCOURGE = true, TAUREN = true, TROLL = true, BLOODELF = true }

function iRL:FindConnectionProfile(name)
    local connection = self:GetConnection()
    return connection and connection.members[self:NormalizeName(name)] or nil
end

function iRL:RefreshGuildRoster()
    if SetGuildRosterShowOffline then SetGuildRosterShowOffline(true) end
    if GuildRoster then GuildRoster() end
end

local function getRaceFromGuid(guid)
    if not guid or not GetPlayerInfoByGUID then return nil end
    local _, _, localizedRace, raceFile = GetPlayerInfoByGUID(guid)
    return raceFile or localizedRace
end

function iRL:GetGuildRosterRows()
    local rows, count = {}, GetNumGuildMembers and GetNumGuildMembers(true) or 0
    local selfName = self:GetPlayerName()
    for index = 1, count do
        local name, _, rankIndex, level, className, _, _, _, online, _, classFile, _, _, _, _, _, guid = GetGuildRosterInfo(index)
        if name then
            local profile = self:FindConnectionProfile(name)
            local race = profile and profile.race or getRaceFromGuid(guid) or "Unknown"
            if self:NormalizeName(name) == self:NormalizeName(selfName) then
                profile = self:GetLocalProfile()
                race = profile.race
                guid = profile.guid
            end
            rows[#rows + 1] = {
                name = name, guid = guid or (profile and profile.guid) or "", rankIndex = rankIndex or 99,
                level = (profile and profile.level) or level or 1, class = (profile and profile.class) or classFile or className or "UNKNOWN",
                race = race, online = online and true or false, profile = profile,
                points = profile and profile.points or 0, selfFound = profile and profile.selfFound or false,
                addonVersion = profile and profile.addonVersion or nil, statistics = profile and profile.statistics or nil,
            }
        end
    end
    if #rows == 0 and self:IsInGuildConnection() then
        local profile = self:GetLocalProfile()
        rows[1] = { name = profile.name, guid = profile.guid, rankIndex = 0, level = profile.level, class = profile.class, race = profile.race, online = true, profile = profile, points = profile.points, selfFound = profile.selfFound, addonVersion = profile.addonVersion, statistics = profile.statistics }
    end
    table.sort(rows, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
    return rows
end

function iRL:GetRaceOverview()
    local groups = {}
    for _, row in ipairs(self:GetGuildRosterRows()) do
        local race = row.race or "Unknown"
        local group = groups[race]
        if not group then
            group = { race = race, faction = AllianceRaces[race] and "Alliance" or (HordeRaces[race] and "Horde" or "Unknown"), members = 0, totalLevel = 0, addonUsers = 0, selfFound = 0, classes = {} }
            groups[race] = group
        end
        group.members = group.members + 1
        group.totalLevel = group.totalLevel + (row.level or 1)
        if row.profile then group.addonUsers = group.addonUsers + 1 end
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

function iRL:GetChampions()
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

function iRL:GetLeaderboard()
    local leaders = {}
    for _, row in ipairs(self:GetGuildRosterRows()) do
        if row.profile then leaders[#leaders + 1] = row end
    end
    table.sort(leaders, function(a, b)
        if a.points ~= b.points then return a.points > b.points end
        if a.level ~= b.level then return a.level > b.level end
        return string.lower(a.name) < string.lower(b.name)
    end)
    return leaders
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(3, function() iRL:RefreshGuildRoster() end)
    elseif iRL.ConnectionDashboard then
        iRL.ConnectionDashboard:RefreshIfShown()
    end
end)
