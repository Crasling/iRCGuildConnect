local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

iRC.Achievements = {}
local Achievements = iRC.Achievements

Achievements.Catalog = {
    { id = "guild_bosses_10", category = "Guild Achievements", points = 10, title = "Guild Vanguard", description = "Defeat 10 unique bosses with a guild-only group." },
    { id = "guild_bosses_25", category = "Guild Achievements", points = 25, title = "Guild Boss Hunters", description = "Defeat 25 unique bosses with a guild-only group." },
    { id = "guild_bosses_50", category = "Guild Achievements", points = 50, title = "Guild Legends", description = "Defeat 50 unique bosses with a guild-only group." },
    { id = "guild_hard_quests_5", category = "Guild Achievements", points = 10, title = "Shared Burdens", description = "Complete 5 quests at or above your level with a guild-only group." },
    { id = "guild_hard_quests_20", category = "Guild Achievements", points = 25, title = "Guild Expedition", description = "Complete 20 quests at or above your level with a guild-only group." },
    { id = "guild_hard_quests_50", category = "Guild Achievements", points = 50, title = "A Guild's Journey", description = "Complete 50 quests at or above your level with a guild-only group." },
}

for _, dungeon in ipairs(iRC.GuildChallenges and iRC.GuildChallenges.Dungeons or {}) do
    Achievements.Catalog[#Achievements.Catalog + 1] = {
        id = dungeon.id, category = "Guild Achievements", points = 15, title = dungeon.name,
        description = "Finish " .. dungeon.name .. " with members of your guild only.",
    }
end

function Achievements:GetCompleted()
    iRCCharDB.achievements = iRCCharDB.achievements or {}
    return iRCCharDB.achievements
end

function Achievements:IsComplete(id, source)
    return (source or self:GetCompleted())[id] ~= nil
end

function Achievements:GetCompletedIds()
    local completed, ids = self:GetCompleted(), {}
    for _, achievement in ipairs(self.Catalog) do if completed[achievement.id] then ids[#ids + 1] = achievement.id end end
    return ids
end

function Achievements:GetGuildPoints(source)
    local points = 0
    for _, achievement in ipairs(self.Catalog) do if self:IsComplete(achievement.id, source) then points = points + achievement.points end end
    return points
end

function Achievements:GetPoints()
    return self:GetGuildPoints() + iRC:GetHardcoreAchievementPoints()
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
    if iRC:GetSettings().showAchievementNotifications then
        iRC:Print(iRC:Text("ACHIEVEMENT_EARNED", achievement.title))
    end
    iRC:SendHello()
    if iRC.AchievementsUI then iRC.AchievementsUI:RefreshIfShown() end
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
