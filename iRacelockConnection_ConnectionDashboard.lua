local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local Dashboard = {}
iRC.ConnectionDashboard = Dashboard

local ORANGE = iRC.ColorValues.Orange
local GREEN = iRC.ColorValues.Green
local GRAY = iRC.ColorValues.Gray
local RED = { 1, 0.25, 0.18 }
local COLUMN_X = { 14, 139, 254, 309, 499, 624 }
local COLUMN_WIDTH = { 115, 105, 45, 180, 115, 75 }
local OVERVIEW_COLUMN_X = { 14, 164, 324, 484 }
local OVERVIEW_COLUMN_WIDTH = { 136, 146, 146, 224 }

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

local function formatAttentionTimer(startedAt)
    if not startedAt then return nil end
    local elapsed = math.max(0, time() - startedAt)
    local hours = math.floor(elapsed / 3600)
    local minutes = math.floor((elapsed % 3600) / 60)
    local duration = hours > 0 and (hours .. "h " .. minutes .. "m") or (minutes .. "m")
    return "Since " .. date("%H:%M", startedAt) .. " · " .. duration
end

local function setBackdrop(frame, background, border)
    frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(unpack(background))
    frame:SetBackdropBorderColor(unpack(border))
end

local function makeRow(parent, index)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:EnableMouse(true)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetHeight(54)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * 60))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -((index - 1) * 60))
    setBackdrop(row, { 0.08, 0.07, 0.06, 0.96 }, { 0.32, 0.27, 0.18, 1 })
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.columns = {}
    local columnX = parent.columnX or COLUMN_X
    local columnWidth = parent.columnWidth or COLUMN_WIDTH
    for column = 1, #COLUMN_X do
        local text = row:CreateFontString(nil, "OVERLAY", column == 1 and "GameFontHighlight" or "GameFontHighlightSmall")
        text:SetPoint("LEFT", row, "LEFT", columnX[column] or COLUMN_X[column], 0)
        text:SetWidth(columnWidth[column] or COLUMN_WIDTH[column])
        text:SetJustifyH(column == 1 and "LEFT" or "CENTER")
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
    frame.attentionTimerElapsed = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        if not self:IsShown() or (self.tab ~= "Verification" and self.tab ~= "Incidents") then return end
        self.attentionTimerElapsed = self.attentionTimerElapsed + elapsed
        if self.attentionTimerElapsed >= 1 then
            self.attentionTimerElapsed = 0
            Dashboard:RenderVisibleRows()
        end
    end)
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
    sideTitle:SetText(iRC:Text("DASHBOARD_VERIFICATION_TITLE"))
    sideTitle:SetTextColor(unpack(ORANGE))
    frame.tabs, frame.tabOrder = {}, {}
    local labels = {
        { name = "Overview" }, { name = "Verification" },
        { name = "Incidents", label = iRC:Text("INCIDENT_TAB"), adminOnly = true },
    }
    for index, item in ipairs(labels) do
        local label = item.name
        local tab = CreateFrame("Button", nil, sidebar, "BackdropTemplate")
        tab:SetSize(item.adminOnly and 156 or 166, 34)
        tab:SetPoint("TOPLEFT", item.adminOnly and 24 or 14, -((index - 1) * 36 + 43))
        setBackdrop(tab, { 0.08, 0.06, 0.04, 0.96 }, { 0.32, 0.25, 0.16, 1 })
        tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        tab.label:SetPoint("LEFT", 10, 0)
        tab.label:SetText((item.adminOnly and "- " or "") .. (item.label or label))
        tab.tabName = label
        tab.adminOnly = item.adminOnly
        tab:SetScript("OnClick", function(button)
            if frame.tab ~= button.tabName then frame.sortKey = nil end
            frame.tab = button.tabName
            Dashboard:Refresh()
        end)
        frame.tabs[label] = tab
        frame.tabOrder[#frame.tabOrder + 1] = tab
    end
    local refreshButton = CreateFrame("Button", nil, sidebar, "UIPanelButtonTemplate")
    refreshButton:SetSize(166, 27)
    refreshButton:SetPoint("BOTTOM", 0, 16)
    refreshButton:SetText("Refresh verification")
    refreshButton:SetScript("OnClick", function()
        iRC:RefreshGuildRoster()
        iRC:SendHello()
        iRC:RequestGuildPresence()
        if iRC.Compatibility and iRC.Compatibility.BroadcastAll then
            iRC.Compatibility:BroadcastAll()
        end
        if iRC.RaceGrid then iRC.RaceGrid:PublishFromClick() end
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
        local button = CreateFrame("Button", nil, main, "BackdropTemplate")
        button:SetSize(160, 27)
        button:SetPoint("TOPLEFT", main, "TOPLEFT", 15 + (index - 1) * 166, -124)
        setBackdrop(button, { 0.055, 0.045, 0.035, 0.96 }, { 0.28, 0.23, 0.16, 0.9 })
        button.activeGlow = button:CreateTexture(nil, "BACKGROUND")
        button.activeGlow:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
        button.activeGlow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
        button.activeGlow:SetColorTexture(0, 0, 0, 0)
        button.attentionGlow = button:CreateTexture(nil, "BACKGROUND", nil, -1)
        button.attentionGlow:SetPoint("TOPLEFT", button, "TOPLEFT", -3, 3)
        button.attentionGlow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 3, -3)
        button.attentionGlow:SetColorTexture(1, 0.08, 0.02, 1)
        button.attentionGlow:SetAlpha(0)
        button.attentionAnimation = button.attentionGlow:CreateAnimationGroup()
        button.attentionAnimation:SetLooping("BOUNCE")
        local pulse = button.attentionAnimation:CreateAnimation("Alpha")
        pulse:SetFromAlpha(0.12)
        pulse:SetToAlpha(0.72)
        pulse:SetDuration(0.65)
        pulse:SetSmoothing("IN_OUT")
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        button.text:SetPoint("CENTER")
        button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
        button.highlight:SetAllPoints(button)
        button.highlight:SetColorTexture(1, 0.72, 0.22, 0.10)
        button:Hide()
        frame.filterButtons[index] = button
    end
    for column = 1, #COLUMN_X do
        local button = CreateFrame("Button", nil, main)
        button:SetSize(COLUMN_WIDTH[column], 18)
        button:SetPoint("TOPLEFT", main, "TOPLEFT", COLUMN_X[column] + 1, -156)
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.text:SetAllPoints(button)
        button.text:SetJustifyH(column == 1 and "LEFT" or "CENTER")
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
    frame.rowData = {}
    frame.memberMenu = CreateFrame("Frame", "iRCMemberManagementMenu", frame, "BackdropTemplate")
    frame.memberMenu:SetSize(336, 160)
    frame.memberMenu:SetFrameStrata("DIALOG")
    frame.memberMenu:SetClampedToScreen(true)
    setBackdrop(frame.memberMenu, { 0.035, 0.028, 0.02, 0.99 }, { ORANGE[1], ORANGE[2], ORANGE[3], 1 })
    frame.memberMenu:Hide()
    local menuTitle = frame.memberMenu:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    menuTitle:SetPoint("TOPLEFT", 16, -12)
    menuTitle:SetPoint("TOPRIGHT", -34, -12)
    menuTitle:SetJustifyH("LEFT")
    frame.memberMenu.title = menuTitle
    local menuHint = frame.memberMenu:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    menuHint:SetPoint("TOPLEFT", menuTitle, "BOTTOMLEFT", 0, -3)
    menuHint:SetText(iRC:Text("MEMBER_MENU_ACTION_HINT"))
    frame.memberMenu.hint = menuHint
    local menuClose = CreateFrame("Button", nil, frame.memberMenu, "UIPanelCloseButton")
    menuClose:SetPoint("TOPRIGHT", 4, 4)

    frame.memberReport = CreateFrame("Frame", "iRCGuildFoundReportFrame", frame, "BackdropTemplate")
    frame.memberReport:SetSize(640, 290)
    frame.memberReport:SetPoint("CENTER", frame, "CENTER", 85, 0)
    frame.memberReport:SetFrameStrata("DIALOG")
    setBackdrop(frame.memberReport, { 0.035, 0.028, 0.02, 0.99 }, { ORANGE[1], ORANGE[2], ORANGE[3], 1 })
    local reportShade = frame.memberReport:CreateTexture(nil, "BACKGROUND", nil, -8)
    reportShade:SetPoint("TOPLEFT", 4, -4)
    reportShade:SetPoint("BOTTOMRIGHT", -4, 4)
    reportShade:SetColorTexture(0, 0, 0, 0.96)
    frame.memberReport:Hide()
    local reportTitle = frame.memberReport:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    reportTitle:SetPoint("TOPLEFT", 18, -17)
    reportTitle:SetPoint("TOPRIGHT", -42, -17)
    reportTitle:SetJustifyH("LEFT")
    reportTitle:SetTextColor(unpack(ORANGE))
    reportTitle:SetText(iRC:Text("GF_REPORT_TITLE"))
    local reportClose = CreateFrame("Button", nil, frame.memberReport, "UIPanelCloseButton")
    reportClose:SetPoint("TOPRIGHT", 4, 4)
    local reportBody = frame.memberReport:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    reportBody:SetPoint("TOPLEFT", 18, -52)
    reportBody:SetPoint("BOTTOMRIGHT", -18, 18)
    reportBody:SetJustifyH("LEFT")
    reportBody:SetJustifyV("TOP")
    reportBody:SetWordWrap(true)
    frame.memberReport.body = reportBody

    local function statusWord(value, trueKey, falseKey)
        if value == nil then return iRC:Text("RL_STATUS_UNKNOWN") end
        return iRC:Text(value and trueKey or falseKey)
    end

    local function showGuildFoundReport(targetName)
        local status = iRC.RaceLockedSync and iRC.RaceLockedSync:GetStatus(targetName)
        local member
        for _, rosterMember in ipairs(iRC:GetGuildRosterRows()) do
            if iRC:NormalizeName(rosterMember.name) == iRC:NormalizeName(targetName) then member = rosterMember break end
        end
        local level = member and tonumber(member.level) or 0
        if member and level < 60 then
            frame.memberReport:SetSize(640, 190)
            reportTitle:SetText(iRC:Text("SF_REPORT_TITLE"))
            local liveState = member.verification and member.verification.state
            local hasSelfFoundStatus = liveState == "verified" or liveState == "compatible"
            local selfFoundStatus = not hasSelfFoundStatus and iRC:Text("GF_SELF_FOUND_UNKNOWN")
                or iRC:Text(member.selfFound and "GF_SELF_FOUND_ACTIVE" or "GF_SELF_FOUND_INACTIVE")
            reportBody:SetText(table.concat({
                iRC:Text("GF_REPORT_MEMBER", displayMemberName(targetName)),
                iRC:Text("GF_REPORT_LEVEL", level),
                iRC:Text("GF_REPORT_SOURCE", member.source or iRC:Text("RL_STATUS_UNKNOWN")),
                "",
                iRC:Text("GF_REPORT_SELF_FOUND", selfFoundStatus),
            }, "\n"))
        elseif not status then
            frame.memberReport:SetSize(640, 190)
            reportTitle:SetText(iRC:Text("GF_REPORT_TITLE"))
            reportBody:SetText(iRC:Text("GF_REPORT_NO_DATA", displayMemberName(targetName)))
        else
            frame.memberReport:SetSize(640, 290)
            reportTitle:SetText(iRC:Text("GF_REPORT_TITLE"))
            local lines = {
                iRC:Text("GF_REPORT_MEMBER", displayMemberName(targetName)),
                iRC:Text("GF_REPORT_SOURCE", status.source or iRC:Text("RL_STATUS_UNKNOWN")),
                iRC:Text("GF_REPORT_RECEIVED", status.lastSeen and date("%Y-%m-%d %H:%M", status.lastSeen) or iRC:Text("RL_STATUS_UNKNOWN")),
                "",
                iRC:Text("GF_REPORT_RAW_VERIFIED", statusWord(status.rawVerified, "GF_HISTORY_VERIFIED", "GF_HISTORY_UNVERIFIED")),
                iRC:Text("GF_REPORT_RAW_CLEAN", statusWord(status.rawClean, "GF_GOLD_CLEAN", "GF_GOLD_FLAGGED")),
            }
            if status.tamperAt and status.tamperAt > 0 then
                lines[#lines + 1] = iRC.Colors.Red .. iRC:Text("GF_REPORT_DISCREPANCY", date("%Y-%m-%d %H:%M", status.tamperAt)) .. iRC.Colors.Reset
            end
            if status.gmTimestamp then
                lines[#lines + 1] = ""
                local gmVerified = status.gmVerified == nil and iRC:Text("RL_OVERRIDE_RESET")
                    or statusWord(status.gmVerified, "RL_VERIFIED", "RL_UNVERIFIED")
                local gmClean = status.gmClean == nil and iRC:Text("RL_OVERRIDE_RESET")
                    or statusWord(status.gmClean, "RL_CLEAN", "RL_FLAGGED")
                lines[#lines + 1] = iRC:Text("GF_REPORT_DECISION_VALUES", gmVerified, gmClean)
                lines[#lines + 1] = iRC:Text("GF_REPORT_DECISION_SOURCE", status.overrideSource or iRC:Text("RL_STATUS_UNKNOWN"), date("%Y-%m-%d %H:%M", status.gmTimestamp))
            end
            reportBody:SetText(table.concat(lines, "\n"))
        end
        frame.memberReport:Show()
    end

    local menuActions = {
        { group = "MEMBER_MENU_GROUP_DETAILS", label = "MEMBER_MENU_VIEW_REPORT", run = showGuildFoundReport },
        { group = "MEMBER_MENU_GROUP_CONTACT", label = "MEMBER_MENU_WHISPER_IRC", run = function(targetName)
            if SendChatMessage then SendChatMessage(iRC:Text("MEMBER_WHISPER_IRC"), "WHISPER", nil, targetName) end
        end },
        { group = "MEMBER_MENU_GROUP_CONTACT", label = "MEMBER_MENU_WHISPER_RACELOCKED", run = function(targetName)
            if SendChatMessage then SendChatMessage(iRC:Text("MEMBER_WHISPER_RACELOCKED"), "WHISPER", nil, targetName) end
        end },
        { group = "MEMBER_MENU_GROUP_CONTACT", label = "MEMBER_MENU_REQUEST_IRC", run = function(targetName)
            if iRC:IsGuildConnectionActive() then
                iRC:RequestInspection(targetName)
                iRC:Print(iRC:Text("MEMBER_REQUEST_SENT", displayMemberName(targetName)))
            end
        end },
        { group = "MEMBER_MENU_GROUP_DECISIONS", label = "MEMBER_MENU_APPROVE", gmOnly = true, maxLevelOnly = true, tone = "approve", run = function(targetName)
            iRC.RaceLockedSync:SetOverride(targetName, true, true)
        end },
        { group = "MEMBER_MENU_GROUP_DECISIONS", label = "MEMBER_MENU_UNVERIFY", gmOnly = true, maxLevelOnly = true, tone = "danger", run = function(targetName)
            iRC.RaceLockedSync:SetOverride(targetName, false, nil)
        end },
        { group = "MEMBER_MENU_GROUP_DECISIONS", label = "MEMBER_MENU_FLAG", gmOnly = true, maxLevelOnly = true, tone = "danger", run = function(targetName)
            iRC.RaceLockedSync:SetOverride(targetName, nil, false)
        end },
        { group = "MEMBER_MENU_GROUP_DECISIONS", label = "MEMBER_MENU_RESET", gmOnly = true, maxLevelOnly = true, tone = "reset", run = function(targetName)
            iRC.RaceLockedSync:SetOverride(targetName, nil, nil)
        end },
    }
    frame.memberMenu.actionButtons = {}
    frame.memberMenu.groupLabels = {}
    for _, action in ipairs(menuActions) do
        if not frame.memberMenu.groupLabels[action.group] then
            local groupLabel = frame.memberMenu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            groupLabel:SetText(iRC:Text(action.group))
            groupLabel:SetTextColor(unpack(ORANGE))
            frame.memberMenu.groupLabels[action.group] = groupLabel
        end
        local button = CreateFrame("Button", nil, frame.memberMenu, "BackdropTemplate")
        button:SetSize(304, 28)
        setBackdrop(button, { 0.07, 0.055, 0.04, 0.98 }, { 0.30, 0.24, 0.16, 1 })
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        button.text:SetPoint("LEFT", 12, 0)
        button.text:SetPoint("RIGHT", -10, 0)
        button.text:SetJustifyH("LEFT")
        button.text:SetText(iRC:Text(action.label))
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetPoint("TOPLEFT", 3, -3)
        highlight:SetPoint("BOTTOMRIGHT", -3, 3)
        highlight:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.16)
        button.runAction = action.run
        button.gmOnly = action.gmOnly
        button.maxLevelOnly = action.maxLevelOnly
        button.group = action.group
        button.tone = action.tone
        button:SetScript("OnClick", function(self)
            local targetName = frame.memberMenu.targetName
            frame.memberMenu:Hide()
            if targetName then self.runAction(targetName) end
        end)
        frame.memberMenu.actionButtons[#frame.memberMenu.actionButtons + 1] = button
    end
    scroll:HookScript("OnVerticalScroll", function() Dashboard:RenderVisibleRows() end)
    frame.tab = "Overview"
    return frame
end

local function setHeaders(frame, values, sortKeys, defaultKey, columnX, columnWidth, headerY)
    columnX, columnWidth = columnX or COLUMN_X, columnWidth or COLUMN_WIDTH
    headerY = headerY or -156
    frame.content.columnX, frame.content.columnWidth = columnX, columnWidth
    frame.scroll:ClearAllPoints()
    frame.scroll:SetPoint("TOPLEFT", frame.main, "TOPLEFT", 14, headerY - 20)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame.main, "BOTTOMRIGHT", -31, 14)
    if not frame.sortKey or frame.sortTab ~= frame.tab then
        frame.sortTab, frame.sortKey = frame.tab, defaultKey
        frame.sortAscending = defaultKey == "name" or defaultKey == "race" or defaultKey == "class" or defaultKey == "source"
    end
    for index = 1, #COLUMN_X do
        local header = frame.headers[index]
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", frame.main, "TOPLEFT", (columnX[index] or COLUMN_X[index]) + 1, headerY)
        header:SetWidth(columnWidth[index] or COLUMN_WIDTH[index])
        header.text:SetJustifyH(index == 1 and "LEFT" or "CENTER")
        for _, row in ipairs(frame.rows) do
            local columnText = row.columns[index]
            columnText:ClearAllPoints()
            columnText:SetPoint("LEFT", row, "LEFT", columnX[index] or COLUMN_X[index], 0)
            columnText:SetWidth(columnWidth[index] or COLUMN_WIDTH[index])
        end
        local key = sortKeys and sortKeys[index]
        header.sortKey = key
        header.alphabetical = key == "name" or key == "race" or key == "class" or key == "source"
        local indicator = key and key == frame.sortKey and (frame.sortAscending and " ^" or " v") or ""
        header.text:SetText((values[index] or "") .. indicator)
        header:SetShown(key ~= nil)
    end
end

local function setFilters(frame, choices)
    if #choices == 0 then
        for _, button in ipairs(frame.filterButtons) do
            button.attentionAnimation:Stop()
            button.attentionGlow:SetAlpha(0)
            button:Hide()
        end
        return "all"
    end
    local selected = frame.filters[frame.tab]
    local available = false
    for _, choice in ipairs(choices) do if choice.id == selected then available = true break end end
    if not available then selected = choices[1].id; frame.filters[frame.tab] = selected end
    for index, button in ipairs(frame.filterButtons) do
        local choice = choices[index]
        if choice then
            local active = choice.id == selected
            button.text:SetText(choice.label)
            button.activeGlow:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], active and 0.18 or 0)
            button:SetBackdropColor(active and 0.18 or 0.055, active and 0.09 or 0.045, active and 0.025 or 0.035, 0.98)
            button:SetBackdropBorderColor(active and ORANGE[1] or 0.28, active and ORANGE[2] or 0.23, active and ORANGE[3] or 0.16, active and 1 or 0.9)
            button.text:SetFontObject(active and GameFontHighlight or GameFontNormal)
            button.text:SetTextColor(active and 1 or 0.78, active and 0.82 or 0.72, active and 0.36 or 0.62)
            if choice.flash then
                if not button.attentionAnimation:IsPlaying() then button.attentionAnimation:Play() end
            else
                button.attentionAnimation:Stop()
                button.attentionGlow:SetAlpha(0)
            end
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

local function openMemberManagementMenu(frame, member)
    if not iRC:IsGuildAdmin() or not member or not member.name then return end
    local menu = frame.memberMenu
    local scale = UIParent:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    menu.targetName = member.name
    menu.title:SetText(displayMemberName(member.name))
    local yOffset, currentGroup = 54, nil
    for _, groupLabel in pairs(menu.groupLabels) do groupLabel:Hide() end
    for _, button in ipairs(menu.actionButtons) do
        local shown = (not button.gmOnly or iRC:IsGuildMaster())
            and (not button.maxLevelOnly or (tonumber(member.level) or 0) >= 60 or iRC:IsTestAdminGuildMaster())
        button:SetShown(shown)
        if shown then
            local eligible = not button.maxLevelOnly or (tonumber(member.level) or 0) >= 60
            button:SetEnabled(eligible)
            if currentGroup ~= button.group then
                currentGroup = button.group
                local groupLabel = menu.groupLabels[currentGroup]
                groupLabel:ClearAllPoints()
                groupLabel:SetPoint("TOPLEFT", 18, -yOffset)
                groupLabel:Show()
                yOffset = yOffset + 19
            end
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", 16, -yOffset)
            local border = not eligible and GRAY or (button.tone == "approve" and GREEN or (button.tone == "danger" and RED or (button.tone == "reset" and GRAY or ORANGE)))
            button:SetBackdropBorderColor(border[1], border[2], border[3], button.tone and 0.9 or 0.45)
            button.text:SetTextColor(border[1], border[2], border[3])
            yOffset = yOffset + 31
        end
    end
    menu:SetHeight(yOffset + 12)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cursorX / scale, cursorY / scale)
    menu:Show()
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

local function setRow(frame, index, values, color, onClick, tooltip)
    local data = { values = values, color = color, onClick = onClick, tooltip = tooltip }
    frame.rowData[index] = data
    return data
end

local function renderRow(row, data)
    local values, color, onClick, tooltip = data.values, data.color, data.onClick, data.tooltip
    if data.attentionSince then values[4] = data.addonText .. "\n" .. formatAttentionTimer(data.attentionSince) end
    for column = 1, #COLUMN_X do
        row.columns[column]:SetText(values[column] or "")
        local columnColor = data.columnColors and data.columnColors[column]
        row.columns[column]:SetTextColor(unpack(columnColor or (column == 1 and (color or ORANGE) or GRAY)))
    end
    local border = color or ORANGE
    row:SetBackdropBorderColor(border[1], border[2], border[3], 0.62)
    row:SetScript("OnClick", onClick)
    row:SetScript("OnEnter", tooltip and function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end or nil)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row:Show()
end

function Dashboard:RenderVisibleRows()
    local frame = self.frame
    if not frame or not frame.rowData then return end
    local first = math.floor(frame.scroll:GetVerticalScroll() / 60) + 1
    local visible = math.max(0, math.min(#frame.rowData - first + 1, math.ceil(frame.scroll:GetHeight() / 60) + 1))
    for slot = 1, visible do
        local index = first + slot - 1
        local row = frame.rows[slot]
        if not row then row = makeRow(frame.content, index); frame.rows[slot] = row end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -((index - 1) * 60))
        row:SetPoint("TOPRIGHT", frame.content, "TOPRIGHT", 0, -((index - 1) * 60))
        renderRow(row, frame.rowData[index])
    end
    for slot = visible + 1, #frame.rows do frame.rows[slot]:Hide() end
end

local function classSummary(classes)
    local list = {}
    for class, count in pairs(classes or {}) do list[#list + 1] = class .. " " .. count end
    table.sort(list)
    return table.concat(list, ", ")
end

function Dashboard:Refresh()
    self.pendingRefresh = nil
    local frame = self:Create()
    frame.rowData = {}
    local connection = iRC:GetConnection()
    if frame.tab == "Champions" or frame.tab == "Leaderboard" then frame.tab = "Verification" end
    if frame.tabs.Incidents then frame.tabs.Incidents:SetShown(iRC:IsGuildAdmin()) end
    if frame.tab == "Incidents" and not iRC:IsGuildAdmin() then frame.tab = "Verification" end
    local visibleTabIndex = 0
    for _, tab in ipairs(frame.tabOrder or {}) do
        if tab:IsShown() then
            visibleTabIndex = visibleTabIndex + 1
            tab:ClearAllPoints()
            tab:SetPoint("TOPLEFT", tab.adminOnly and 24 or 14, -((visibleTabIndex - 1) * 36 + 43))
        end
    end
    frame.status:SetText(connection and (iRC:IsGuildConnectionActive() and (iRC.Colors.Green .. "Connected: " .. iRC.Colors.Reset .. connection.guildName) or (iRC.Colors.Yellow .. iRC:Text("DASHBOARD_STATUS_INACTIVE") .. " " .. iRC.Colors.Reset .. connection.guildName)) or (iRC.Colors.Red .. "No guild connection" .. iRC.Colors.Reset))
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
        setFilters(frame, {})
        frame.title:SetText("Faction race overview")
        frame.subtitle:SetText("A guild-level snapshot of each race represented in your guild connection.")
        setHeaders(frame, { "Race", "Members / Avg. level", "Addon / Self-Found", "Class mix" }, { "race", "members", "addonUsers", "classes" }, "members", OVERVIEW_COLUMN_X, OVERVIEW_COLUMN_WIDTH, -130)
        groups = filterAndSort(frame, groups, function() return true end, function(group, key)
            if key == "race" then return group.race or "" end
            if key == "addonUsers" then return group.addonUsers or 0 end
            if key == "classes" then return classSummary(group.classes) end
            return group.members or 0
        end)
        for _, group in ipairs(groups) do
            count = count + 1
            setRow(frame, count, { group.race, group.members .. " / " .. group.averageLevel, group.addonUsers .. " / " .. group.selfFound, classSummary(group.classes) }, ORANGE)
        end
    elseif frame.tab == "Verification" then
        local verified, compatible, attention, offline = 0, 0, 0, 0
        local members = iRC:GetGuildRosterRows()
        local rules = iRC:GetConnectionRules() or {}
        local usesSelfFound = rules.selfFoundOnly == true
        local usesGuildFound = usesSelfFound and rules.level60GuildFound == true
            and rules.allowLevel60WithoutSelfFound ~= true
        local progressHeader = usesGuildFound and iRC:Text("VERIFICATION_PROGRESS_SF_GF_COLUMN")
            or (usesSelfFound and iRC:Text("VERIFICATION_PROGRESS_COLUMN") or iRC:Text("VERIFICATION_ONLY_COLUMN"))
        for _, member in ipairs(members) do
            local state = member.verification and member.verification.state
            if state == "verified" then verified = verified + 1
            elseif state == "compatible" then compatible = compatible + 1
            elseif state == "offline" or state == "inactive" then offline = offline + 1
            else attention = attention + 1 end
        end
        setSummaryCards(frame, {
            { label = "Verified", value = tostring(verified), color = GREEN },
            { label = "Compatible", value = tostring(compatible), color = ORANGE },
            { label = "Needs attention", value = tostring(attention), color = RED },
            { label = "Offline", value = tostring(offline), color = GRAY },
        })
        local filter = setFilters(frame, {
            { id = "all", label = "All members" }, { id = "attention", label = "Needs attention", flash = attention > 0 }, { id = "verified", label = "Verified" }, { id = "compatible", label = "Compatible" },
        })
        frame.title:SetText("Guild verification")
        frame.subtitle:SetText("Live presence status. Missing or stale online members are handled by the officer notification system.")
        setHeaders(frame,
            { "Member", "Race / Class", "Level", "Live status", progressHeader, iRC:Text("VERIFICATION_STATUS_COLUMN") },
            { "name", "race", "level", "status", "progress", "clean" }, "name")
        members = filterAndSort(frame, members, function(member)
            local state = member.verification and member.verification.state or "missing"
            return filter == "all" or state == filter or (filter == "attention" and state ~= "verified" and state ~= "compatible" and state ~= "offline" and state ~= "inactive")
        end, function(member, key)
            if key == "name" then return member.name or "" end
            if key == "race" then return (member.race or "") .. (member.class or "") end
            if key == "status" then return member.verification and member.verification.state or "missing" end
            local guildFoundStatus = member.raceLockedStatus or (iRC.RaceLockedSync and iRC.RaceLockedSync:GetStatus(member.name))
            if key == "progress" then
                if usesSelfFound and (member.level or 0) < 60 then return member.selfFound and 1 or 0 end
                if usesGuildFound and (member.level or 0) >= 60 then
                    return guildFoundStatus and (guildFoundStatus.verified and 1 or 0) or 0
                end
                local state = member.verification and member.verification.state
                return (state == "verified" or state == "compatible") and 1 or 0
            end
            if key == "clean" then return guildFoundStatus and (guildFoundStatus.clean and 1 or 0) or -1 end
            return member.level or 0
        end)
        for _, member in ipairs(members) do
            count = count + 1
            local verification = member.verification or { state = "missing", label = "Addon not detected" }
            local compatiblePresence = member.compatibilityMember and member.compatibilityMember.presence
            local addon = verification.state == "compatible" and compatiblePresence and (sourceLabel(compatiblePresence.source) .. " · " .. verification.label)
                or (member.profile and (sourceLabel("iRC") .. " v" .. (member.addonVersion or "?") .. " · " .. verification.label))
                or (member.compatibility and (sourceLabel(member.source) .. " · " .. verification.label))
                or verification.label
            local attentionTimer = formatAttentionTimer(member.attentionSince)
            local addonText = addon
            if attentionTimer then addon = addon .. "\n" .. attentionTimer end
            local liveState = verification.state
            local hasLiveAddon = liveState == "verified" or liveState == "compatible"
            local selfFound = not hasLiveAddon and "Unknown"
                or (member.selfFound and "Active" or "Inactive")
            local selectedMember = member
            local guildFoundStatus = member.raceLockedStatus or (iRC.RaceLockedSync and iRC.RaceLockedSync:GetStatus(member.name))
            local hasSelfFoundSource = hasLiveAddon
            local progressText, progressColor
            if usesSelfFound and (member.level or 0) < 60 then
                progressText = hasSelfFoundSource and iRC:Text("VERIFICATION_SELF_FOUND", iRC:Text(member.selfFound and "SELF_FOUND_ACTIVE" or "SELF_FOUND_INACTIVE"))
                    or iRC:Text("VERIFICATION_SELF_FOUND_UNKNOWN")
                progressColor = hasSelfFoundSource and (member.selfFound and GREEN or RED) or GRAY
            elseif usesGuildFound and (member.level or 0) >= 60 then
                local verified = guildFoundStatus and guildFoundStatus.verified == true
                progressText = iRC:Text("VERIFICATION_GUILD_FOUND", iRC:Text(hasLiveAddon and verified and "RL_VERIFIED" or "RL_UNVERIFIED"))
                progressColor = hasLiveAddon and verified and GREEN or RED
            else
                progressText = iRC:Text(hasLiveAddon and "RL_VERIFIED" or "RL_UNVERIFIED")
                progressColor = hasLiveAddon and GREEN or RED
            end
            local belowMaxLevel = (member.level or 0) < 60
            local lowerLevelStatusOK = liveState == "verified" or liveState == "compatible"
            local lowerLevelOffline = liveState == "offline" or liveState == "inactive"
            local cleanText = belowMaxLevel and iRC:Text(lowerLevelStatusOK and "VERIFICATION_OK"
                or (lowerLevelOffline and "VERIFICATION_OFFLINE" or "RL_UNVERIFIED")) or iRC:Text("RL_STATUS_UNKNOWN")
            if not lowerLevelStatusOK then
                cleanText = iRC:Text(lowerLevelOffline and "VERIFICATION_OFFLINE" or "RL_UNVERIFIED")
            elseif (member.level or 0) >= 60 and guildFoundStatus and guildFoundStatus.clean ~= nil then
                cleanText = iRC:Text("VERIFICATION_GOLD", iRC:Text(guildFoundStatus.clean and "RL_CLEAN" or "RL_FLAGGED"))
            end
            local statusTooltip = selfFound
            if iRC.RaceLockedSync then statusTooltip = statusTooltip .. "\n" .. iRC.RaceLockedSync:DescribeStatus(member.name, false, guildFoundStatus) end
            if iRC:IsGuildAdmin() then statusTooltip = statusTooltip .. "\n\n" .. iRC:Text("MEMBER_MENU_HINT") end
            local color = verification.state == "verified" and GREEN or (verification.state == "compatible" and RED or ((verification.state == "offline" or verification.state == "inactive") and GRAY or RED))
            local data = setRow(frame, count, { displayMemberName(member.name), member.race .. " / " .. member.class, tostring(member.level), addon, progressText, cleanText }, color, function(_, mouseButton)
                if mouseButton == "RightButton" then
                    openMemberManagementMenu(frame, selectedMember)
                elseif selectedMember.profile then
                    iRC.MainUI:Open(selectedMember.name, true)
                    iRC:RequestInspection(selectedMember.name)
                end
            end, statusTooltip)
            data.attentionSince, data.addonText = member.attentionSince, addonText
            data.columnColors = {
                [5] = progressColor,
                [6] = not lowerLevelStatusOK and (lowerLevelOffline and GRAY or RED)
                    or (belowMaxLevel and GREEN
                    or (guildFoundStatus and guildFoundStatus.clean ~= nil and (guildFoundStatus.clean and GREEN or RED) or GRAY)),
            }
        end
    elseif frame.tab == "Incidents" then
        local incidents = connection and connection.officerIncidents or {}
        local reporters, locations, recent = {}, {}, 0
        for _, incident in ipairs(incidents) do
            reporters[iRC:NormalizeName(incident.reporter)] = true
            locations[incident.instanceName or ""] = true
            if time() - (tonumber(incident.occurredAt) or 0) <= 86400 then recent = recent + 1 end
        end
        local function tableCount(values) local total = 0; for _ in pairs(values) do total = total + 1 end; return total end
        setSummaryCards(frame, {
            { label = iRC:Text("INCIDENT_TOTAL"), value = tostring(#incidents), color = RED },
            { label = iRC:Text("INCIDENT_LAST_24H"), value = tostring(recent), color = ORANGE },
            { label = iRC:Text("INCIDENT_REPORTERS"), value = tostring(tableCount(reporters)), color = ORANGE },
            { label = iRC:Text("INCIDENT_LOCATIONS"), value = tostring(tableCount(locations)), color = ORANGE },
        })
        local filter = setFilters(frame, {
            { id = "all", label = iRC:Text("INCIDENT_FILTER_ALL") },
            { id = "hour", label = iRC:Text("INCIDENT_FILTER_HOUR") },
            { id = "day", label = iRC:Text("INCIDENT_FILTER_DAY") },
        })
        frame.title:SetText(iRC:Text("INCIDENT_TITLE"))
        frame.subtitle:SetText(iRC:Text("INCIDENT_DESC"))
        setHeaders(frame,
            { iRC:Text("INCIDENT_PLAYER"), iRC:Text("INCIDENT_TIME"), iRC:Text("INCIDENT_LOCATION"), iRC:Text("INCIDENT_MEMBERS"), iRC:Text("INCIDENT_STATUS") },
            { "name", "time", "location", "members", "status" }, "time")
        incidents = filterAndSort(frame, incidents, function(incident)
            local age = time() - (tonumber(incident.occurredAt) or 0)
            return filter == "all" or (filter == "hour" and age <= 3600) or (filter == "day" and age <= 86400)
        end, function(incident, key)
            if key == "name" then return incident.reporter or "" end
            if key == "location" then return incident.instanceName or "" end
            if key == "members" then return incident.players or "" end
            if key == "status" then return incident.receivedAt or 0 end
            return incident.occurredAt or 0
        end)
        for _, incident in ipairs(incidents) do
            count = count + 1
            setRow(frame, count, {
                displayMemberName(incident.reporter),
                date("%Y-%m-%d %H:%M", tonumber(incident.occurredAt) or 0),
                incident.instanceName or iRC:Text("GROUP_VIOLATION_UNKNOWN_LOCATION"),
                incident.players or iRC:Text("GROUP_VIOLATION_UNKNOWN_PLAYER"),
                iRC:Text("INCIDENT_UPLOADED"),
            }, RED, nil, incident.reason)
        end
    end
    frame.content:SetHeight(math.max(1, count * 60))
    frame.scroll:SetVerticalScroll(math.min(frame.scroll:GetVerticalScroll(), math.max(0, count * 60 - frame.scroll:GetHeight())))
    self:RenderVisibleRows()
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
    if not self.frame or not self.frame:IsShown() or self.pendingRefresh then return end
    if not C_Timer or not C_Timer.After then self:Refresh(); return end
    local ticket = {}
    self.pendingRefresh = ticket
    C_Timer.After(0.2, function()
        if Dashboard.pendingRefresh ~= ticket then return end
        Dashboard.pendingRefresh = nil
        if Dashboard.frame and Dashboard.frame:IsShown() then Dashboard:Refresh() end
    end)
end

function iRC:OpenConnectionDashboard()
    Dashboard:Open()
end
