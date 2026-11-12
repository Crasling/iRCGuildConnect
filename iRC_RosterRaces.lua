local _, private = ...
local iRC = private.iRC
local Races = {}
iRC.RosterRaces = Races

local BATCH_SIZE, SCAN_LIMIT, RETRY_DELAY = 8, 32, 60
local connection, pending, order, cursor, remaining = nil, {}, {}, 1, 0
local scheduled, generation, lastUnitScan = false, 0, -30
local nativeMembers, nativeDirty = nil, true
local schedule

local function raceToken(value)
    if iRC:IsSecretValue(value) or type(value) ~= "string" then return nil end
    local race = iRC:NormalizeGuildRace(value)
    return race ~= "" and race or nil
end

local function playerGuid(value)
    return not iRC:IsSecretValue(value) and type(value) == "string" and #value <= 128
        and value:match("^Player%-%w[%w%-]*$") ~= nil
end

local function useConnection(current)
    if current == connection then return end
    connection, pending, order, cursor, remaining = current, {}, {}, 1, 0
    scheduled, generation, lastUnitScan = false, generation + 1, -30
    nativeMembers, nativeDirty = nil, true
end

local function savedRaces(create)
    if not connection then return nil end
    if type(connection.memberRaceCache) ~= "table" then
        if not create then return nil end
        connection.memberRaceCache = {}
    end
    return connection.memberRaceCache
end

local function remember(guid, race)
    local cache = savedRaces(true)
    if not cache or not playerGuid(guid) or not race then return end
    cache[guid] = race
    if pending[guid] then pending[guid], remaining = nil, remaining - 1 end
end

local function read(callback, ...)
    if type(callback) ~= "function" then return nil end
    local ok, value = pcall(callback, ...)
    if ok and not iRC:IsSecretValue(value) then return value end
end

local function numericId(value)
    return not iRC:IsSecretValue(value) and type(value) == "number"
        and value > 0 and value < 10000 and value % 1 == 0
end

function Races:InvalidateNativeMembers()
    nativeDirty = true
end

function Races:IsGuildClub(clubId)
    if iRC:IsSecretValue(clubId) or not C_Club then return false end
    local ownClub = read(C_Club.GetGuildClubId)
    return ownClub ~= nil and clubId == ownClub
end

function Races:NeedsNativeRefresh()
    return nativeDirty and connection ~= nil and C_Club ~= nil and C_CreatureInfo ~= nil
end

