local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local Dashboard = {}
iRC.ConnectionDashboard = Dashboard

local ORANGE = iRC.ColorValues.Orange
local GREEN = iRC.ColorValues.Green
local GRAY = iRC.ColorValues.Gray
local RED = { 1, 0.25, 0.18 }
local COLUMN_X = { 14, 162, 305, 457, 603 }
local COLUMN_WIDTH = { 138, 133, 142, 136, 118 }

local function sourceLabel(source)
    if source == "iRC" then return iRC.Colors.Green .. "iRC" .. iRC.Colors.Reset end
    local compatibleSource = type(source) == "string" and source:match("^iRC %+ (.+)$")
    if compatibleSource then
        return iRC.Colors.Green .. "iRC" .. iRC.Colors.Reset .. " + " .. iRC.Colors.Red .. compatibleSource .. iRC.Colors.Reset
    end
    return iRC.Colors.Red .. (source or "RaceLocked") .. iRC.Colors.Reset
end

local function displayMemberName(name)
    if type(name) ~= "string" then return "Unknown" end
    local characterName, realmName = name:match("^(.+)%-(.+)$")
    local playerRealm = GetRealmName and GetRealmName() or nil
    if characterName and realmName and playerRealm and string.lower(realmName) == string.lower(playerRealm) then
        return characterName
    end
    return name
end

local SELF_FOUND_HISTORY_LABELS = {
    VERIFIED = "Verified",
    TRACKED = "Tracked",
    BROKEN = "Broken",
    LEVEL_60_EXCEPTION = "Lv60 exception",
    UNVERIFIED = "Unverified",
}

local function setBackdrop(frame, background, border)
    frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(unpack(background))
    frame:SetBackdropBorderColor(unpack(border))
end

local function makeRow(parent, index)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(54)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * 60))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -((index - 1) * 60))
    setBackdrop(row, { 0.08, 0.07, 0.06, 0.96 }, { 0.32, 0.27, 0.18, 1 })
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.columns = {}
    for column = 1, 5 do
        local text = row:CreateFontString(nil, "OVERLAY", column == 1 and "GameFontHighlight" or "GameFontHighlightSmall")
        text:SetPoint("LEFT", row, "LEFT", COLUMN_X[column], 0)
        text:SetWidth(COLUMN_WIDTH[column])
        text:SetJustifyH("LEFT")
        row.columns[column] = text
    end
    return row
end

local function makeSummaryCard(parent)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    setBackdrop(card, { 0.075, 0.06, 0.045, 0.98 }, { 0.42, 0.33, 0.18, 1 })
    card.label = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.label:SetPoint("TOPLEFT", 10, -8)
    card.label:SetPoint("TOPRIGHT", -10, -8)
    card.label:SetJustifyH("CENTER")
    card.label:SetTextColor(unpack(GRAY))
    card.value = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    card.value:SetPoint("BOTTOM", 0, 8)
    return card
end

