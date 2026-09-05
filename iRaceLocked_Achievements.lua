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
    { id = "guild_bosses_10", category = "Guild", points = 10, title = "Guild Vanguard", description = "Defeat 10 unique bosses with a guild-only group." },
    { id = "guild_bosses_25", category = "Guild", points = 25, title = "Guild Boss Hunters", description = "Defeat 25 unique bosses with a guild-only group." },
    { id = "guild_bosses_50", category = "Guild", points = 50, title = "Guild Legends", description = "Defeat 50 unique bosses with a guild-only group." },
    { id = "guild_hard_quests_5", category = "Guild", points = 10, title = "Shared Burdens", description = "Complete 5 quests at or above your level with a guild-only group." },
    { id = "guild_hard_quests_20", category = "Guild", points = 25, title = "Guild Expedition", description = "Complete 20 quests at or above your level with a guild-only group." },
    { id = "guild_hard_quests_50", category = "Guild", points = 50, title = "A Guild's Journey", description = "Complete 50 quests at or above your level with a guild-only group." },
}

for _, dungeon in ipairs(iRL.GuildChallenges and iRL.GuildChallenges.Dungeons or {}) do
    Achievements.Catalog[#Achievements.Catalog + 1] = {
        id = dungeon.id, category = "Guild", points = 15, title = dungeon.name,
        description = "Finish " .. dungeon.name .. " with members of your guild only.",
    }
end

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

function Achievements:Award(id)
    local completed = self:GetCompleted()
    if completed[id] then return false end
    local achievement
    for _, entry in ipairs(self.Catalog) do
        if entry.id == id then achievement = entry break end
    end
    if not achievement then return false end
    completed[id] = { earnedAt = time() }
    if iRL:GetSettings().showAchievementNotifications then
        iRL:Print("Achievement earned: |cffffff00" .. achievement.title .. "|r")
    end
    iRL:SendHello()
    if iRL.AchievementsUI then iRL.AchievementsUI:RefreshIfShown() end
    return true
end

function Achievements:Evaluate()
    local completed, unlocked = self:GetCompleted(), false
    for _, achievement in ipairs(self.Catalog) do
        if not completed[achievement.id] and achievement.isComplete and achievement.isComplete() then
            if self:Award(achievement.id) then unlocked = true end
        end
    end
    return unlocked
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:SetScript("OnEvent", function() Achievements:Evaluate() end)
