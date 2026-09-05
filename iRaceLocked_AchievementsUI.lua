local iRL = _G.iRaceLocked
if not iRL then return end

local UI = {}
iRL.AchievementsUI = UI

local COLORS = {
    gold = iRL.ColorValues.Orange,
    green = iRL.ColorValues.Green,
    muted = iRL.ColorValues.Gray,
    parchment = iRL.ColorValues.Orange,
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

local function makeAchievementRow(parent, index)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(78)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * 84))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -((index - 1) * 84))
    createBackdrop(row, { 0.10, 0.085, 0.07, 0.96 }, { 0.28, 0.25, 0.20, 1 })
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.iconFrame = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.iconFrame:SetSize(60, 60)
    row.iconFrame:SetPoint("LEFT", 8, 0)
    createBackdrop(row.iconFrame, { 0.04, 0.04, 0.04, 1 }, { 0.48, 0.38, 0.18, 1 })
    row.icon = row.iconFrame:CreateTexture(nil, "ARTWORK")
    row.icon:SetTexture("Interface\\Icons\\Achievement_General")
    row.icon:SetPoint("CENTER")
    row.icon:SetSize(46, 46)

    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.title:SetPoint("TOPLEFT", row.iconFrame, "TOPRIGHT", 11, -12)
    row.title:SetPoint("RIGHT", row, "RIGHT", -81, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.description = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.description:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -7)
    row.description:SetPoint("RIGHT", row, "RIGHT", -81, 0)
    row.description:SetJustifyH("LEFT")
    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.status:SetPoint("BOTTOMLEFT", row.iconFrame, "BOTTOMRIGHT", 11, 10)
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
    row.name:SetJustifyH("LEFT")
    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -5)
    row.detail:SetJustifyH("LEFT")
    row.badge = makeBadge(row)
    row.badge:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    return row
end

local function getCategories()
    local categories, seen = { "Summary" }, { Summary = true }
    for _, achievement in ipairs(iRL.Achievements.Catalog) do
        if not seen[achievement.category] then
            seen[achievement.category] = true
            categories[#categories + 1] = achievement.category
        end
    end
    categories[#categories + 1] = "Guild Members"
    return categories
end

local function getProfile(frame)
    if not frame.subjectName or iRL:NormalizeName(frame.subjectName) == iRL:NormalizeName(iRL:GetPlayerName()) then
        return iRL:GetLocalProfile(), iRL.Achievements:GetCompleted()
    end
    local connection = iRL:GetConnection()
    local profile = connection and connection.members[iRL:NormalizeName(frame.subjectName)]
    return profile, profile and profile.completed or {}
end

local function setTabAppearance(button, active)
    button:SetBackdropColor(active and 0.24 or 0.08, active and 0.16 or 0.065, active and 0.04 or 0.05, 0.96)
    button:SetBackdropBorderColor(active and 1 or 0.34, active and 0.72 or 0.28, active and 0.18 or 0.20, 1)
    button.label:SetTextColor(unpack(active and COLORS.gold or COLORS.parchment))
end

function UI:Create()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "iRaceLockedAchievementsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(940, 620)
    frame:SetPoint("CENTER")
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

    local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 15, -14)
    header:SetPoint("TOPRIGHT", -15, -14)
    header:SetHeight(74)
    createBackdrop(header, { 0.10, 0.07, 0.035, 0.98 }, { 0.55, 0.41, 0.17, 1 })

    frame.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", header, "TOP", 0, -13)
    frame.title:SetText(iRL.DisplayName .. " Achievements")
    frame.title:SetTextColor(unpack(COLORS.gold))
    frame.player = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.player:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 17, 13)
    frame.pointsLabel = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.pointsLabel:SetPoint("TOP", header, "TOP", 0, -38)
    frame.pointsLabel:SetText("Achievement Points")
    frame.pointsLabel:SetTextColor(unpack(COLORS.gold))
    frame.points = makeBadge(header)
    frame.points:SetPoint("BOTTOM", header, "BOTTOM", 0, 6)

    local sidebar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -98)
    sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 17)
    sidebar:SetWidth(228)
    createBackdrop(sidebar, { 0.18, 0.11, 0.045, 0.98 }, { 0.58, 0.43, 0.18, 1 })
    frame.sidebar = sidebar

    local sidebarTitle = sidebar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sidebarTitle:SetPoint("TOPLEFT", 14, -13)
    sidebarTitle:SetText("Achievements")
    sidebarTitle:SetTextColor(unpack(COLORS.gold))
    frame.tabs = {}
    for index, category in ipairs(getCategories()) do
        local tab = CreateFrame("Button", nil, sidebar, "BackdropTemplate")
        tab:SetSize(198, 31)
        tab:SetPoint("TOPLEFT", 14, -((index - 1) * 35 + 41))
        createBackdrop(tab, { 0.08, 0.065, 0.05, 0.96 }, { 0.34, 0.28, 0.20, 1 })
        tab:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        tab.label:SetPoint("LEFT", 12, 0)
        tab.label:SetText(category)
        tab.category = category
        tab:SetScript("OnClick", function(self)
            frame.category = self.category
            if self.category ~= "Guild Members" then frame.subjectName = iRL:GetPlayerName() end
            UI:Refresh()
        end)
        frame.tabs[category] = tab
    end

    local main = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    main:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 13, 0)
    main:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 17)
    createBackdrop(main, { 0.055, 0.047, 0.038, 0.98 }, { 0.46, 0.37, 0.21, 1 })
    frame.main = main
    frame.contentTitle = main:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.contentTitle:SetPoint("TOPLEFT", 15, -14)
    frame.contentTitle:SetTextColor(unpack(COLORS.gold))
    frame.contentSubtitle = main:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.contentSubtitle:SetPoint("TOPLEFT", frame.contentTitle, "BOTTOMLEFT", 0, -5)
    frame.contentSubtitle:SetPoint("RIGHT", main, "RIGHT", -22, 0)
    frame.contentSubtitle:SetJustifyH("LEFT")

    local scroll = CreateFrame("ScrollFrame", nil, main, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", main, "TOPLEFT", 15, -56)
    scroll:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -31, 14)
    frame.scroll = scroll
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(647)
    content:SetHeight(1)
    scroll:SetScrollChild(content)
    frame.scrollContent = content
    frame.achievementRows, frame.memberRows = {}, {}
    frame.category = "Summary"
    return frame