function Dashboard:Create()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", "iRacelockConnectionConnectionFrame", UIParent, "BackdropTemplate")
    frame:SetSize(1020, 650)
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
    title:SetText(iRC.DisplayName)
    title:SetTextColor(unpack(ORANGE))
    frame.status = titleBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetPoint("BOTTOM", 0, 9)
    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", 3, 3)
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    local sidebar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", 15, -77)
    sidebar:SetPoint("BOTTOMLEFT", 15, 16)
    sidebar:SetWidth(194)
    setBackdrop(sidebar, { 0.10, 0.065, 0.03, 0.98 }, { 0.54, 0.40, 0.16, 1 })
    local sideTitle = sidebar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sideTitle:SetPoint("TOPLEFT", 14, -14)
    sideTitle:SetText("Guild Connection")
    sideTitle:SetTextColor(unpack(ORANGE))
    frame.tabs = {}
    local labels = { "Overview", "Verification", "Champions", "Leaderboard" }
    for index, label in ipairs(labels) do
        local tab = CreateFrame("Button", nil, sidebar, "BackdropTemplate")
        tab:SetSize(166, 34)
        tab:SetPoint("TOPLEFT", 14, -((index - 1) * 36 + 43))
        setBackdrop(tab, { 0.08, 0.06, 0.04, 0.96 }, { 0.32, 0.25, 0.16, 1 })
        tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        tab.label:SetPoint("LEFT", 10, 0)
        tab.label:SetText(label)
        tab.tabName = label
        tab:SetScript("OnClick", function(button)
            if frame.tab ~= button.tabName then frame.sortKey = nil end
            frame.tab = button.tabName
            Dashboard:Refresh()
        end)
        frame.tabs[label] = tab
    end
    local refreshButton = CreateFrame("Button", nil, sidebar, "UIPanelButtonTemplate")
    refreshButton:SetSize(166, 27)
    refreshButton:SetPoint("BOTTOM", 0, 16)
    refreshButton:SetText("Refresh guild roster")
    refreshButton:SetScript("OnClick", function()
        iRC:RefreshGuildRoster()
        iRC:SendHello()
        iRC:RequestGuildPresence()
        Dashboard:Refresh()
    end)

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
    frame.subtitle:SetWordWrap(true)
    frame.summaryCards = {}
    for index = 1, 4 do
        local card = makeSummaryCard(main)
        card:SetSize(172, 54)
        card:SetPoint("TOPLEFT", main, "TOPLEFT", 15 + (index - 1) * 178, -66)
        frame.summaryCards[index] = card
    end
    frame.filterButtons, frame.filters, frame.headers = {}, {}, {}
    for index = 1, 4 do
        local button = CreateFrame("Button", nil, main, "UIPanelButtonTemplate")
        button:SetSize(124, 23)
        button:SetPoint("TOPLEFT", main, "TOPLEFT", 15 + (index - 1) * 130, -126)
        button:Hide()
        frame.filterButtons[index] = button
    end
    for column = 1, 5 do
        local button = CreateFrame("Button", nil, main)
        button:SetSize(COLUMN_WIDTH[column], 18)
        button:SetPoint("TOPLEFT", main, "TOPLEFT", COLUMN_X[column] + 1, -156)
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.text:SetAllPoints(button)
        button.text:SetJustifyH("LEFT")
        button.text:SetTextColor(unpack(ORANGE))
        button:SetScript("OnClick", function(self)
            if not self.sortKey then return end
            if frame.sortKey == self.sortKey then
                frame.sortAscending = not frame.sortAscending
            else
                frame.sortKey = self.sortKey
                frame.sortAscending = self.alphabetical and true or false
            end
            Dashboard:Refresh()
        end)
        frame.headers[column] = button
    end
    local scroll = CreateFrame("ScrollFrame", nil, main, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", main, "TOPLEFT", 14, -176)
    scroll:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -31, 14)
    frame.scroll = scroll
    frame.content = CreateFrame("Frame", nil, scroll)
    frame.content:SetWidth(722)
    frame.content:SetHeight(1)
    scroll:SetScrollChild(frame.content)
    frame.rows = {}
    frame.tab = "Overview"
    return frame
end

local function setHeaders(frame, values, sortKeys, defaultKey)
    if not frame.sortKey or frame.sortTab ~= frame.tab then
        frame.sortTab, frame.sortKey = frame.tab, defaultKey
        frame.sortAscending = defaultKey == "name" or defaultKey == "race" or defaultKey == "class" or defaultKey == "source"
    end
    for index = 1, 5 do
        local header = frame.headers[index]
        local key = sortKeys and sortKeys[index]
        header.sortKey = key
        header.alphabetical = key == "name" or key == "race" or key == "class" or key == "source"
        local indicator = key and key == frame.sortKey and (frame.sortAscending and " ▲" or " ▼") or ""
        header.text:SetText((values[index] or "") .. indicator)
        header:SetShown(key ~= nil)
    end
end

local function setFilters(frame, choices)
    local selected = frame.filters[frame.tab]
    local available = false
    for _, choice in ipairs(choices) do if choice.id == selected then available = true break end end
    if not available then selected = choices[1].id; frame.filters[frame.tab] = selected end
    for index, button in ipairs(frame.filterButtons) do
        local choice = choices[index]
        if choice then
            button:SetText(choice.label)
            button:SetEnabled(choice.id ~= selected)
            button:SetScript("OnClick", function()
                frame.filters[frame.tab] = choice.id
                Dashboard:Refresh()
            end)
            button:Show()
        else
            button:Hide()
        end
    end
    return selected
