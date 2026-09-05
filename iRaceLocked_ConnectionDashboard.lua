local iRL = _G.iRaceLocked
if not iRL then return end

local Dashboard = {}
iRL.ConnectionDashboard = Dashboard

local ORANGE = iRL.ColorValues.Orange
local GREEN = iRL.ColorValues.Green
local GRAY = iRL.ColorValues.Gray

local function setBackdrop(frame, background, border)
    frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(unpack(background))
    frame:SetBackdropBorderColor(unpack(border))
end

local function makeRow(parent, index)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(48)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * 53))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -((index - 1) * 53))
    setBackdrop(row, { 0.08, 0.07, 0.06, 0.96 }, { 0.32, 0.27, 0.18, 1 })
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.columns = {}
    for column = 1, 4 do
        local text = row:CreateFontString(nil, "OVERLAY", column == 1 and "GameFontHighlight" or "GameFontHighlightSmall")
        text:SetPoint("LEFT", row, "LEFT", column == 1 and 12 or (column == 2 and 190 or (column == 3 and 345 or 500)), 0)
        text:SetWidth(column == 1 and 170 or 145)
        text:SetJustifyH("LEFT")
        row.columns[column] = text
    end
    return row
end

function Dashboard:Create()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", "iRaceLockedConnectionFrame", UIParent, "BackdropTemplate")
    frame:SetSize(900, 590)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    setBackdrop(frame, { 0.025, 0.022, 0.018, 0.98 }, { 0.46, 0.37, 0.20, 1 })
    frame:Hide()
    tinsert(UISpecialFrames, frame:GetName())
    self.frame = frame

    local titleBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    titleBar:SetPoint("TOPLEFT", 12, -12)
    titleBar:SetPoint("TOPRIGHT", -12, -12)
    titleBar:SetHeight(54)
    setBackdrop(titleBar, { 0.10, 0.07, 0.035, 0.98 }, { 0.55, 0.41, 0.17, 1 })
    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -11)
    title:SetText(iRL.DisplayName)
    title:SetTextColor(unpack(ORANGE))
    frame.status = titleBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetPoint("BOTTOM", 0, 9)
    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", 3, 3)

    local sidebar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", 15, -77)
    sidebar:SetPoint("BOTTOMLEFT", 15, 16)
    sidebar:SetWidth(174)
    setBackdrop(sidebar, { 0.10, 0.065, 0.03, 0.98 }, { 0.54, 0.40, 0.16, 1 })
    local sideTitle = sidebar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sideTitle:SetPoint("TOPLEFT", 14, -14)
    sideTitle:SetText("Guild Connection")
    sideTitle:SetTextColor(unpack(ORANGE))
    frame.tabs = {}
    local labels = { "Overview", "Verification", "Champions", "Leaderboard" }
    for index, label in ipairs(labels) do
        local tab = CreateFrame("Button", nil, sidebar, "BackdropTemplate")
        tab:SetSize(146, 30)
        tab:SetPoint("TOPLEFT", 14, -((index - 1) * 36 + 43))
        setBackdrop(tab, { 0.08, 0.06, 0.04, 0.96 }, { 0.32, 0.25, 0.16, 1 })
        tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        tab.label:SetPoint("LEFT", 10, 0)
        tab.label:SetText(label)
        tab.tabName = label
        tab:SetScript("OnClick", function(button)
            frame.tab = button.tabName
            Dashboard:Refresh()
        end)
        frame.tabs[label] = tab
    end
    local refreshButton = CreateFrame("Button", nil, sidebar, "UIPanelButtonTemplate")
    refreshButton:SetSize(146, 25)
    refreshButton:SetPoint("BOTTOM", 0, 16)
    refreshButton:SetText("Refresh guild roster")
    refreshButton:SetScript("OnClick", function() iRL:RefreshGuildRoster(); iRL:SendHello(); Dashboard:Refresh() end)

    local main = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    main:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 12, 0)
    main:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 16)
    setBackdrop(main, { 0.055, 0.047, 0.038, 0.98 }, { 0.46, 0.37, 0.21, 1 })
    frame.main = main
    frame.title = main:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", 15, -14)
    frame.title:SetTextColor(unpack(ORANGE))
    frame.subtitle = main:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -5)
    frame.subtitle:SetPoint("RIGHT", main, "RIGHT", -20, 0)
    frame.subtitle:SetJustifyH("LEFT")
    frame.headers = {}
    for column = 1, 4 do
        local text = main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("TOPLEFT", main, "TOPLEFT", column == 1 and 13 or (column == 2 and 191 or (column == 3 and 346 or 501)), -62)
        text:SetTextColor(unpack(ORANGE))
        frame.headers[column] = text
    end
    local scroll = CreateFrame("ScrollFrame", nil, main, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", main, "TOPLEFT", 14, -82)
    scroll:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -31, 14)
    frame.scroll = scroll
    frame.content = CreateFrame("Frame", nil, scroll)
    frame.content:SetWidth(651)
    frame.content:SetHeight(1)
    scroll:SetScrollChild(frame.content)
    frame.rows = {}
    frame.tab = "Overview"
    return frame
end

local function setHeaders(frame, values)
    for index = 1, 4 do frame.headers[index]:SetText(values[index] or "") end
