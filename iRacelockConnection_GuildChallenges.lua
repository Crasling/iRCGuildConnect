local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local Challenges = {}
iRC.GuildChallenges = Challenges

Challenges.Dungeons = {
    { id = "guild_rfc", boss = "Taragaman the Hungerer", npc = 11520, name = "Ragefire Chasm" },
    { id = "guild_dm", boss = "Edwin VanCleef", npc = 639, name = "The Deadmines" },
    { id = "guild_wc", boss = "Mutanus the Devourer", npc = 3654, name = "Wailing Caverns" },
    { id = "guild_sfk", boss = "Archmage Arugal", npc = 4275, name = "Shadowfang Keep" },
    { id = "guild_bfd", boss = "Aku'mai", npc = 4829, name = "Blackfathom Deeps" },
    { id = "guild_stockades", boss = "Bazil Thredd", npc = 8127, name = "The Stockade" },
    { id = "guild_gnomeregan", boss = "Mekgineer Thermaplugg", npc = 7800, name = "Gnomeregan" },
    { id = "guild_rfk", boss = "Charlga Razorflank", npc = 4421, name = "Razorfen Kraul" },
    { id = "guild_sm_graveyard", boss = "Interrogator Vishas", npc = 3983, name = "Scarlet Monastery: Graveyard" },
    { id = "guild_sm_library", boss = "Arcanist Doan", npc = 6480, name = "Scarlet Monastery: Library" },
    { id = "guild_sm_armory", boss = "Herod", npc = 3975, name = "Scarlet Monastery: Armory" },
    { id = "guild_sm_cathedral", boss = "High Inquisitor Whitemane", npc = 3977, name = "Scarlet Monastery: Cathedral" },
    { id = "guild_rfd", boss = "Amnennar the Coldbringer", npc = 7358, name = "Razorfen Downs" },
    { id = "guild_uldaman", boss = "Archaedas", npc = 2748, name = "Uldaman" },
    { id = "guild_zf", boss = "Chief Ukorz Sandscalp", npc = 7267, name = "Zul'Farrak" },
    { id = "guild_maraudon", boss = "Princess Theradras", npc = 12201, name = "Maraudon" },
    { id = "guild_st", boss = "Shade of Eranikus", npc = 5709, name = "The Temple of Atal'Hakkar" },
    { id = "guild_brd", boss = "Emperor Dagran Thaurissan", npc = 9019, name = "Blackrock Depths" },
    { id = "guild_lbrs", boss = "Overlord Wyrmthalak", npc = 9568, name = "Lower Blackrock Spire" },
    { id = "guild_ubrs", boss = "General Drakkisath", npc = 10363, name = "Upper Blackrock Spire" },
    { id = "guild_diremaul_east", boss = "Alzzin the Wildshaper", npc = 11492, name = "Dire Maul East" },
    { id = "guild_diremaul_west", boss = "Prince Tortheldrin", npc = 11486, name = "Dire Maul West" },
    { id = "guild_diremaul_north", boss = "King Gordok", npc = 11501, name = "Dire Maul North" },
    { id = "guild_scholomance", boss = "Darkmaster Gandling", npc = 1853, name = "Scholomance" },
    { id = "guild_stratholme", boss = "Baron Rivendare", npc = 10440, name = "Stratholme" },
}

local dungeonByBoss, dungeonByNpc = {}, {}
for _, dungeon in ipairs(Challenges.Dungeons) do
    dungeonByBoss[string.lower(dungeon.boss)] = dungeon
    dungeonByNpc[dungeon.npc] = dungeon
end

local function getProgress()
    iRCCharDB = iRCCharDB or {}
    iRCCharDB.guildChallengeProgress = iRCCharDB.guildChallengeProgress or { bosses = {}, quests = {}, questLevels = {} }
    local progress = iRCCharDB.guildChallengeProgress
    progress.bosses = progress.bosses or {}
    progress.quests = progress.quests or {}
    progress.questLevels = progress.questLevels or {}
    return progress
end

local function countEntries(entries)
    local count = 0
    for _ in pairs(entries) do count = count + 1 end
    return count
end

local function award(id)
    if iRC.Achievements then iRC.Achievements:Award(id) end
end

local function checkThresholds(progress)
    local bosses = countEntries(progress.bosses)
    local quests = countEntries(progress.quests)
    if bosses >= 10 then award("guild_bosses_10") end
    if bosses >= 25 then award("guild_bosses_25") end
    if bosses >= 50 then award("guild_bosses_50") end
    if quests >= 5 then award("guild_hard_quests_5") end
    if quests >= 20 then award("guild_hard_quests_20") end
    if quests >= 50 then award("guild_hard_quests_50") end
end

local function getQuestLevel(questId)
    if C_QuestLog and C_QuestLog.GetQuestDifficultyLevel then
        local ok, level = pcall(C_QuestLog.GetQuestDifficultyLevel, questId)
        if level and level > 0 then return level end
    end
    if C_QuestLog and C_QuestLog.GetInfo then
        local ok, info = pcall(C_QuestLog.GetInfo, questId)
        if info and info.level and info.level > 0 then return info.level end
    end
    return nil
end

local frame = CreateFrame("Frame")
pcall(frame.RegisterEvent, frame, "BOSS_KILL")
frame:RegisterEvent("QUEST_TURNED_IN")
frame:RegisterEvent("QUEST_ACCEPTED")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:SetScript("OnEvent", function(_, event, ...)
    if not iRC:IsGuildOnlyGroup() then return end
    local progress = getProgress()
    if event == "BOSS_KILL" then
        local _, encounterName = ...
        if not encounterName then return end
        local bossKey = string.lower(encounterName)
        progress.bosses[bossKey] = time()
        local dungeon = dungeonByBoss[bossKey]
        if dungeon then award(dungeon.id) end
        checkThresholds(progress)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subEvent, _, _, _, _, _, destGuid = CombatLogGetCurrentEventInfo()
        if subEvent ~= "UNIT_DIED" or not destGuid then return end
        local npcId = tonumber(select(6, strsplit("-", destGuid)))
        local dungeon = npcId and dungeonByNpc[npcId]
        if dungeon then
            progress.bosses[string.lower(dungeon.boss)] = time()
            award(dungeon.id)
            checkThresholds(progress)
        end
    elseif event == "QUEST_ACCEPTED" then
        local questLogIndex, questId = ...
        if questLogIndex and questId and GetQuestLogTitle then
            local _, questLevel = GetQuestLogTitle(questLogIndex)
            if questLevel and questLevel > 0 then progress.questLevels[tostring(questId)] = questLevel end
        end
    elseif event == "QUEST_TURNED_IN" then
        local questId = ...
        local questLevel = questId and (progress.questLevels[tostring(questId)] or getQuestLevel(questId))
        if questId then progress.questLevels[tostring(questId)] = nil end
        if questLevel and questLevel >= (UnitLevel("player") or 1) then
            progress.quests[tostring(questId)] = time()
            checkThresholds(progress)
        end
    end
end)
