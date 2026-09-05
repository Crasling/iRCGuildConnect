local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local Statistics = {}
iRC.Statistics = Statistics

local function getStorage()
    iRCCharDB = iRCCharDB or {}
    iRCCharDB.statistics = iRCCharDB.statistics or {}
    return iRCCharDB.statistics
end

function Statistics:Initialize()
    local statistics = getStorage()
    local guid = UnitGUID("player") or ""
    if statistics.characterGuid ~= guid then
        statistics.characterGuid = guid
        statistics.enemiesSlain = 0
        statistics.jumps = 0
        statistics.bosses = {}
    end
    statistics.enemiesSlain = tonumber(statistics.enemiesSlain) or 0
    statistics.jumps = tonumber(statistics.jumps) or 0
    statistics.bosses = statistics.bosses or {}
    return statistics
end

function Statistics:GetSnapshot()
    local statistics = self:Initialize()
    local bosses = 0
    for _ in pairs(statistics.bosses) do bosses = bosses + 1 end
    return {
        enemiesSlain = statistics.enemiesSlain,
        dungeonBosses = bosses,
        jumps = statistics.jumps,
    }
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PARTY_KILL")
frame:RegisterEvent("BOSS_KILL")
pcall(frame.RegisterEvent, frame, "PLAYER_JUMPED")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        Statistics:Initialize()
    elseif event == "PARTY_KILL" then
        local statistics = Statistics:Initialize()
        statistics.enemiesSlain = statistics.enemiesSlain + 1
    elseif event == "BOSS_KILL" then
        local encounterId, encounterName = ...
        local statistics = Statistics:Initialize()
        local key = tostring(encounterId or encounterName or "unknown")
        statistics.bosses[key] = encounterName or key
    elseif event == "PLAYER_JUMPED" then
        local statistics = Statistics:Initialize()
        statistics.jumps = statistics.jumps + 1
    end
end)
