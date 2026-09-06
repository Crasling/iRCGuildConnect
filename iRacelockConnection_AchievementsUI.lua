local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local UI = {}
iRC.AchievementsUI = UI

local COLORS = {
    gold = iRC.ColorValues.Orange,
    green = iRC.ColorValues.Green,
    muted = iRC.ColorValues.Gray,
    parchment = iRC.ColorValues.Orange,
}

local RACE_ICONS = {
    HUMAN = "Interface\\Icons\\Achievement_Character_Human_Male",
    DWARF = "Interface\\Icons\\Achievement_Character_Dwarf_Male",
    NIGHTELF = "Interface\\Icons\\Achievement_Character_Nightelf_Male",
    GNOME = "Interface\\Icons\\Achievement_Character_Gnome_Male",
    DRAENEI = "Interface\\Icons\\Achievement_Character_Draenei_Male",
    ORC = "Interface\\Icons\\Achievement_Character_Orc_Male",
    SCOURGE = "Interface\\Icons\\Achievement_Character_Undead_Male",
    TAUREN = "Interface\\Icons\\Achievement_Character_Tauren_Male",
    TROLL = "Interface\\Icons\\Achievement_Character_Troll_Male",
    BLOODELF = "Interface\\Icons\\Achievement_Character_Bloodelf_Male",
}

local RACE_COLORS = {
    HUMAN = { 0.82, 0.62, 0.25 }, DWARF = { 0.74, 0.43, 0.18 }, NIGHTELF = { 0.56, 0.30, 0.78 }, GNOME = { 0.35, 0.68, 0.95 }, DRAENEI = { 0.45, 0.46, 0.90 },
    ORC = { 0.62, 0.18, 0.14 }, SCOURGE = { 0.43, 0.63, 0.50 }, TAUREN = { 0.56, 0.32, 0.18 }, TROLL = { 0.12, 0.62, 0.88 }, BLOODELF = { 0.84, 0.22, 0.24 },
    Unknown = { 0.45, 0.45, 0.45 },
}

local RACE_LABELS = {
    HUMAN = "Human", DWARF = "Dwarf", NIGHTELF = "Night Elf", GNOME = "Gnome", DRAENEI = "Draenei",
    ORC = "Orc", SCOURGE = "Undead", TAUREN = "Tauren", TROLL = "Troll", BLOODELF = "Blood Elf",
}

local RACES_BY_FACTION = {
    Horde = { "TROLL", "ORC", "SCOURGE", "TAUREN" },
    Alliance = { "HUMAN", "DWARF", "NIGHTELF", "GNOME" },
}

if iRC:SupportsTBCPlayableRaces() then
    RACES_BY_FACTION.Horde[#RACES_BY_FACTION.Horde + 1] = "BLOODELF"
    RACES_BY_FACTION.Alliance[#RACES_BY_FACTION.Alliance + 1] = "DRAENEI"
end

local FACTION_STYLES = {
    Horde = { border = { 0.72, 0.18, 0.15, 1 }, background = { 0.13, 0.035, 0.03, 0.92 } },
    Alliance = { border = { 0.18, 0.42, 0.80, 1 }, background = { 0.025, 0.07, 0.16, 0.92 } },
}

local PODIUM_COLORS = {
    [1] = { 0.95, 0.72, 0.18, 1 },
    [2] = { 0.72, 0.74, 0.78, 1 },
    [3] = { 0.68, 0.38, 0.17, 1 },
}

local FALLBACK_CLASS_COLORS = {
    WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 }, HUNTER = { 0.67, 0.83, 0.45 }, ROGUE = { 1, 0.96, 0.41 },
    PRIEST = { 0.95, 0.95, 0.95 }, SHAMAN = { 0, 0.44, 0.87 }, MAGE = { 0.25, 0.78, 0.92 }, WARLOCK = { 0.53, 0.53, 0.93 }, DRUID = { 1, 0.49, 0.04 },
}

local function createBackdrop(frame, color, border)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(unpack(color))
    frame:SetBackdropBorderColor(unpack(border))
end

local function makeBadge(parent)
    local badge = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    badge:SetSize(62, 42)
    createBackdrop(badge, { 0.07, 0.06, 0.05, 0.95 }, { 0.55, 0.47, 0.25, 1 })
    badge.value = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    badge.value:SetPoint("CENTER", 0, 0)
    badge.value:SetTextColor(unpack(COLORS.gold))
    return badge
end

local function makeAchievementRow(parent)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(84)
    createBackdrop(row, { 0.10, 0.085, 0.07, 0.96 }, { 0.28, 0.25, 0.20, 1 })
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.iconFrame = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.iconFrame:SetSize(60, 60)
    row.iconFrame:SetPoint("TOPLEFT", 8, -8)
    createBackdrop(row.iconFrame, { 0.04, 0.04, 0.04, 1 }, { 0.48, 0.38, 0.18, 1 })
    row.icon = row.iconFrame:CreateTexture(nil, "ARTWORK")
    row.icon:SetTexture("Interface\\Icons\\Achievement_General")
    row.icon:SetPoint("CENTER")
    row.icon:SetSize(46, 46)

    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.title:SetPoint("TOPLEFT", row.iconFrame, "TOPRIGHT", 12, -8)
    row.title:SetPoint("RIGHT", row, "RIGHT", -88, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(true)
    row.description = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.description:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -7)
    row.description:SetPoint("RIGHT", row, "RIGHT", -88, 0)
    row.description:SetJustifyH("LEFT")
    row.description:SetWordWrap(true)
    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.status:SetPoint("TOPLEFT", row.description, "BOTTOMLEFT", 0, -6)
    row.status:SetPoint("RIGHT", row, "RIGHT", -88, 0)
    row.status:SetJustifyH("LEFT")
    row.badge = makeBadge(row)
    row.badge:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    return row
end

local function makeMemberRow(parent, index)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(54)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * 60))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -((index - 1) * 60))
    createBackdrop(row, { 0.10, 0.085, 0.07, 0.96 }, { 0.28, 0.25, 0.20, 1 })
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", 14, -10)
    row.name:SetPoint("RIGHT", row, "RIGHT", -84, 0)
    row.name:SetJustifyH("LEFT")
    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -5)
    row.detail:SetPoint("RIGHT", row, "RIGHT", -84, 0)
    row.detail:SetJustifyH("LEFT")
    row.badge = makeBadge(row)
    row.badge:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    return row
