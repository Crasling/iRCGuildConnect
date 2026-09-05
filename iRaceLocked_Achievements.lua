local iRL = _G.iRaceLocked
if not iRL then return end

iRL.Achievements = {}
local Achievements = iRL.Achievements

Achievements.Catalog = {
    { id = "connection_joined", category = "Connection", points = 5, title = "A Common Cause", description = "Join your guild's iRacelockConnection connection.", isComplete = function() return iRL:IsInGuildConnection() end },
    { id = "level_10", category = "Journey", points = 10, title = "First Steps", description = "Reach level 10.", isComplete = function() return (UnitLevel("player") or 0) >= 10 end },
    { id = "level_20", category = "Journey", points = 10, title = "Finding Your Path", description = "Reach level 20.", isComplete = function() return (UnitLevel("player") or 0) >= 20 end },
    { id = "level_30", category = "Journey", points = 15, title = "Seasoned Traveller", description = "Reach level 30.", isComplete = function() return (UnitLevel("player") or 0) >= 30 end },
    { id = "level_40", category = "Journey", points = 20, title = "A Mount of Your Own", description = "Reach level 40.", isComplete = function() return (UnitLevel("player") or 0) >= 40 end },
    { id = "level_60", category = "Journey", points = 50, title = "A Race Remembered", description = "Reach level 60.", isComplete = function() return (UnitLevel("player") or 0) >= 60 end },
}

function Achievements:GetCompleted()
    iRLCharDB.achievements = iRLCharDB.achievements or {}
    return iRLCharDB.achievements
end

function Achievements:IsComplete(id, source)
    return (source or self:GetCompleted())[id] ~= nil
end

function Achievements:GetCompletedIds()
    local completed, ids = self:GetCompleted(), {}
    for _, achievement in ipairs(self.Catalog) do if completed[achievement.id] then ids[#ids + 1] = achievement.id end end
    return ids
end

function Achievements:GetPoints(source)
    local points = 0
    for _, achievement in ipairs(self.Catalog) do if self:IsComplete(achievement.id, source) then points = points + achievement.points end end
    return points
end

function Achievements:Evaluate()
    local completed, unlocked = self:GetCompleted(), false
    for _, achievement in ipairs(self.Catalog) do
        if not completed[achievement.id] and achievement.isComplete() then
            completed[achievement.id] = { earnedAt = time() }
            unlocked = true
            if iRL:GetSettings().showAchievementNotifications then
                iRL:Print("Achievement earned: |cffffff00" .. achievement.title .. "|r")
            end
        end
    end
    if unlocked then
        iRL:SendHello()
        if iRL.AchievementsUI then iRL.AchievementsUI:RefreshIfShown() end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:SetScript("OnEvent", function() Achievements:Evaluate() end)