end

local function filterAndSort(frame, items, shouldInclude, valueFor)
    local filtered = {}
    for _, item in ipairs(items) do if shouldInclude(item) then filtered[#filtered + 1] = item end end
    table.sort(filtered, function(a, b)
        local first, second = valueFor(a, frame.sortKey), valueFor(b, frame.sortKey)
        if type(first) == "string" then first, second = string.lower(first), string.lower(tostring(second or "")) end
        if first == second then return tostring(a.name or a.race or "") < tostring(b.name or b.race or "") end
        if frame.sortAscending then return first < second end
        return first > second
    end)
    return filtered
end

local function setSummaryCards(frame, cards)
    for index, card in ipairs(frame.summaryCards) do
        local item = cards[index] or {}
        card.label:SetText(item.label or "")
        card.value:SetText(item.value or "")
        local color = item.color or ORANGE
        card.value:SetTextColor(unpack(color))
        card:SetBackdropBorderColor(color[1], color[2], color[3], 0.72)
        card:Show()
    end
end

local function setRow(frame, index, values, color, onClick)
    local row = frame.rows[index]
    if not row then row = makeRow(frame.content, index); frame.rows[index] = row end
    for column = 1, 5 do
        row.columns[column]:SetText(values[column] or "")
        row.columns[column]:SetTextColor(unpack(column == 1 and (color or ORANGE) or GRAY))
    end
    local border = color or ORANGE
    row:SetBackdropBorderColor(border[1], border[2], border[3], 0.62)
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
    local connection = iRC:GetConnection()
    frame.status:SetText(connection and (iRC.Colors.Green .. "Connected: " .. iRC.Colors.Reset .. connection.guildName) or (iRC.Colors.Red .. "No guild connection" .. iRC.Colors.Reset))
    for name, tab in pairs(frame.tabs) do
        local active = name == frame.tab
        tab:SetBackdropColor(active and 0.24 or 0.08, active and 0.16 or 0.06, active and 0.04 or 0.04, 0.96)
        tab.label:SetTextColor(unpack(active and ORANGE or GRAY))
    end
    local count = 0
    if frame.tab == "Overview" then
        local groups = iRC:GetRaceOverview()
        local members, addonUsers, selfFound, factions = 0, 0, 0, 0
        for _, group in ipairs(groups) do
            members = members + (group.members or 0)
            addonUsers = addonUsers + (group.addonUsers or 0)
            selfFound = selfFound + (group.selfFound or 0)
            factions = factions + 1
        end
        setSummaryCards(frame, {
            { label = "Guild members", value = tostring(members), color = ORANGE },
            { label = "Live addon users", value = tostring(addonUsers), color = GREEN },
            { label = "Self-Found active", value = tostring(selfFound), color = GREEN },
            { label = "Races represented", value = tostring(factions), color = ORANGE },
        })
        local filter = setFilters(frame, {
            { id = "all", label = "All races" }, { id = "Horde", label = "Horde" }, { id = "Alliance", label = "Alliance" },
        })
        frame.title:SetText("Faction race overview")
        frame.subtitle:SetText("A guild-level snapshot of each race represented in your guild connection.")
        setHeaders(frame, { "Race", "Faction", "Members / Avg. level", "Addon / Self-Found", "Class mix" }, { "race", "faction", "members", "addonUsers", "classes" }, "members")
        groups = filterAndSort(frame, groups, function(group) return filter == "all" or group.faction == filter end, function(group, key)
            if key == "race" then return group.race or "" end
            if key == "faction" then return group.faction or "" end
            if key == "addonUsers" then return group.addonUsers or 0 end
            if key == "classes" then return classSummary(group.classes) end
            return group.members or 0
        end)
        for _, group in ipairs(groups) do
            count = count + 1
            setRow(frame, count, { group.race, group.faction, group.members .. " / " .. group.averageLevel, group.addonUsers .. " / " .. group.selfFound, classSummary(group.classes) }, ORANGE)
        end
    elseif frame.tab == "Verification" then
        local verified, compatible, attention, offline = 0, 0, 0, 0
        local members = iRC:GetGuildRosterRows()
        for _, member in ipairs(members) do
            local state = member.verification and member.verification.state
            if state == "verified" then verified = verified + 1
            elseif state == "compatible" then compatible = compatible + 1
            elseif state == "offline" then offline = offline + 1
            else attention = attention + 1 end
        end
        setSummaryCards(frame, {
            { label = "Verified", value = tostring(verified), color = GREEN },
            { label = "Compatible", value = tostring(compatible), color = ORANGE },
            { label = "Needs attention", value = tostring(attention), color = RED },
            { label = "Offline", value = tostring(offline), color = GRAY },
        })
        local filter = setFilters(frame, {
            { id = "all", label = "All members" }, { id = "attention", label = "Needs attention" }, { id = "verified", label = "Verified" }, { id = "compatible", label = "Compatible" },
        })
        frame.title:SetText("Guild verification")
        frame.subtitle:SetText("Live presence status. Missing or stale online members are handled by the officer notification system.")
        setHeaders(frame, { "Member", "Race / Class", "Level", "Live status", "Self-Found / Points" }, { "name", "race", "level", "status", "points" }, "name")
        members = filterAndSort(frame, members, function(member)
            local state = member.verification and member.verification.state or "missing"
            return filter == "all" or state == filter or (filter == "attention" and state ~= "verified" and state ~= "compatible" and state ~= "offline")
        end, function(member, key)
            if key == "name" then return member.name or "" end
            if key == "race" then return (member.race or "") .. (member.class or "") end
            if key == "status" then return member.verification and member.verification.state or "missing" end
            if key == "points" then return member.points or 0 end
            return member.level or 0
        end)
        for _, member in ipairs(members) do
            count = count + 1
            local verification = member.verification or { state = "missing", label = "Addon not detected" }
            local addon = member.profile and (sourceLabel("iRC") .. " v" .. (member.addonVersion or "?") .. " · " .. verification.label)
                or (member.compatibility and (sourceLabel(member.source) .. " · " .. verification.label))
                or verification.label
            local evidence = member.profile and member.profile.selfFoundEvidence or nil
            local historyStatus = evidence and evidence.status or "UNVERIFIED"
            local historyLabel = SELF_FOUND_HISTORY_LABELS[historyStatus] or "Unverified"
            local selfFound = member.profile and ((member.selfFound and "Active" or "Inactive") .. " / " .. historyLabel)
                or (member.compatibility and (member.selfFound and "Active (ForkEU)" or "Inactive (ForkEU)"))
                or "Unknown"
            local selectedMember = member
            local color = verification.state == "verified" and GREEN or (verification.state == "compatible" and RED or (verification.state == "offline" and GRAY or RED))
            setRow(frame, count, { displayMemberName(member.name), member.race .. " / " .. member.class, tostring(member.level), addon, selfFound .. " / " .. member.points }, color, function()
                if selectedMember.profile then iRC.AchievementsUI:Open(selectedMember.name); iRC:RequestInspection(selectedMember.name) end
            end)
        end
    elseif frame.tab == "Champions" then
        local _, race = UnitRace("player")
        local champions = iRC:GetChampions()
        local top = champions[1]
        setSummaryCards(frame, {
            { label = "Your race", value = race or "Unknown", color = ORANGE },
            { label = "Champions", value = tostring(#champions), color = GREEN },
            { label = "Top level", value = tostring(top and top.level or 0), color = ORANGE },
            { label = "Top achievement points", value = tostring(top and top.points or 0), color = ORANGE },
        })
        local filter = setFilters(frame, {
            { id = "all", label = "All sources" }, { id = "irc", label = "iRC only" }, { id = "compatible", label = "Compatible" },
        })
        frame.title:SetText("Champions of " .. (race or "your race"))
        frame.subtitle:SetText("Guild members of your race, ranked by level and achievement points.")
        setHeaders(frame, { "Champion", "Class", "Level", "Achievement Points", "Source" }, { "name", "class", "level", "points", "source" }, "level")
        champions = filterAndSort(frame, champions, function(member)
            return filter == "all" or (filter == "irc" and member.profile) or (filter == "compatible" and member.compatibility and not member.profile)
        end, function(member, key)
            if key == "name" then return member.name or "" end
            if key == "class" then return member.class or "" end
            if key == "points" then return member.points or 0 end
            if key == "source" then return member.source or "" end
            return member.level or 0
        end)
        for _, member in ipairs(champions) do
            count = count + 1
            local selectedMember = member
            setRow(frame, count, { "#" .. count .. " " .. displayMemberName(member.name), member.class, tostring(member.level), tostring(member.points or 0), (member.profile or member.compatibility) and sourceLabel(member.source or "iRC") or "Not detected" }, member.profile and GREEN or (member.compatibility and RED or ORANGE), function()
                if selectedMember.profile then iRC.AchievementsUI:Open(selectedMember.name); iRC:RequestInspection(selectedMember.name) end
            end)
        end
    else
        local leaderboard = iRC:GetLeaderboard()
        local top = leaderboard[1]
        local verified, compatible = 0, 0
        for _, member in ipairs(leaderboard) do
            if member.profile then verified = verified + 1 elseif member.compatibility then compatible = compatible + 1 end
        end
        setSummaryCards(frame, {
            { label = "Ranked members", value = tostring(#leaderboard), color = ORANGE },
            { label = "iRC profiles", value = tostring(verified), color = GREEN },
            { label = "Compatible profiles", value = tostring(compatible), color = RED },
            { label = "Top achievement points", value = tostring(top and top.points or 0), color = ORANGE },
        })
        local filter = setFilters(frame, {
            { id = "all", label = "All sources" }, { id = "irc", label = "iRC only" }, { id = "compatible", label = "Compatible" },
        })
        frame.title:SetText("Connection leaderboard")
        frame.subtitle:SetText("Guild rankings with source-aware progress data. A character is represented once.")
        setHeaders(frame, { "Name", "Level", "Achievement Points", "Guild", "Source" }, { "name", "level", "points", "guild", "source" }, "points")
        local connection = iRC:GetConnection()
        local guildName = connection and connection.guildName or "Unknown"
        leaderboard = filterAndSort(frame, leaderboard, function(member)
            return filter == "all" or (filter == "irc" and member.profile) or (filter == "compatible" and member.compatibility and not member.profile)
        end, function(member, key)
            local score = member.leaderboard or {}
            if key == "name" then return member.name or "" end
            if key == "guild" then return guildName end
            if key == "source" then return score.source or member.source or "" end
            if key == "points" then return score.points or member.points or 0 end
            return score.level or member.level or 0
        end)
        for _, member in ipairs(leaderboard) do
            count = count + 1
            local score = member.leaderboard or {}
            local selectedMember = member
            setRow(frame, count, { "#" .. count .. " " .. displayMemberName(member.name), tostring(score.level or member.level or 1), tostring(score.points or member.points or 0), guildName, sourceLabel(score.source or "iRC") }, member.profile and GREEN or RED, function()
                if selectedMember.profile then
                    iRC.AchievementsUI:Open(selectedMember.name)
                    if iRC:NormalizeName(selectedMember.name) ~= iRC:NormalizeName(iRC:GetPlayerName()) then iRC:RequestInspection(selectedMember.name) end
                end
            end)
        end
    end
    for index = count + 1, #frame.rows do frame.rows[index]:Hide() end
    frame.content:SetHeight(math.max(1, count * 60))
    frame.scroll:SetVerticalScroll(0)
end

function Dashboard:Open()
    local frame = self:Create()
    if iRC.CloseWindowsExcept then iRC:CloseWindowsExcept(frame) end
    iRC:RefreshGuildRoster()
    self:Refresh()
    frame:Show()
end

function Dashboard:Toggle()
    local frame = self:Create()
    if frame:IsShown() then
        frame:Hide()
    else
        self:Open()
    end
end

function Dashboard:RefreshIfShown()
    if self.frame and self.frame:IsShown() then self:Refresh() end
end

function iRC:OpenConnectionDashboard()
    Dashboard:Open()
end