end

local function makeRaceCard(parent)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetHeight(178)
    createBackdrop(card, { 0.045, 0.055, 0.075, 0.98 }, { 0.30, 0.31, 0.34, 1 })

    card.accent = card:CreateTexture(nil, "ARTWORK")
    card.accent:SetWidth(4)
    card.accent:SetPoint("TOPLEFT", 4, -5)
    card.accent:SetPoint("BOTTOMLEFT", 4, 5)

    card.iconFrame = CreateFrame("Frame", nil, card, "BackdropTemplate")
    card.iconFrame:SetSize(46, 46)
    card.iconFrame:SetPoint("TOPLEFT", 13, -12)
    createBackdrop(card.iconFrame, { 0.03, 0.03, 0.03, 1 }, { 0.58, 0.49, 0.25, 1 })
    card.icon = card.iconFrame:CreateTexture(nil, "ARTWORK")
    card.icon:SetPoint("CENTER")
    card.icon:SetSize(38, 38)

    card.race = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    card.race:SetPoint("TOPLEFT", card.iconFrame, "TOPRIGHT", 9, -1)
    card.race:SetTextColor(unpack(COLORS.gold))
    card.rank = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.rank:SetPoint("TOPRIGHT", -14, -16)
    card.rank:SetTextColor(unpack(COLORS.gold))
    card.freshness = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.freshness:SetPoint("TOPLEFT", card.iconFrame, "TOPRIGHT", 9, -27)
    card.freshness:SetPoint("RIGHT", card, "RIGHT", -14, 0)
    card.freshness:SetJustifyH("LEFT")
    card.guildLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.guildLabel:SetPoint("TOP", card, "TOP", 0, -65)
    card.guildLabel:SetText("Guilds")
    card.guildLabel:SetTextColor(unpack(COLORS.gold))
    card.guild = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.guild:SetPoint("TOP", card.guildLabel, "BOTTOM", 0, -3)
    card.guild:SetWidth(285)
    card.guild:SetJustifyH("CENTER")

    card.averageLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.averageLabel:SetPoint("TOP", card, "TOP", -102, -104)
    card.averageLabel:SetText("Average level")
    card.membersLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.membersLabel:SetPoint("TOP", card, "TOP", 0, -104)
    card.membersLabel:SetText("Total players")
    card.pointsLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.pointsLabel:SetPoint("TOP", card, "TOP", 102, -104)
    card.pointsLabel:SetText("Level 60")
    card.average = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.average:SetPoint("TOP", card.averageLabel, "BOTTOM", 0, -3)
    card.members = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.members:SetPoint("TOP", card.membersLabel, "BOTTOM", 0, -3)
    card.points = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.points:SetPoint("TOP", card.pointsLabel, "BOTTOM", 0, -3)

    card.classesTitle = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.classesTitle:SetPoint("TOP", card, "TOP", 0, -139)
    card.classesTitle:SetText("Class breakdown")
    card.classText = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.classText:SetPoint("TOPLEFT", 15, -153)
    card.classText:SetPoint("TOPRIGHT", -15, -153)
    card.classText:SetJustifyH("CENTER")
    card.classText:SetWordWrap(false)
    card.classBar = CreateFrame("Frame", nil, card)
    card.classBar:SetPoint("TOPLEFT", 16, -168)
    card.classBar:SetPoint("TOPRIGHT", -16, -168)
    card.classBar:SetHeight(7)
    card.classSegments = {}
    card.metrics = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.metrics:SetPoint("TOPLEFT", 12, -184)
    card.metrics:SetPoint("TOPRIGHT", -12, -184)
    card.metrics:SetJustifyH("CENTER")
    card:EnableMouse(true)
    card:SetScript("OnEnter", function(self)
        if not GameTooltip or not self.report then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(iRC:GetRaceOverviewGuildName(self.report.race) or "—")
        if self.report.timestamp and self.report.timestamp > 0 then GameTooltip:AddLine(iRC:Text("RL_GRID_UPDATED", date("%Y-%m-%d %H:%M", self.report.timestamp))) end
        if self.report.source then GameTooltip:AddLine(iRC:Text("RL_GRID_SOURCE", self.report.source)) end
        GameTooltip:AddLine(iRC:Text("RL_GRID_AP_SOURCE"), 1, 1, 1, true)
        if self.report.populationSource == "verified_compatible" then
            GameTooltip:AddLine(iRC:Text("RL_GRID_POPULATION", self.report.verifiedMembers or 0, self.report.compatibleMembers or 0), 1, 1, 1, true)
        else
            GameTooltip:AddLine(iRC:Text("RL_GRID_EXTERNAL_POPULATION"), 1, 1, 1, true)
        end
        if self.report.cached then GameTooltip:AddLine(iRC:Text("RL_GRID_CACHED"), 1, 0.65, 0) end
        for class, average in pairs(self.report.classAverageLevels or {}) do
            GameTooltip:AddLine(iRC:Text("RL_GRID_CLASS_LEVEL", class, average))
        end
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return card
end

local function makeFactionSection(parent, faction)
    local style = FACTION_STYLES[faction]
    local section = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    createBackdrop(section, style.background, style.border)
    section.title = section:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    section.title:SetPoint("TOPLEFT", 14, -10)
    section.title:SetText(faction)
    section.title:SetTextColor(unpack(style.border))
    return section
end

local function makeRacePodium(parent)
    local podium = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    createBackdrop(podium, { 0.075, 0.06, 0.04, 0.98 }, { 0.55, 0.41, 0.17, 1 })
    podium.title = podium:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    podium.title:SetPoint("TOP", 0, -7)
    podium.title:SetText("Top Races")
    podium.title:SetTextColor(unpack(COLORS.gold))
    podium.entries = {}

    for rank = 1, 3 do
        local entry = CreateFrame("Frame", nil, podium, "BackdropTemplate")
        createBackdrop(entry, { 0.045, 0.055, 0.075, 0.98 }, PODIUM_COLORS[rank])
        entry.icon = entry:CreateTexture(nil, "ARTWORK")
        entry.icon:SetSize(30, 30)
        entry.icon:SetPoint("LEFT", 8, 0)
        entry.rank = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        entry.rank:SetPoint("TOPLEFT", entry.icon, "TOPRIGHT", 7, -7)
        entry.rank:SetTextColor(unpack(PODIUM_COLORS[rank]))
        entry.race = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        entry.race:SetPoint("LEFT", entry.rank, "RIGHT", 5, 0)
        entry.race:SetPoint("RIGHT", entry, "RIGHT", -8, 0)
        entry.race:SetJustifyH("LEFT")
        entry.points = entry:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        entry.points:SetPoint("TOPLEFT", entry.rank, "BOTTOMLEFT", 0, -3)
        podium.entries[rank] = entry
    end
    return podium
end

local ACHIEVEMENT_NAVIGATION = {
    { id = "Achievements", label = "Achievements" },
    { id = "Hardcore Achievements", label = "Hardcore Achievements", child = true },
    { id = "Guild Achievements", label = "Guild Achievements", child = true },
    { id = "RP Achievements", label = "RP Achievements", child = true },
    { id = "Race Overview", label = "Race Overview" },
    { id = "Guild Members", label = "Guild Members" },
}

local function getProfile(frame)
    if not frame.subjectName or iRC:NormalizeName(frame.subjectName) == iRC:NormalizeName(iRC:GetPlayerName()) then
        return iRC:GetLocalProfile(), iRC.Achievements:GetCompleted()
    end
    local connection = iRC:GetConnection()
    local profile = connection and connection.members[iRC:NormalizeName(frame.subjectName)]
    return profile, profile and profile.completed or {}
end

local function completionStatus(record)
    if not record then return "Not yet earned" end
    if type(record) == "table" and record.earnedAt then
        return "Completed: " .. date("%d %b %Y", record.earnedAt)
    end
    return "Completed (date unavailable)"
end

local function setTabAppearance(button, active)
    button:SetBackdropColor(active and 0.24 or 0.08, active and 0.16 or 0.065, active and 0.04 or 0.05, 0.96)
    button:SetBackdropBorderColor(active and 1 or 0.34, active and 0.72 or 0.28, active and 0.18 or 0.20, 1)
    button.label:SetTextColor(unpack(active and COLORS.gold or COLORS.parchment))
end

function UI:Create()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "iRacelockConnectionAchievementsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(980, 650)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    createBackdrop(frame, { 0.025, 0.022, 0.018, 0.98 }, { 0.42, 0.35, 0.19, 1 })
    frame:Hide()
    tinsert(UISpecialFrames, frame:GetName())
    self.frame = frame

    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 4, 4)
    -- UIPanelCloseButton's default handler routes through Blizzard's panel
    -- manager, which can refuse a close while in combat. This is a normal
    -- addon frame, so hiding it directly is safe in and out of combat.
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 15, -14)
    header:SetPoint("TOPRIGHT", -15, -14)
    header:SetHeight(78)
    createBackdrop(header, { 0.10, 0.07, 0.035, 0.98 }, { 0.55, 0.41, 0.17, 1 })

    frame.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", header, "TOPLEFT", 18, -11)
    frame.title:SetText(iRC.DisplayName .. " Achievements")
    frame.title:SetTextColor(unpack(COLORS.gold))
    frame.player = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.player:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 17, 13)
    frame.pointsLabel = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.pointsLabel:SetPoint("RIGHT", header, "RIGHT", -94, 0)
    frame.pointsLabel:SetText("Achievement Points")
    frame.pointsLabel:SetTextColor(unpack(COLORS.gold))
    frame.points = makeBadge(header)
    frame.points:SetPoint("RIGHT", header, "RIGHT", -15, 0)

    local sidebar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -106)
    sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 17)
    sidebar:SetWidth(210)
    createBackdrop(sidebar, { 0.18, 0.11, 0.045, 0.98 }, { 0.58, 0.43, 0.18, 1 })
    frame.sidebar = sidebar

    local sidebarTitle = sidebar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sidebarTitle:SetPoint("TOPLEFT", 14, -13)
    sidebarTitle:SetText("Achievements")
    sidebarTitle:SetTextColor(unpack(COLORS.gold))
    frame.tabs = {}
    for index, item in ipairs(ACHIEVEMENT_NAVIGATION) do
        local tab = CreateFrame("Button", nil, sidebar, "BackdropTemplate")
        tab:SetSize(item.child and 166 or 180, 31)
        tab:SetPoint("TOPLEFT", item.child and 28 or 14, -((index - 1) * 35 + 41))
        createBackdrop(tab, { 0.08, 0.065, 0.05, 0.96 }, { 0.34, 0.28, 0.20, 1 })
        tab:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        tab.label:SetPoint("LEFT", 12, 0)
        tab.label:SetText(item.child and "- " .. item.label or item.label)
        tab.category = item.id
        tab:SetScript("OnClick", function(self)
            if self.category == "Hardcore Achievements" then
                UI:OpenHardcoreAchievements()
                return
            end
            frame.category = self.category
            if self.category ~= "Guild Members" and self.category ~= "Race Overview" then frame.subjectName = iRC:GetPlayerName() end
            UI:Refresh()
        end)
        frame.tabs[item.id] = tab
    end

    local main = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    main:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 13, 0)
    main:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 17)
    createBackdrop(main, { 0.055, 0.047, 0.038, 0.98 }, { 0.46, 0.37, 0.21, 1 })
    frame.main = main
    frame.contentTitle = main:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.contentTitle:SetPoint("TOPLEFT", 15, -14)
    frame.contentTitle:SetTextColor(unpack(COLORS.gold))
    frame.raceRefresh = CreateFrame("Button", nil, main, "UIPanelButtonTemplate")
    frame.raceRefresh:SetSize(125, 23)
    frame.raceRefresh:SetPoint("TOPRIGHT", -14, -9)
    frame.raceRefresh:SetText(iRC:Text("RL_GRID_REFRESH"))
    frame.raceRefresh:SetScript("OnClick", function()
        if iRC.RaceGrid then iRC.RaceGrid:PublishFromClick() end
        UI:Refresh()
    end)
    frame.raceRefresh:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(iRC:Text("RL_GRID_REFRESH"))
        GameTooltip:AddLine(iRC:Text("RL_GRID_REFRESH_TIP"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame.raceRefresh:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    frame.raceRefresh:Hide()
    frame.contentSubtitle = main:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.contentSubtitle:SetPoint("TOPLEFT", frame.contentTitle, "BOTTOMLEFT", 0, -5)
    frame.contentSubtitle:SetPoint("RIGHT", main, "RIGHT", -22, 0)
    frame.contentSubtitle:SetJustifyH("LEFT")
    frame.contentSubtitle:SetWordWrap(true)

    local scroll = CreateFrame("ScrollFrame", nil, main, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", main, "TOPLEFT", 15, -78)
    scroll:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -31, 14)
    frame.scroll = scroll
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(675)
    content:SetHeight(1)
    scroll:SetScrollChild(content)
    frame.scrollContent = content
    frame.achievementRows, frame.memberRows, frame.raceCards, frame.factionSections = {}, {}, {}, {}
    frame.racePodium = makeRacePodium(content)
    frame.racePodium:Hide()
    frame.category = "Achievements"
    return frame
end

local function updateAchievementRows(frame, profile, completed)
    local visible = {}
    for _, achievement in ipairs(iRC.Achievements.Catalog) do
        if frame.category == achievement.category then
            visible[#visible + 1] = achievement
        end
    end
    local yOffset = 0
    for index, achievement in ipairs(visible) do
        local row = frame.achievementRows[index]
        if not row then
            row = makeAchievementRow(frame.scrollContent)
            frame.achievementRows[index] = row
        end
        local complete = completed and completed[achievement.id]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.scrollContent, "TOPLEFT", 0, -yOffset)
        row:SetPoint("TOPRIGHT", frame.scrollContent, "TOPRIGHT", 0, -yOffset)
        row.icon:SetDesaturated(not complete)
        row.title:SetText(achievement.title)
        row.title:SetTextColor(unpack(complete and COLORS.green or COLORS.muted))
        row.description:SetText(achievement.description)
        row.status:SetText(completionStatus(complete))
        row.status:SetTextColor(unpack(complete and COLORS.green or COLORS.muted))
        row.badge.value:SetText(achievement.points)
        local titleHeight = math.max(row.title:GetStringHeight(), 16)
        local descriptionHeight = math.max(row.description:GetStringHeight(), 12)
        local statusHeight = math.max(row.status:GetStringHeight(), 12)
        local textHeight = 8 + titleHeight + 7 + descriptionHeight + 6 + statusHeight + 10
        row:SetHeight(math.max(84, textHeight))
        if complete then
            row:SetBackdropBorderColor(0.80, 0.63, 0.13, 1)
        else
            row:SetBackdropBorderColor(0.28, 0.25, 0.20, 1)
        end
        row:Show()
        yOffset = yOffset + row:GetHeight() + 8
    end
    for index = #visible + 1, #frame.achievementRows do frame.achievementRows[index]:Hide() end
    for _, row in ipairs(frame.memberRows) do row:Hide() end
    for _, card in ipairs(frame.raceCards) do card:Hide() end
    for _, section in pairs(frame.factionSections) do section:Hide() end
    frame.racePodium:Hide()
    frame.scrollContent:SetHeight(math.max(1, yOffset > 0 and yOffset - 8 or 1))
    frame.scroll:SetVerticalScroll(0)
    frame.contentTitle:SetText(frame.category)
    local guildPoints = iRC.Achievements:GetGuildPoints(completed)
    local total = profile and profile.points or guildPoints
    if profile and iRC:NormalizeName(profile.name) == iRC:NormalizeName(iRC:GetPlayerName()) then
        local hardcorePoints = iRC:GetHardcoreAchievementPoints()
        total = hardcorePoints + guildPoints
        if iRC:HasHardcoreAchievements() then
            frame.contentSubtitle:SetText("Hardcore Achievements: " .. hardcorePoints .. "  |  Guild Achievements: " .. guildPoints .. "  |  Total: " .. total)
        else
            frame.contentSubtitle:SetText("Guild Achievements: " .. guildPoints .. ". Install HardcoreAchievements to add its points to your total.")
        end
    else
        frame.contentSubtitle:SetText((profile and profile.name or "Unknown") .. " has earned " .. total .. " shared achievement points.")
    end
end

local function getTrollFoundPoints()
    local getPoints = _G.TrollFound_GetTotalPoints
    if type(getPoints) ~= "function" then return 0 end
    local ok, points = pcall(getPoints)
    return ok and (tonumber(points) or 0) or 0
end

local function hideNonListContent(frame)
    for _, row in ipairs(frame.memberRows) do row:Hide() end
    for _, card in ipairs(frame.raceCards) do card:Hide() end
    for _, section in pairs(frame.factionSections) do section:Hide() end
    frame.racePodium:Hide()
end

local function updateAchievementOverview(frame)
    local guildPoints = iRC.Achievements:GetGuildPoints()
    local sources = {
        {
            category = "Hardcore Achievements", title = "Hardcore Achievements", icon = "Interface\\Icons\\Achievement_General",
            description = "Open the complete HardcoreAchievements window.", points = iRC:GetHardcoreAchievementPoints(),
            available = iRC:HasHardcoreAchievements(),
        },
        {
            category = "Guild Achievements", title = "Guild Achievements", icon = "Interface\\Icons\\Achievement_GuildPerks_GuildPage",
            description = "iRC achievements earned while completing guild-only challenges.", points = guildPoints, available = true,
        },
        {
            category = "RP Achievements", title = "RP Achievements", icon = "Interface\\Icons\\INV_Misc_Book_09",
            description = "TrollFound achievements displayed in iRC's achievement list.", points = getTrollFoundPoints(),
            available = type(_G.TrollFound_Achievements) == "table",
        },
    }
    local yOffset = 0
    for index, source in ipairs(sources) do
        local row = frame.achievementRows[index]
        if not row then
            row = makeAchievementRow(frame.scrollContent)
            frame.achievementRows[index] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.scrollContent, "TOPLEFT", 0, -yOffset)
        row:SetPoint("TOPRIGHT", frame.scrollContent, "TOPRIGHT", 0, -yOffset)
        row:SetHeight(84)
        row.icon:SetTexture(source.icon)
        row.icon:SetDesaturated(not source.available)
        row.title:SetText(source.title)
        row.title:SetTextColor(unpack(source.available and COLORS.gold or COLORS.muted))
        row.description:SetText(source.description)
        row.status:SetText(source.available and "Available" or "Addon not detected")
        row.status:SetTextColor(unpack(source.available and COLORS.green or COLORS.muted))
        row.badge.value:SetText(source.points)
        row:SetBackdropBorderColor(source.available and 0.48 or 0.28, source.available and 0.38 or 0.25, source.available and 0.18 or 0.20, 1)
        row:SetScript("OnClick", function()
            if source.category == "Hardcore Achievements" then
                UI:OpenHardcoreAchievements()
            else
                frame.category = source.category
                frame.subjectName = iRC:GetPlayerName()
                UI:Refresh()
            end
        end)
        row:Show()
        yOffset = yOffset + 92
    end
    for index = #sources + 1, #frame.achievementRows do frame.achievementRows[index]:Hide() end
    hideNonListContent(frame)
    frame.scrollContent:SetHeight(math.max(1, yOffset - 8))
    frame.scroll:SetVerticalScroll(0)
    frame.contentTitle:SetText("Achievements")
    frame.contentSubtitle:SetText("Choose an achievement source. HardcoreAchievements and TrollFound keep ownership of their own progress data.")
end

local function updateRPAchievementRows(frame)
    local source = _G.TrollFound_Achievements
    local completed = _G.TrollFound_HasAchievement
    local metadata = _G.TrollFound_GetAchievementMetadata
    if type(source) ~= "table" then
        updateAchievementOverview(frame)
        frame.contentTitle:SetText("RP Achievements")
        frame.contentSubtitle:SetText("TrollFound is not detected. Install and enable TrollFound to view its roleplay achievements here.")
        return
    end

    local achievements = {}
    for id, achievement in pairs(source) do
        if type(achievement) == "table" then achievements[#achievements + 1] = { id = id, achievement = achievement } end
    end
    table.sort(achievements, function(a, b)
        local first, second = tonumber(a.id), tonumber(b.id)
        if first and second then return first < second end
        return tostring(a.id) < tostring(b.id)
    end)
    local yOffset = 0
    for index, entry in ipairs(achievements) do
        local achievement = entry.achievement
        local row = frame.achievementRows[index]
        if not row then
            row = makeAchievementRow(frame.scrollContent)
            frame.achievementRows[index] = row
        end
        local done = type(completed) == "function" and completed(entry.id) or false
        local record = type(metadata) == "function" and metadata(entry.id) or nil
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.scrollContent, "TOPLEFT", 0, -yOffset)
        row:SetPoint("TOPRIGHT", frame.scrollContent, "TOPRIGHT", 0, -yOffset)
        row.icon:SetTexture(achievement.icon or "Interface\\Icons\\Achievement_General")
        row.icon:SetDesaturated(not done)
        row.title:SetText(achievement.name or "RP Achievement")
        row.title:SetTextColor(unpack(done and COLORS.green or COLORS.muted))
        row.description:SetText(achievement.description or "")
        local completedText = done and "Completed" or "Not yet earned"
        if done and type(record) == "table" and record.date then completedText = completedText .. ": " .. record.date end
        row.status:SetText(completedText)
        row.status:SetTextColor(unpack(done and COLORS.green or COLORS.muted))
        row.badge.value:SetText(tonumber(achievement.points) or 0)
        row:SetHeight(84)
        row:SetBackdropBorderColor(done and 0.80 or 0.28, done and 0.63 or 0.25, done and 0.13 or 0.20, 1)
        row:SetScript("OnClick", nil)
        row:Show()
        yOffset = yOffset + 92
    end
    for index = #achievements + 1, #frame.achievementRows do frame.achievementRows[index]:Hide() end
    hideNonListContent(frame)
    frame.scrollContent:SetHeight(math.max(1, yOffset - 8))
    frame.scroll:SetVerticalScroll(0)
    frame.contentTitle:SetText("RP Achievements")
    frame.contentSubtitle:SetText("Roleplay achievements provided by TrollFound and displayed through iRC.")
end

local function updateMemberRows(frame)
    local profiles = { iRC:GetLocalProfile() }
    local connection = iRC:GetConnection()
    if connection then
        for _, profile in pairs(connection.members) do
            if iRC:NormalizeName(profile.name) ~= iRC:NormalizeName(iRC:GetPlayerName()) then profiles[#profiles + 1] = profile end
        end
    end
    table.sort(profiles, function(a, b) return a.name < b.name end)
    for index, profile in ipairs(profiles) do
        local row = frame.memberRows[index]
        if not row then
            row = makeMemberRow(frame.scrollContent, index)
            frame.memberRows[index] = row
        end
        row.name:SetText(profile.name)
        row.name:SetTextColor(unpack(iRC:NormalizeName(profile.name) == iRC:NormalizeName(iRC:GetPlayerName()) and COLORS.green or COLORS.gold))
        row.detail:SetText((profile.race or "Unknown") .. " · " .. (profile.class or "Unknown") .. " · Level " .. (profile.level or 1))
        row.badge.value:SetText(profile.points or 0)
        row.profileName = profile.name
        row:SetScript("OnClick", function(self)
            frame.subjectName = self.profileName
            frame.category = "Guild Achievements"
            if iRC:NormalizeName(self.profileName) ~= iRC:NormalizeName(iRC:GetPlayerName()) then iRC:RequestInspection(self.profileName) end
            UI:Refresh()
        end)
        row:Show()
    end
    for index = #profiles + 1, #frame.memberRows do frame.memberRows[index]:Hide() end
    for _, row in ipairs(frame.achievementRows) do row:Hide() end
    for _, card in ipairs(frame.raceCards) do card:Hide() end
    for _, section in pairs(frame.factionSections) do section:Hide() end
    frame.racePodium:Hide()
    frame.scrollContent:SetHeight(math.max(1, #profiles * 60))
    frame.scroll:SetVerticalScroll(0)
    frame.contentTitle:SetText("Guild Members")
    frame.contentSubtitle:SetText("Select a guild member to inspect their shared achievement progress.")
end

local function formatNumber(value)
    local number = math.floor(tonumber(value) or 0)
    local sign = number < 0 and "-" or ""
    local digits = tostring(math.abs(number)):reverse():gsub("(%d%d%d)", "%1,")
    return sign .. digits:reverse():gsub("^,", "")
end

local function getClassColor(class)
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] or FALLBACK_CLASS_COLORS[class]
    if not color then color = FALLBACK_CLASS_COLORS[class] or { 0.50, 0.50, 0.50 } end
    return color.r or color[1], color.g or color[2], color.b or color[3]
end

local CLASS_SHORT_NAMES = {
    WARRIOR = "War", PALADIN = "Pal", HUNTER = "Hun", ROGUE = "Rog", PRIEST = "Pri", SHAMAN = "Sha", MAGE = "Mag", WARLOCK = "Lock", DRUID = "Dru",
}

local function updateClassBreakdown(card, classes, totalMembers)
    local classGroups = {}
    for class, count in pairs(classes or {}) do classGroups[#classGroups + 1] = { class = class, count = count } end
    table.sort(classGroups, function(a, b) return a.count > b.count end)
    local labels, usedWidth = {}, 0
    local availableWidth = math.max(1, (card:GetWidth() or 333) - 32)
    for index, group in ipairs(classGroups) do
        local share = totalMembers > 0 and group.count / totalMembers or 0
        local percent = math.floor(share * 100 + 0.5)
        labels[#labels + 1] = (CLASS_SHORT_NAMES[group.class] or group.class) .. " " .. percent .. "%"
        local segment = card.classSegments[index]
        if not segment then
            segment = card.classBar:CreateTexture(nil, "ARTWORK")
            segment:SetHeight(7)
            card.classSegments[index] = segment
        end
        segment:ClearAllPoints()
        segment:SetPoint("LEFT", card.classBar, "LEFT", usedWidth, 0)
        local width = index == #classGroups and availableWidth - usedWidth or math.floor(availableWidth * share)
        segment:SetWidth(math.max(1, width))
        segment:SetColorTexture(getClassColor(group.class))
        segment:Show()
        usedWidth = usedWidth + width
    end
    for index = #classGroups + 1, #card.classSegments do card.classSegments[index]:Hide() end
    card.classText:SetText(#labels > 0 and table.concat(labels, "  ") or "No class data")
end

local function setRaceCard(card, group, rank)
    local accent = RACE_COLORS[group.race] or RACE_COLORS.Unknown
    card.accent:SetColorTexture(accent[1], accent[2], accent[3], 1)
    card.icon:SetTexture(RACE_ICONS[group.race] or "Interface\\Icons\\Achievement_General")
    card.race:SetText(RACE_LABELS[group.race] or group.race)
    card.rank:SetText("#" .. rank)
    card.guild:SetText(iRC:GetRaceOverviewGuildName(group.race) or "—")
    card.average:SetText(group.averageLevel or 0)
    card.members:SetText(group.members or 0)
    card.points:SetText(formatNumber(group.membersLevel60 or 0))
    card.report = group
    card.freshness:SetText(group.source and iRC:Text(group.cached and "RL_GRID_CACHED" or "RL_GRID_RECENT") or "")
    card.metrics:SetText(iRC:Text("RL_GRID_METRICS", group.guildDeaths ~= nil and tostring(group.guildDeaths) or "—"))
    updateClassBreakdown(card, group.classes, group.members)
    card:Show()
end

local function emptyRaceGroup(race, faction)
    return { race = race, faction = faction, guildName = iRC:GetRaceOverviewGuildName(race), members = 0, averageLevel = 0, points = 0, classes = {} }
end

local function updateRacePodium(frame, rankedGroups)
    local placementOrder = { 2, 1, 3 }
    frame.racePodium:ClearAllPoints()
    frame.racePodium:SetSize(675, 86)
    frame.racePodium:SetPoint("TOPLEFT", frame.scrollContent, "TOPLEFT", 0, 0)
    for _, rank in ipairs(placementOrder) do
        local entry = frame.racePodium.entries[rank]
        local group = rankedGroups[rank]
        entry:ClearAllPoints()
        entry:SetSize(207, 48)
        if rank == 1 then
            entry:SetPoint("TOP", frame.racePodium, "TOP", 0, -22)
        elseif rank == 2 then
            entry:SetPoint("TOPLEFT", frame.racePodium, "TOPLEFT", 10, -31)
        else
            entry:SetPoint("TOPRIGHT", frame.racePodium, "TOPRIGHT", -10, -31)
        end
        entry.rank:SetText("#" .. rank)
        if group then
            entry.icon:SetTexture(RACE_ICONS[group.race] or "Interface\\Icons\\Achievement_General")
            entry.race:SetText(RACE_LABELS[group.race] or group.race)
            entry.points:SetText(formatNumber(group.members or 0) .. " players")
        else
            entry.icon:SetTexture("Interface\\Icons\\Achievement_General")
            entry.race:SetText("No data")
            entry.points:SetText("0 players")
        end
        entry:Show()
    end
    frame.racePodium:Show()
end

local function updateRaceOverview(frame)
    local groupsByRace, totalPlayers = {}, 0
    local overviewGroups, overviewSource = iRC:GetRaceGridOverview()
    for _, group in ipairs(overviewGroups) do
        groupsByRace[group.race] = group
        totalPlayers = totalPlayers + (group.members or 0)
    end

    local allGroups = {}
    for faction, races in pairs(RACES_BY_FACTION) do
        for _, race in ipairs(races) do
            local group = groupsByRace[race] or emptyRaceGroup(race, faction)
            allGroups[#allGroups + 1] = group
        end
    end
    table.sort(allGroups, function(a, b)
        if a.members ~= b.members then return a.members > b.members end
        if a.averageLevel ~= b.averageLevel then return a.averageLevel > b.averageLevel end
        return a.race < b.race
    end)
    local ranks = {}
    for index, group in ipairs(allGroups) do ranks[group.race] = index end

    local rowHeight, gap, contentWidth = 214, 9, 675
    updateRacePodium(frame, allGroups)
    local usedCards, yOffset = 0, 95

    for _, faction in ipairs({ "Horde", "Alliance" }) do
        local section = frame.factionSections[faction]
        if not section then
            section = makeFactionSection(frame.scrollContent, faction)
            frame.factionSections[faction] = section
        end
        local races = {}
        for _, race in ipairs(RACES_BY_FACTION[faction]) do
            races[#races + 1] = groupsByRace[race] or emptyRaceGroup(race, faction)
        end
        local rowCount = math.ceil(#races / 2)
        local sectionHeight = 44 + rowCount * rowHeight + math.max(0, rowCount - 1) * gap + 10
        section:ClearAllPoints()
        section:SetSize(contentWidth, sectionHeight)
        section:SetPoint("TOPLEFT", frame.scrollContent, "TOPLEFT", 0, -yOffset)
        section:Show()
        local cardWidth = (contentWidth - 32) / 2
        for index, group in ipairs(races) do
            usedCards = usedCards + 1
            local card = frame.raceCards[usedCards]
            if not card then
                card = makeRaceCard(section)
                frame.raceCards[usedCards] = card
            elseif card:GetParent() ~= section then
                card:SetParent(section)
            end
            local column = (index - 1) % 2
            local row = math.floor((index - 1) / 2)
            card:ClearAllPoints()
            card:SetSize(cardWidth, rowHeight)
            card:SetPoint("TOPLEFT", section, "TOPLEFT", 12 + column * (cardWidth + 8), -(36 + row * (rowHeight + gap)))
            setRaceCard(card, group, ranks[group.race] or usedCards)
        end
        yOffset = yOffset + sectionHeight + gap
    end
    for index = usedCards + 1, #frame.raceCards do frame.raceCards[index]:Hide() end
    for _, row in ipairs(frame.achievementRows) do row:Hide() end
    for _, row in ipairs(frame.memberRows) do row:Hide() end
    frame.scrollContent:SetHeight(math.max(1, yOffset - gap))
    frame.scroll:SetVerticalScroll(0)
    frame.contentTitle:SetText("RaceLocked Overview")
    frame.contentSubtitle:SetText(iRC:Text("RL_GRID_OVERVIEW_DESC"))
    return totalPlayers
end

function UI:Refresh()
    self.pendingRefresh = nil
    local frame = self:Create()
    frame.raceRefresh:SetShown(frame.category == "Race Overview")
    local profile, completed = getProfile(frame)
    local name = profile and profile.name or frame.subjectName or iRC:GetPlayerName()
    local race, class, level = profile and profile.race or "Unknown", profile and profile.class or "Unknown", profile and profile.level or 1
    frame.player:SetText(name .. "  " .. iRC.Colors.Gray .. race .. " " .. class .. " · Level " .. level .. iRC.Colors.Reset)
    frame.pointsLabel:SetText(iRC:HasHardcoreAchievements() and "HCA + Guild Points" or "Guild Achievement Points")
    frame.points.value:SetText(profile and profile.points or iRC.Achievements:GetPoints())
    for category, tab in pairs(frame.tabs) do setTabAppearance(tab, frame.category == category) end
    if frame.category == "Achievements" then
        frame.pointsLabel:SetText("Achievement Sources")
        frame.points.value:SetText("")
        updateAchievementOverview(frame)
    elseif frame.category == "RP Achievements" then
        frame.pointsLabel:SetText("TrollFound Points")
        frame.points.value:SetText(getTrollFoundPoints())
        updateRPAchievementRows(frame)
    elseif frame.category == "Guild Members" then
        updateMemberRows(frame)
    elseif frame.category == "Race Overview" then
        local connection = iRC:GetConnection()
        frame.player:SetText((connection and connection.guildName or "No guild") .. iRC.Colors.Gray .. "  Guild race progression" .. iRC.Colors.Reset)
        frame.pointsLabel:SetText("Reported Players")
        frame.points.value:SetText(formatNumber(updateRaceOverview(frame)))
    else
        updateAchievementRows(frame, profile, completed)
    end
end

function UI:OpenHardcoreAchievements()
    if not iRC:HasHardcoreAchievements() then
        iRC:Print(iRC.Colors.Red .. iRC:Text("HCA_UNAVAILABLE") .. iRC.Colors.Reset)
        return
    end
    iRC:CloseAllWindows()
    -- HCA creates AchievementPanel lazily when its public tab opener runs, so
    -- do not require the frame to exist before requesting it.
    local hardcore = _G.HardcoreAchievements
    if hardcore and type(hardcore.ShowAchievementTab) == "function" then
        hardcore.ShowAchievementTab()
        local hardcoreFrame = hardcore.AchievementPanel or _G.AchievementPanel
        if hardcoreFrame and hardcoreFrame.Raise then hardcoreFrame:Raise() end
        return
    end
    local hardcoreFrame = _G.AchievementPanel
    if hardcoreFrame then
        hardcoreFrame:Show()
        if hardcoreFrame.Raise then hardcoreFrame:Raise() end
        return
    end
    iRC:Print(iRC.Colors.Red .. iRC:Text("HCA_NOT_READY") .. iRC.Colors.Reset)
end

function UI:Open(subjectName)
    local frame = self:Create()
    if iRC.CloseWindowsExcept then iRC:CloseWindowsExcept(frame) end
    frame.subjectName = subjectName or iRC:GetPlayerName()
    if not frame.category or not frame.tabs[frame.category] or frame.category == "Hardcore Achievements" then frame.category = "Achievements" end
    frame:SetScale(iRC:GetSettings().achievementScale or 1)
    self:Refresh()
    frame:Show()
    frame:Raise()
end

function UI:Toggle()
    local frame = self:Create()
    if frame:IsShown() then
        frame:Hide()
    else
        self:Open()
    end
end

function UI:RefreshIfShown()
    if not self.frame or not self.frame:IsShown() or self.pendingRefresh then return end
    if not C_Timer or not C_Timer.After then self:Refresh(); return end
    local ticket = {}
    self.pendingRefresh = ticket
    C_Timer.After(0.2, function()
        if UI.pendingRefresh ~= ticket then return end
        UI.pendingRefresh = nil
        if UI.frame and UI.frame:IsShown() then UI:Refresh() end
    end)
end