end

local function setRow(frame, index, values, color, onClick)
    local row = frame.rows[index]
    if not row then row = makeRow(frame.content, index); frame.rows[index] = row end
    for column = 1, 4 do
        row.columns[column]:SetText(values[column] or "")
        row.columns[column]:SetTextColor(unpack(column == 1 and (color or ORANGE) or GRAY))
    end
    row:SetScript("OnClick", onClick)
    row:Show()
end

local function classSummary(classes)
    local list = {}
    for class, count in pairs(classes or {}) do list[#list + 1] = class .. " " .. count end
    table.sort(list)
    return table.concat(list, ", ")
end

function Dashboard:Refresh()
    local frame = self:Create()
    local connection = iRL:GetConnection()
    frame.status:SetText(connection and (iRL.Colors.Green .. "Connected: " .. iRL.Colors.Reset .. connection.guildName) or (iRL.Colors.Red .. "No guild connection" .. iRL.Colors.Reset))
    for name, tab in pairs(frame.tabs) do
        local active = name == frame.tab
        tab:SetBackdropColor(active and 0.24 or 0.08, active and 0.16 or 0.06, active and 0.04 or 0.04, 0.96)
        tab.label:SetTextColor(unpack(active and ORANGE or GRAY))
    end
    local count = 0
    if frame.tab == "Overview" then
        frame.title:SetText("Faction race overview")
        frame.subtitle:SetText("A guild-level view of every race represented in this connection. No group or language behaviour is enforced by iRC.")
        setHeaders(frame, { "Race", "Members / Avg. level", "iRC / Self-Found", "Class mix" })
        for _, group in ipairs(iRL:GetRaceOverview()) do
            count = count + 1
            setRow(frame, count, { group.race .. " (" .. group.faction .. ")", group.members .. " / " .. group.averageLevel, group.addonUsers .. " / " .. group.selfFound, classSummary(group.classes) }, ORANGE)
        end
    elseif frame.tab == "Verification" then
        frame.title:SetText("Guild verification")
        frame.subtitle:SetText("iRC and Self-Found values are reported only by members using iRacelockConnection. Unknown means no current iRC profile has been received.")
        setHeaders(frame, { "Member", "Race / Class", "Level / iRC", "Self-Found / Points" })
        for _, member in ipairs(iRL:GetGuildRosterRows()) do
            count = count + 1
            local addon = member.profile and ("v" .. (member.addonVersion or "?")) or "Not detected"
            local selfFound = member.profile and (member.selfFound and "Active" or "Inactive") or "Unknown"
            local selectedMember = member
            setRow(frame, count, { member.name, member.race .. " / " .. member.class, member.level .. " / " .. addon, selfFound .. " / " .. member.points }, member.profile and GREEN or GRAY, function()
                if selectedMember.profile then iRL.AchievementsUI:Open(selectedMember.name); iRL:RequestInspection(selectedMember.name) end
            end)
        end
    elseif frame.tab == "Champions" then
        local _, race = UnitRace("player")
        frame.title:SetText("Champions of " .. (race or "your race"))
        frame.subtitle:SetText("Guild members of your current race, ranked by level and then iRacelockConnection achievement points.")
        setHeaders(frame, { "Champion", "Class", "Level", "iRC points" })
        for _, member in ipairs(iRL:GetChampions()) do
            count = count + 1
            local selectedMember = member
            setRow(frame, count, { member.name, member.class, tostring(member.level), member.profile and tostring(member.points) or "Not detected" }, member.profile and GREEN or ORANGE, function()
                if selectedMember.profile then iRL.AchievementsUI:Open(selectedMember.name); iRL:RequestInspection(selectedMember.name) end
            end)
        end
    else
        frame.title:SetText("Connection leaderboard")
        frame.subtitle:SetText("Ranks iRC members by iRacelockConnection points, then level. Statistics are tracked locally and shared by iRC only.")
        setHeaders(frame, { "Member", "Points / Level", "Enemies / Bosses", "Jumps" })
        for _, member in ipairs(iRL:GetLeaderboard()) do
            count = count + 1
            local stats = member.statistics or {}
            local selectedMember = member
            setRow(frame, count, { member.name, member.points .. " / " .. member.level, (stats.enemiesSlain or 0) .. " / " .. (stats.dungeonBosses or 0), tostring(stats.jumps or 0) }, GREEN, function()
                iRL.AchievementsUI:Open(selectedMember.name)
                if iRL:NormalizeName(selectedMember.name) ~= iRL:NormalizeName(iRL:GetPlayerName()) then iRL:RequestInspection(selectedMember.name) end
            end)
        end
    end
    for index = count + 1, #frame.rows do frame.rows[index]:Hide() end
    frame.content:SetHeight(math.max(1, count * 53))
    frame.scroll:SetVerticalScroll(0)
end

function Dashboard:Open()
    local frame = self:Create()
    iRL:RefreshGuildRoster()
    self:Refresh()
    frame:Show()
end

function Dashboard:RefreshIfShown()
    if self.frame and self.frame:IsShown() then self:Refresh() end
end

function iRL:OpenConnectionDashboard()
    Dashboard:Open()
end