function Races:GetNativeMembers(current)
    useConnection(current)
    if not nativeDirty then return nativeMembers end
    if not connection or not C_Club or not C_CreatureInfo then return nativeMembers end
    -- Club member tables can be secret during chat lockdown. Keep the last
    -- public snapshot instead of inspecting restricted tables or IDs.
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
        and read(C_ChatInfo.InChatMessagingLockdown) ~= false then return nativeMembers end
    local clubId = read(C_Club.GetGuildClubId)
    if clubId == nil then return nativeMembers end
    local members = read(C_Club.GetClubMembers, clubId)
    if type(members) ~= "table" or #members == 0 then return nativeMembers end
    local result, races, classes, complete = { byGuid = {}, byName = {} }, {}, {}, true
    for index = 1, math.min(#members, 2000) do
        local memberId = members[index]
        local info = not iRC:IsSecretValue(memberId) and read(C_Club.GetMemberInfo, clubId, memberId) or nil
        if type(info) == "table" and playerGuid(info.guid) then
            local race, class
            if numericId(info.race) then
                if races[info.race] == nil then
                    local data = read(C_CreatureInfo.GetRaceInfo, info.race)
                    races[info.race] = type(data) == "table" and raceToken(data.clientFileString) or false
                end
                race = races[info.race] or nil
            end
            if numericId(info.classID) then
                if classes[info.classID] == nil then
                    local data = read(C_CreatureInfo.GetClassInfo, info.classID)
                    if type(data) == "table" and not iRC:IsSecretValue(data.classFile)
                        and type(data.classFile) == "string" and not iRC:IsSecretValue(data.className)
                        and type(data.className) == "string" then classes[info.classID] = data
                    else classes[info.classID] = false end
                end
                class = classes[info.classID] or nil
            end
            -- Profession IDs identify what a member has; skill ranks from this API
            -- are not reliable on Forever, so iRC never copies them into skills.
            local member = { guid = info.guid, race = race,
                classFile = class and class.classFile, className = class and class.className,
                profession1ID = numericId(info.profession1ID) and info.profession1ID or nil,
                profession2ID = numericId(info.profession2ID) and info.profession2ID or nil }
            result.byGuid[info.guid] = member
            if not iRC:IsSecretValue(info.name) and type(info.name) == "string" then
                result.byName[iRC:NormalizeName(info.name)] = member
            end
            if race then remember(info.guid, race) end
            if not race then complete = false end
        else
            complete = false
        end
    end
    nativeMembers, nativeDirty = result, not complete
    return nativeMembers
end

function Races:Reconcile(current, roster)
    useConnection(current)
    local present = {}
    for _, member in ipairs(roster) do if playerGuid(member.guid) then present[member.guid] = true end end
    for guid in pairs(pending) do
        if not present[guid] then pending[guid], remaining = nil, remaining - 1 end
    end
end

function Races:LearnProfile(current, profile)
    useConnection(current)
    if not playerGuid(profile.guid) then return end
    local native = nativeMembers and nativeMembers.byGuid[profile.guid]
    local race = native and native.race or raceToken(profile.race)
    if not race then return end
    local cache = savedRaces(false)
    local updated = not cache or cache[profile.guid] ~= race
    remember(profile.guid, race)
    if updated and iRC.RaceGrid then iRC.RaceGrid:MarkLocalReportDirty() end
end

local function changed(names)
    if #names == 0 then return end
    for _, name in ipairs(names) do iRC:InvalidateGuildMemberRow(name) end
    if iRC.RaceGrid then iRC.RaceGrid:MarkLocalReportDirty() end
    if iRC.MainUI then iRC.MainUI:RefreshIfShown() end
    if iRC.ConnectionDashboard then iRC.ConnectionDashboard:RefreshIfShown() end
    iRC:DebugMsg(string.format("Race lookup: learned %d guild member race(s); %d unresolved.", #names, remaining), 3)
end

function Races:Resolve(current, name, guid, profileRace)
    useConnection(current)
    local race = raceToken(profileRace)
    if race then remember(guid, race); return race end
    local cache = savedRaces(false)
    race = playerGuid(guid) and cache and raceToken(cache[guid]) or nil
    if race then return race end
    if connection and playerGuid(guid) and not pending[guid] and remaining < 2000 then
        -- Reuse one queue and one timer, including in very large guilds.
        pending[guid] = { name = name, nextAttempt = 0 }
        order[#order + 1], remaining = guid, remaining + 1
        schedule()
    end
    return nil
end

local function captureUnit(unit, learned)
    if not UnitGUID or not UnitRace then return end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or not playerGuid(guid) or not pending[guid] then return end
    local job = pending[guid]
    local raceOK, localized, token = pcall(UnitRace, unit)
    local race = raceOK and (raceToken(token) or raceToken(localized)) or nil
    if race then
        remember(guid, race)
        learned[#learned + 1] = job.name
    end
end

local function captureVisibleUnits(learned)
    for _, unit in ipairs({ "player", "target", "mouseover", "party1", "party2", "party3", "party4" }) do
        captureUnit(unit, learned)
    end
    if IsInRaid then
        local ok, inRaid = pcall(IsInRaid)
        if ok and not iRC:IsSecretValue(inRaid) and inRaid == true then
            for index = 1, 40 do captureUnit("raid" .. index, learned) end
        end
    end
end

function Races:ProcessPending()
    if iRC:GetConnection() ~= connection then useConnection(iRC:GetConnection()); return end
    if remaining == 0 then return end
    local now, learned, attempted = GetTime(), {}, 0
    if now - lastUnitScan >= 30 then
        lastUnitScan = now
        captureVisibleUnits(learned)
    end
    for _ = 1, math.min(SCAN_LIMIT, #order) do
        if attempted >= BATCH_SIZE then break end
        if cursor > #order then cursor = 1 end
        local guid = order[cursor]
        cursor = cursor + 1
        local job = pending[guid]
        if job and now >= job.nextAttempt then
            attempted, job.nextAttempt = attempted + 1, now + RETRY_DELAY
            local ok, _, _, localized, token = false, nil, nil, nil, nil
            if GetPlayerInfoByGUID then ok, _, _, localized, token = pcall(GetPlayerInfoByGUID, guid) end
            local race = ok and (raceToken(token) or raceToken(localized)) or nil
            if race then
                remember(guid, race)
                learned[#learned + 1] = job.name
            end
        end
    end
    if remaining == 0 then order, cursor = {}, 1
    elseif #order > math.max(64, remaining * 2) then
        local compact = {}
        for _, guid in ipairs(order) do if pending[guid] then compact[#compact + 1] = guid end end
        order, cursor = compact, 1
    end
    changed(learned)
    schedule()
end

schedule = function()
    if scheduled or remaining == 0 or not C_Timer or not C_Timer.After then return end
    scheduled = true
    local ticket = generation
    C_Timer.After(1, function()
        if ticket ~= generation then return end
        scheduled = false
        Races:ProcessPending()
    end)
end

-- Read races only for unresolved guild-member GUIDs. Nearby NPCs and other
-- players do not create cache entries or trigger any communication.
local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED",
    "UNIT_NAME_UPDATE", "GROUP_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE" }) do events:RegisterEvent(event) end
events:SetScript("OnEvent", function(_, event, unit)
    local current = iRC:GetConnection()
    if current ~= connection then useConnection(current) end
    if remaining == 0 then return end
    local learned = {}
    if event == "PLAYER_TARGET_CHANGED" then captureUnit("target", learned)
    elseif event == "UPDATE_MOUSEOVER_UNIT" then captureUnit("mouseover", learned)
    elseif event == "GROUP_ROSTER_UPDATE" then captureVisibleUnits(learned)
    elseif type(unit) == "string" and not iRC:IsSecretValue(unit) then captureUnit(unit, learned) end
    changed(learned)
end)