end

local function updateAchievementRows(frame, profile, completed)
    local visible = {}
    for _, achievement in ipairs(iRL.Achievements.Catalog) do
        if frame.category == "Summary" or frame.category == achievement.category then
            visible[#visible + 1] = achievement
        end
    end
    for index, achievement in ipairs(visible) do
        local row = frame.achievementRows[index]
        if not row then
            row = makeAchievementRow(frame.scrollContent, index)
            frame.achievementRows[index] = row
        end
        local complete = completed and completed[achievement.id]
        row.icon:SetDesaturated(not complete)
        row.title:SetText(achievement.title)
        row.title:SetTextColor(unpack(complete and COLORS.green or COLORS.muted))
        row.description:SetText(achievement.description)
        row.status:SetText(complete and "Completed" or "Not yet earned")
        row.status:SetTextColor(unpack(complete and COLORS.green or COLORS.muted))
        row.badge.value:SetText(achievement.points)
        if complete then
            row:SetBackdropBorderColor(0.80, 0.63, 0.13, 1)
        else
            row:SetBackdropBorderColor(0.28, 0.25, 0.20, 1)
        end
        row:Show()
    end
    for index = #visible + 1, #frame.achievementRows do frame.achievementRows[index]:Hide() end
    for _, row in ipairs(frame.memberRows) do row:Hide() end
    frame.scrollContent:SetHeight(math.max(1, #visible * 84))
    frame.scroll:SetVerticalScroll(0)
    frame.contentTitle:SetText(frame.category)
    local total = iRL.Achievements:GetPoints(completed)
    frame.contentSubtitle:SetText((profile and profile.name or "Unknown") .. " has earned " .. total .. " achievement points.")
end

local function updateMemberRows(frame)
    local profiles = { iRL:GetLocalProfile() }
    local connection = iRL:GetConnection()
    if connection then
        for _, profile in pairs(connection.members) do
            if iRL:NormalizeName(profile.name) ~= iRL:NormalizeName(iRL:GetPlayerName()) then profiles[#profiles + 1] = profile end
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
        row.name:SetTextColor(unpack(iRL:NormalizeName(profile.name) == iRL:NormalizeName(iRL:GetPlayerName()) and COLORS.green or COLORS.gold))
        row.detail:SetText((profile.race or "Unknown") .. " · " .. (profile.class or "Unknown") .. " · Level " .. (profile.level or 1))
        row.badge.value:SetText(profile.points or 0)
        row.profileName = profile.name
        row:SetScript("OnClick", function(self)
            frame.subjectName = self.profileName
            frame.category = "Summary"
            if iRL:NormalizeName(self.profileName) ~= iRL:NormalizeName(iRL:GetPlayerName()) then iRL:RequestInspection(self.profileName) end
            UI:Refresh()
        end)
        row:Show()
    end
    for index = #profiles + 1, #frame.memberRows do frame.memberRows[index]:Hide() end
    for _, row in ipairs(frame.achievementRows) do row:Hide() end
    frame.scrollContent:SetHeight(math.max(1, #profiles * 60))
    frame.scroll:SetVerticalScroll(0)
    frame.contentTitle:SetText("Guild Members")
    frame.contentSubtitle:SetText("Select a guild member to inspect their shared achievement progress.")
end

function UI:Refresh()
    local frame = self:Create()
    local profile, completed = getProfile(frame)
    local name = profile and profile.name or frame.subjectName or iRL:GetPlayerName()
    local race, class, level = profile and profile.race or "Unknown", profile and profile.class or "Unknown", profile and profile.level or 1
    frame.player:SetText(name .. "  " .. iRL.Colors.Gray .. race .. " " .. class .. " · Level " .. level .. iRL.Colors.Reset)
    frame.points.value:SetText(iRL.Achievements:GetPoints(completed))
    for category, tab in pairs(frame.tabs) do setTabAppearance(tab, frame.category == category) end
    if frame.category == "Guild Members" then updateMemberRows(frame) else updateAchievementRows(frame, profile, completed) end
end

function UI:Open(subjectName)
    local frame = self:Create()
    frame.subjectName = subjectName or iRL:GetPlayerName()
    if not frame.category then frame.category = "Summary" end
    frame:SetScale(iRL:GetSettings().achievementScale or 1)
    self:Refresh()
    frame:Show()
end

function UI:RefreshIfShown()
    if self.frame and self.frame:IsShown() then self:Refresh() end
end
