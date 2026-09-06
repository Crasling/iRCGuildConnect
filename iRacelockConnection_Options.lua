local _, private = ...
local iRC = private and private.iRC
if not iRC then return end
local L = iRC.L

local ORANGE = iRC.ColorValues.Orange
local CHECKBOX_TEMPLATE = InterfaceOptionsCheckButtonTemplate and "InterfaceOptionsCheckButtonTemplate" or "UICheckButtonTemplate"

local function IsAddonLoadedCompat(addonName)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(addonName) end
    if IsAddOnLoaded then return IsAddOnLoaded(addonName) end
    return false
end

local function CreateSectionHeader(parent, text, yOffset)
    local header = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    header:SetHeight(24)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, yOffset)
    header:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
    header:SetBackdropColor(0.15, 0.15, 0.20, 0.60)

    local accent = header:CreateTexture(nil, "ARTWORK")
    accent:SetHeight(1)
    accent:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    accent:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    accent:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.40)

    local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", header, "LEFT", 8, 0)
    label:SetText(text)
    return header, yOffset - 28
end

local function SetSimpleTooltip(frame, title, description)
    frame:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title or "", 1, 0.82, 0)
        if description and description ~= "" then GameTooltip:AddLine(description, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end

local function CreateSettingsCheckbox(parent, label, description, yOffset, getValue, setValue, indent)
    indent = indent or 0
    local checkbox = CreateFrame("CheckButton", nil, parent, CHECKBOX_TEMPLATE)
    checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", 20 + indent, yOffset)
    if not checkbox.Text then
        checkbox.Text = checkbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        checkbox.Text:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
    end
    checkbox.Text:SetText(label)
    checkbox.Text:SetFontObject(GameFontHighlight)
    checkbox.Refresh = function() checkbox:SetChecked(getValue() and true or false) end
    checkbox:SetScript("OnClick", function(self) setValue(self:GetChecked() and true or false) end)
    SetSimpleTooltip(checkbox, label, description)

    local nextY = yOffset - 22
    if description and description ~= "" then
        local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        desc:SetPoint("TOPLEFT", parent, "TOPLEFT", 48 + indent, nextY)
        desc:SetWidth(470 - indent)
        desc:SetJustifyH("LEFT")
        desc:SetText(description)
        checkbox.description = desc
        local height = math.max(desc:GetStringHeight(), 12)
        nextY = nextY - height - 6
    end
    return checkbox, nextY
end

local function CreateSettingsDropdown(frameName, parent, label, description, yOffset, getValue, setValue, getOptions, getOptionLabel)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    title:SetText(label)

    -- Classic's enable/disable helpers look up template children by frame name.
    local dropdown = CreateFrame("Frame", frameName, parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, yOffset - 15)
    UIDropDownMenu_SetWidth(dropdown, 220)
    UIDropDownMenu_JustifyText(dropdown, "LEFT")
    dropdown.Refresh = function()
        UIDropDownMenu_SetText(dropdown, getOptionLabel(getValue()))
    end
    UIDropDownMenu_Initialize(dropdown, function(_, level)
        for _, value in ipairs(getOptions()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = getOptionLabel(value)
            info.value = value
            info.checked = value == getValue()
            info.func = function()
                setValue(value)
                dropdown:Refresh()
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    SetSimpleTooltip(dropdown, label, description)

    local nextY = yOffset - 48
    if description and description ~= "" then
        local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        desc:SetPoint("TOPLEFT", parent, "TOPLEFT", 48, nextY)
        desc:SetWidth(470)
        desc:SetJustifyH("LEFT")
        desc:SetText(description)
        nextY = nextY - math.max(desc:GetStringHeight(), 12) - 6
    end
    return dropdown, nextY
end

local function SetRuleVisualState(checkbox, active)
    local color = active and iRC.ColorValues.Green or iRC.ColorValues.Gray
    if checkbox.Text then checkbox.Text:SetTextColor(color[1], color[2], color[3]) end
    if checkbox.description then checkbox.description:SetTextColor(color[1], color[2], color[3]) end
    if not checkbox.ruleState then
        checkbox.ruleState = checkbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        checkbox.ruleState:SetPoint("LEFT", checkbox.Text, "RIGHT", 9, 0)
    end
    checkbox.ruleState:SetText(active and "ACTIVE" or "INACTIVE")
    checkbox.ruleState:SetTextColor(color[1], color[2], color[3])
end

local function CreateSubcategoryHeader(parent, text, yOffset)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 34, yOffset)
    label:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
    label:SetText(text)
    return label, yOffset - 20
end

local function CreateSettingsButton(parent, text, width, yOffset, onClick, tooltip)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 26)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    if tooltip then SetSimpleTooltip(button, text, tooltip) end
    return button, yOffset - 34
end

local function CreateInfoText(parent, text, yOffset, fontObject)
    local info = parent:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlight")
    info:SetPoint("TOPLEFT", parent, "TOPLEFT", 25, yOffset)
    info:SetWidth(490)
    info:SetJustifyH("LEFT")
    info:SetText(text)
    local height = math.max(info:GetStringHeight(), 14)
    return info, yOffset - height - 6
end

local function CreateConnectionStatusCard(parent, yOffset)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetHeight(82)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, yOffset)
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, yOffset)
    card:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    card:SetBackdropColor(0.10, 0.08, 0.06, 0.94)
    card:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.65)

    local accent = card:CreateTexture(nil, "ARTWORK")
    accent:SetWidth(3)
    accent:SetPoint("TOPLEFT", card, "TOPLEFT", 5, -7)
    accent:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 5, 7)
    accent:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.90)

    local label = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -12)
    label:SetText("Connection status")

    local status = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    status:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)

    local detail = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    detail:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -5)
    detail:SetWidth(470)
    detail:SetJustifyH("LEFT")

    return { status = status, detail = detail }, yOffset - 92
end

local settingsFrame = CreateFrame("Frame", "iRacelockConnectionSettingsFrame", UIParent, "BackdropTemplate")
settingsFrame:SetSize(750, 520)
settingsFrame:SetPoint("CENTER", UIParent, "CENTER")
settingsFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    edgeSize = 16,
    insets = { left = 5, right = 5, top = 5, bottom = 5 },
})
settingsFrame:SetBackdropColor(0.05, 0.05, 0.10, 0.95)
settingsFrame:SetBackdropBorderColor(0.80, 0.80, 0.90, 1)
settingsFrame:SetFrameStrata("HIGH")
settingsFrame:SetClampedToScreen(true)
settingsFrame:SetMovable(true)
settingsFrame:EnableMouse(true)
settingsFrame:RegisterForDrag("LeftButton", "RightButton")
settingsFrame:SetScript("OnDragStart", settingsFrame.StartMoving)
settingsFrame:SetScript("OnMouseDown", settingsFrame.StartMoving)
settingsFrame:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing(); self:SetUserPlaced(true) end)
settingsFrame:Hide()
tinsert(UISpecialFrames, settingsFrame:GetName())

local shadow = CreateFrame("Frame", nil, settingsFrame, "BackdropTemplate")
shadow:SetPoint("TOPLEFT", settingsFrame, -1, 1)
shadow:SetPoint("BOTTOMRIGHT", settingsFrame, 1, -1)
shadow:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 5 })
shadow:SetBackdropBorderColor(0, 0, 0, 0.80)

local titleBar = CreateFrame("Frame", nil, settingsFrame, "BackdropTemplate")
titleBar:SetHeight(31)
titleBar:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 0, 0)
titleBar:SetPoint("TOPRIGHT", settingsFrame, "TOPRIGHT", 0, 0)
titleBar:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    edgeSize = 16,
    insets = { left = 5, right = 5, top = 5, bottom = 5 },
})
titleBar:SetBackdropColor(0.07, 0.07, 0.12, 1)
local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
title:SetPoint("CENTER", titleBar)
title:SetText(iRC.Colors.iRC .. iRC.DisplayName .. iRC.Colors.Reset .. " " .. iRC.Colors.Green .. "v" .. iRC:GetDisplayVersion() .. iRC.Colors.Reset)

local closeButton = CreateFrame("Button", nil, settingsFrame, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", settingsFrame, "TOPRIGHT", 0, 0)
closeButton:SetScript("OnClick", function() settingsFrame:Hide() end)

local sidebarWidth = 150
local sidebar = CreateFrame("Frame", nil, settingsFrame, "BackdropTemplate")
sidebar:SetWidth(sidebarWidth)
sidebar:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 10, -35)
sidebar:SetPoint("BOTTOMLEFT", settingsFrame, "BOTTOMLEFT", 10, 10)
sidebar:SetBackdrop({
    bgFile = "Interface\\BUTTONS\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
sidebar:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
sidebar:SetBackdropBorderColor(0.40, 0.40, 0.50, 0.60)

local contentArea = CreateFrame("Frame", nil, settingsFrame, "BackdropTemplate")
contentArea:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 6, 0)
contentArea:SetPoint("BOTTOMRIGHT", settingsFrame, "BOTTOMRIGHT", -10, 10)
contentArea:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
contentArea:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
contentArea:SetBackdropBorderColor(0.60, 0.60, 0.70, 1)

local function CreateTabContent()
    local container = CreateFrame("Frame", nil, contentArea)
    container:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 5, -5)
    container:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", -5, 5)
    container:Hide()

    local scrollFrame = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -22, 0)
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(550)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    container:EnableMouseWheel(true)
    container:SetScript("OnMouseWheel", function(_, delta)
        local maximum = math.max(0, scrollChild:GetHeight() - scrollFrame:GetHeight())
        local position = math.max(0, math.min(maximum, scrollFrame:GetVerticalScroll() - delta * 30))
        scrollFrame:SetVerticalScroll(position)
    end)
    return container, scrollChild, scrollFrame
end

local generalContainer, generalContent = CreateTabContent()
local connectionContainer, connectionContent = CreateTabContent()
local roleplayContainer, roleplayContent = CreateTabContent()
local aboutContainer, aboutContent = CreateTabContent()
local iWRContainer, iWRContent = CreateTabContent()
local iNIFContainer, iNIFContent = CreateTabContent()
local iSPContainer, iSPContent = CreateTabContent()
local iSTContainer, iSTContent = CreateTabContent()
local adminContainer, adminContent = CreateTabContent()
local tabContents = { generalContainer, connectionContainer, roleplayContainer, aboutContainer, iWRContainer, iNIFContainer, iSPContainer, iSTContainer, adminContainer }
local sidebarButtons = {}

local function ShowTab(index)
    for tabIndex, tab in ipairs(tabContents) do tab:SetShown(tabIndex == index) end
    for tabIndex, button in ipairs(sidebarButtons) do
        if tabIndex == index then
            button.bg:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.25)
            button.text:SetFontObject(GameFontHighlight)
        else
            button.bg:SetColorTexture(0, 0, 0, 0)
            button.text:SetFontObject(GameFontNormal)
        end
    end
end

local sidebarItems = {
    { type = "header", label = iRC.DisplayName },
    { type = "tab", label = "General", index = 1 },
    { type = "tab", label = "Connection & Rules", index = 2 },
    { type = "tab", label = "Roleplay", index = 3 },
    { type = "tab", label = "About", index = 4 },
    { type = "header", label = "Other Addons" },
    { type = "tab", label = "iWillRemember", index = 5 },
    { type = "tab", label = "iNeedIfYouNeed", index = 6 },
    { type = "tab", label = "iSoundPlayer", index = 7 },
    { type = "tab", label = "iSealTwist", index = 8 },
}
if iRC:IsTestAdmin() then
    sidebarItems[#sidebarItems + 1] = { type = "header", label = L.TEST_ADMIN_HEADER }
    sidebarItems[#sidebarItems + 1] = { type = "tab", label = L.TEST_ADMIN_TAB, index = 9 }
end
local sidebarY = -6
for _, item in ipairs(sidebarItems) do
    if item.type == "header" then
        local headerText = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        headerText:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 12, sidebarY - 2)
        headerText:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
        headerText:SetText(item.label)
        sidebarY = sidebarY - 20
    else
        local button = CreateFrame("Button", nil, sidebar)
        button:SetSize(sidebarWidth - 12, 26)
        button:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 6, sidebarY)
        button.bg = button:CreateTexture(nil, "BACKGROUND")
        button.bg:SetAllPoints(button)
        button.bg:SetColorTexture(0, 0, 0, 0)
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        button.text:SetPoint("LEFT", button, "LEFT", 14, 0)
        button.text:SetText(item.label)
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints(button)
        highlight:SetColorTexture(1, 1, 1, 0.08)
        button:SetScript("OnClick", function() ShowTab(item.index) end)
        sidebarButtons[#sidebarButtons + 1] = button
        sidebarY = sidebarY - 28
    end
end

local y = -12
_, y = CreateSectionHeader(generalContent, "Display Settings", y)
local notificationCheck, debugModeCheck
notificationCheck, y = CreateSettingsCheckbox(generalContent, "Show achievement notifications", "Show a message when you earn an achievement.", y,
    function() return iRC:GetSettings().showAchievementNotifications end,
    function(value) iRC:GetSettings().showAchievementNotifications = value end)
_, y = CreateSectionHeader(generalContent, "Race Grid", y - 4)
local globalRaceGridCheck
globalRaceGridCheck, y = CreateSettingsCheckbox(generalContent, "Share global race-grid data", L.RL_GRID_SHARING_DESC, y,
    function() return iRC:GetSettings().shareGlobalRaceGrid end,
    function(value)
        iRC:GetSettings().shareGlobalRaceGrid = value and true or false
        if iRC.SendHello then iRC:SendHello() end
        if value and iRC.RaceGrid then
            iRC.RaceGrid:Refresh()
        elseif iRC.RaceGrid then
            iRC.RaceGrid:Disable()
        end
    end)
_, y = CreateSectionHeader(generalContent, "Minimap Settings", y - 4)
local minimapCheck
minimapCheck, y = CreateSettingsCheckbox(generalContent, "Show minimap button", "Show or hide the iRC button by your minimap.", y,
    function() return not iRC:GetSettings().minimapButton.hide end,
    function(value)
        iRC:GetSettings().minimapButton.hide = not value
        if iRC.Minimap then iRC.Minimap:UpdateVisibility() end
    end)
_, y = CreateSectionHeader(generalContent, "Achievement Window", y - 4)
local scaleLabel = generalContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
scaleLabel:SetPoint("TOPLEFT", generalContent, "TOPLEFT", 20, y)
scaleLabel:SetText("Achievement window scale")
local scaleValue = generalContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
scaleValue:SetPoint("LEFT", scaleLabel, "RIGHT", 10, 0)
scaleValue:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
local slider = CreateFrame("Slider", "iRacelockConnectionAchievementScaleSlider", generalContent, "OptionsSliderTemplate")
slider:SetPoint("TOPLEFT", generalContent, "TOPLEFT", 20, y - 22)
slider:SetWidth(240)
slider:SetMinMaxValues(0.8, 1.2)
slider:SetValueStep(0.05)
_G[slider:GetName() .. "Low"]:SetText("80%")
_G[slider:GetName() .. "High"]:SetText("120%")
_G[slider:GetName() .. "Text"]:SetText("")
SetSimpleTooltip(slider, "Achievement window scale", "Make the achievement window smaller or larger.")
slider:SetScript("OnValueChanged", function(_, value)
    value = math.floor(value * 20 + 0.5) / 20
    iRC:GetSettings().achievementScale = value
    scaleValue:SetText(math.floor(value * 100 + 0.5) .. "%")
    if iRC.AchievementsUI and iRC.AchievementsUI.frame then iRC.AchievementsUI.frame:SetScale(value) end
end)
y = y - 74
_, y = CreateSettingsButton(generalContent, "Open achievements", 180, y, function() iRC.AchievementsUI:Open() end, "View your achievements.")
_, y = CreateSettingsButton(generalContent, "Reset achievement window position", 220, y, function()
    local achievementFrame = iRC.AchievementsUI:Create()
    achievementFrame:ClearAllPoints()
    achievementFrame:SetPoint("CENTER")
    iRC:Print(L.ACHIEVEMENT_WINDOW_RESET)
end, "Move the achievement window back to the middle of the screen.")
generalContent:SetHeight(math.abs(y) + 20)

y = -12
_, y = CreateSectionHeader(connectionContent, "Guild Connection", y)
local connectionCard
connectionCard, y = CreateConnectionStatusCard(connectionContent, y)
local connectionStatus, connectionDetail = connectionCard.status, connectionCard.detail
_, y = CreateInfoText(connectionContent, "Your guild shares progress, stats, and achievements through iRC.", y - 2, "GameFontDisableSmall")
local connectionActionsY = y - 4
local dashboardButton = CreateSettingsButton(connectionContent, "Open connection dashboard", 210, connectionActionsY, function()
    iRC:OpenConnectionDashboard()
end, "View guild members, shared progress, and addon status.")
local broadcastButton = CreateSettingsButton(connectionContent, "Broadcast my status", 180, connectionActionsY, function()
    iRC:SendHello()
    iRC:Print(L.CONNECTION_STATUS_BROADCAST)
end, "Send your latest progress to the guild.")
broadcastButton:ClearAllPoints()
broadcastButton:SetPoint("LEFT", dashboardButton, "RIGHT", 8, 0)
y = connectionActionsY - 36

local guildRulesStatus
local guildActivationCheck, guildRaceDropdown, nativeTongueCheck, selfFoundOnlyCheck, level60GuildFoundCheck, level60SelfFoundExceptionCheck, sameRaceGroupsCheck, level60SameRaceExceptionCheck
y = select(2, CreateSectionHeader(connectionContent, "Guild Enforced Rules", y - 2))
guildRulesStatus, y = CreateInfoText(connectionContent, "", y, "GameFontHighlight")
_, y = CreateInfoText(connectionContent, L.GUILD_RULES_INTRO, y, "GameFontDisableSmall")
guildActivationCheck, y = CreateSettingsCheckbox(connectionContent, L.GUILD_ACTIVATION_LABEL, L.GUILD_ACTIVATION_DESC, y,
    function() return iRC:IsGuildConnectionActive() end,
    function(value) iRC:SetGuildConnectionActive(value) end)
_, y = CreateSubcategoryHeader(connectionContent, L.GUILD_RACE_HEADER, y - 2)
guildRaceDropdown, y = CreateSettingsDropdown("iRacelockConnectionGuildRaceDropdown", connectionContent, L.GUILD_RACE_LABEL, L.GUILD_RACE_DESC, y,
    function() return iRC:GetGuildRace() end,
    function(value) iRC:SetGuildRace(value) end,
    function() return iRC:GetAvailableGuildRaces() end,
    function(value) return iRC:Text("GUILD_RACE_" .. value) end)
_, y = CreateSubcategoryHeader(connectionContent, "Language", y - 2)
nativeTongueCheck, y = CreateSettingsCheckbox(connectionContent, "Native language chat", "Forces your chat boxes to use your character's racial language when you send a message.", y,
    function() return iRC:GetConnectionRules().nativeTongueOnly end,
    function(value) iRC:SetConnectionRule("nativeTongueOnly", value) end)
_, y = CreateSubcategoryHeader(connectionContent, "Progression", y - 2)
selfFoundOnlyCheck, y = CreateSettingsCheckbox(connectionContent, "Self-Found only", "Require the game's Self-Found mode while leveling. Self-Found blocks player trading, Auction House use, and most mail.", y,
    function() return iRC:GetConnectionRules().selfFoundOnly end,
    function(value) iRC:SetConnectionRule("selfFoundOnly", value) end)
_, y = CreateSubcategoryHeader(connectionContent, "Level 60 Self-Found Options", y - 2)
level60GuildFoundCheck, y = CreateSettingsCheckbox(connectionContent, "Level 60 Guild Found", "At level 60, replace Self-Found with Guild Found. Trade and group only with guild members; iRC blocks the Auction House and non-guild groups.", y,
    function() return iRC:GetConnectionRules().level60GuildFound end,
    function(value) iRC:SetConnectionRule("level60GuildFound", value) end, 18)
level60SelfFoundExceptionCheck, y = CreateSettingsCheckbox(connectionContent, "Level 60 SF Exception", "At level 60, iRC stops enforcing Self-Found and Guild Found limits. You may trade, use the Auction House, and group normally.", y,
    function() return iRC:GetConnectionRules().allowLevel60WithoutSelfFound end,
    function(value) iRC:SetConnectionRule("allowLevel60WithoutSelfFound", value) end, 18)
_, y = CreateSubcategoryHeader(connectionContent, "Group Rules", y - 2)
sameRaceGroupsCheck, y = CreateSettingsCheckbox(connectionContent, "Same-race groups only", "Warn the group and leave any party or raid that includes a different race.", y,
    function() return iRC:GetConnectionRules().sameRaceGroupsOnly end,
    function(value) iRC:SetConnectionRule("sameRaceGroupsOnly", value) end)
level60SameRaceExceptionCheck, y = CreateSettingsCheckbox(connectionContent, "Level 60 Mixed-Race Exception", "At level 60, allow mixed-race parties and raids. Same-race groups remain required while leveling.", y,
    function() return iRC:GetConnectionRules().allowLevel60MixedRaceGroups end,
    function(value) iRC:SetConnectionRule("allowLevel60MixedRaceGroups", value) end, 18)
connectionContent:SetHeight(math.abs(y) + 20)

_, y = CreateSectionHeader(connectionContent, L.RL_OVERRIDE_TITLE, y - 8)
_, y = CreateInfoText(connectionContent, L.RL_OVERRIDE_DESC, y, "GameFontDisableSmall")
_, y = CreateInfoText(connectionContent, L.RL_OVERRIDE_MEMBER, y, "GameFontHighlight")
local overrideName = CreateFrame("EditBox", nil, connectionContent, "InputBoxTemplate")
overrideName:SetSize(240, 24)
overrideName:SetPoint("TOPLEFT", connectionContent, "TOPLEFT", 25, y)
overrideName:SetAutoFocus(false)
overrideName:SetMaxLetters(80)
overrideName:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
local overrideVerified, overrideClean = "-", "-"
local overrideVerifiedDropdown, overrideCleanDropdown
local function overrideValue(value)
    if value == "1" then return true end
    if value == "0" then return false end
end
overrideVerifiedDropdown, y = CreateSettingsDropdown("iRCGuildFoundVerifiedDropdown", connectionContent, L.RL_OVERRIDE_VERIFIED, nil, y - 34,
    function() return overrideVerified end, function(value) overrideVerified = value end,
    function() return { "-", "1", "0" } end,
    function(value) return value == "-" and L.RL_OVERRIDE_RESET or (value == "1" and L.RL_VERIFIED or L.RL_UNVERIFIED) end)
overrideCleanDropdown, y = CreateSettingsDropdown("iRCGuildFoundCleanDropdown", connectionContent, L.RL_OVERRIDE_CLEAN, nil, y,
    function() return overrideClean end, function(value) overrideClean = value end,
    function() return { "-", "1", "0" } end,
    function(value) return value == "-" and L.RL_OVERRIDE_RESET or (value == "1" and L.RL_CLEAN or L.RL_FLAGGED) end)
local overrideApply
overrideApply, y = CreateSettingsButton(connectionContent, L.RL_OVERRIDE_APPLY, 220, y, function()
    local name = (overrideName:GetText() or ""):match("^%s*(.-)%s*$")
    if not iRC.RaceLockedSync:SetOverride(name, overrideValue(overrideVerified), overrideValue(overrideClean)) then iRC:Print(L.RL_OVERRIDE_FAILED) end
end, L.RL_OVERRIDE_DESC)
connectionContent:SetHeight(math.abs(y) + 20)

y = -12
_, y = CreateSectionHeader(roleplayContent, "Player Settings", y)
local trollTalkStatus
trollTalkStatus, y = CreateInfoText(roleplayContent, "", y, "GameFontHighlight")
_, y = CreateSectionHeader(roleplayContent, "Troll Talk", y - 2)
local trollTalkCheck
trollTalkCheck, y = CreateSettingsCheckbox(roleplayContent, "Enable Troll Talk", "Add simple troll wording to your normal chat messages.", y,
    function() return iRC.Roleplay:GetPlayerSettings().trollTalk end,
    function(value) iRC.Roleplay:GetPlayerSettings().trollTalk = value and true or false end)
_, y = CreateInfoText(roleplayContent, "Example: “Do you want to join?” becomes “Do ya wanna join?” Words such as man and mate can still become mon.", y - 2, "GameFontDisableSmall")
roleplayContent:SetHeight(math.abs(y) + 20)

do
    local y = -15
    local aboutIcon = aboutContent:CreateTexture(nil, "ARTWORK")
    aboutIcon:SetSize(64, 64)
    aboutIcon:SetPoint("TOP", aboutContent, "TOP", 0, y)
    aboutIcon:SetTexture(iRC.IconPath)
    y = y - 70

    local aboutTitle = aboutContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    aboutTitle:SetPoint("TOP", aboutContent, "TOP", 0, y)
    aboutTitle:SetText(iRC.Colors.iRC .. iRC.DisplayName .. iRC.Colors.Reset .. " " .. iRC.Colors.Green .. "v" .. iRC:GetDisplayVersion() .. iRC.Colors.Reset)
    y = y - 20

    local aboutAuthor = aboutContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    aboutAuthor:SetPoint("TOP", aboutContent, "TOP", 0, y)
    aboutAuthor:SetText("Created by: " .. iRC.Colors.Orange .. "Crasling" .. iRC.Colors.Reset)
    y = y - 25

    local aboutDescription = aboutContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    aboutDescription:SetPoint("TOPLEFT", aboutContent, "TOPLEFT", 25, y)
    aboutDescription:SetWidth(470)
    aboutDescription:SetJustifyH("LEFT")
    aboutDescription:SetWordWrap(true)
    aboutDescription:SetText(iRC.Colors.iRC .. iRC.DisplayName .. " " .. iRC.Colors.Reset .. "is a guild-connected race progression and achievement framework. Guild members using iRC can share progress, verification status, Self-Found state, and local leaderboard statistics.")
    y = y - aboutDescription:GetStringHeight() - 15

    _, y = CreateSectionHeader(aboutContent, "Links", y)
    _, y = CreateInfoText(aboutContent, "GitHub: github.com/Crasling/iRacelockConnection", y, "GameFontDisableSmall")
    _, y = CreateSectionHeader(aboutContent, L.DEVELOPER_HEADER, y - 6)
    debugModeCheck, y = CreateSettingsCheckbox(aboutContent, L.ENABLE_DEBUG_MODE, L.ENABLE_DEBUG_MODE_DESC, y,
        function() return iRC:GetSettings().debugMode end,
        function(value) iRC:GetSettings().debugMode = value and true or false end)
    aboutContent:SetHeight(math.abs(y) + 20)
end

local companionAddons = {
    { content = iWRContent, name = "iWillRemember", addonName = "iWillRemember", description = "A player notes addon for tracking and sharing memorable encounters with friends and guild members.", link = "curseforge.com/wow/addons/iwillremember", button = "Open iWR Settings", getFrame = function() return _G.iWR and _G.iWR.SettingsFrame end },
    { content = iNIFContent, name = "iNeedIfYouNeed", addonName = "iNeedIfYouNeed", description = "A smart loot companion that helps groups handle Need and Greed decisions for eligible items.", link = "curseforge.com/wow/addons/ineedifyouneed", button = "Open iNIF Settings", getFrame = function() return _G.iNIFSettingsFrame end },
    { content = iSPContent, name = "iSoundPlayer", addonName = "iSoundPlayer", description = "A custom sound addon for playing your own sounds from game events, spells, buffs, and more.", link = "curseforge.com/wow/addons/isoundplayer", button = "Open iSP Settings", getFrame = function() return _G.iSPSettingsFrame end },
    { content = iSTContent, name = "iSealTwist", addonName = "iSealTwist", description = "A TBC Paladin seal-twist timing helper with a visual swing timer and latency-aware window.", link = "curseforge.com/wow/addons/isealtwist", button = "Open iST Settings", getFrame = function() return _G.iSTSettingsFrame end },
}

for _, addon in ipairs(companionAddons) do
    local companion = addon
    addon.installedFrame = CreateFrame("Frame", nil, addon.content)
    addon.installedFrame:SetAllPoints(addon.content)
    addon.installedFrame:Hide()
    do
        local y = -12
        _, y = CreateSectionHeader(addon.installedFrame, iRC.Colors.iRC .. addon.name .. iRC.Colors.Reset, y)
        _, y = CreateInfoText(addon.installedFrame, iRC.Colors.iRC .. addon.name .. iRC.Colors.Reset .. " is installed. Open its settings to configure the addon.", y, "GameFontHighlight")
        _, y = CreateSettingsButton(addon.installedFrame, addon.button, 180, y - 6, function()
            local frame = companion.getFrame()
            if not frame then return end
            local point, _, relativePoint, xOffset, yOffset = settingsFrame:GetPoint()
            frame:ClearAllPoints()
            frame:SetPoint(point, UIParent, relativePoint, xOffset, yOffset)
            settingsFrame:Hide()
            frame:Show()
        end, "Open " .. addon.name .. " settings.")
        addon.content:SetHeight(math.abs(y) + 20)
    end

    addon.promoFrame = CreateFrame("Frame", nil, addon.content)
    addon.promoFrame:SetAllPoints(addon.content)
    addon.promoFrame:Hide()
    do
        local y = -12
        _, y = CreateSectionHeader(addon.promoFrame, iRC.Colors.iRC .. addon.name .. iRC.Colors.Reset, y)
        _, y = CreateInfoText(addon.promoFrame, addon.description, y, "GameFontHighlight")
        _, y = CreateInfoText(addon.promoFrame, "Available on CurseForge: " .. addon.link, y - 4, "GameFontDisableSmall")
        addon.content:SetHeight(math.abs(y) + 20)
    end
end

local testGuildMasterCheck, testAdminStatus, testGuildStatus, testActivateGuildButton
if iRC:IsTestAdmin() then
    y = -12
    _, y = CreateSectionHeader(adminContent, L.TEST_ADMIN_TITLE, y)
    _, y = CreateInfoText(adminContent, L.TEST_ADMIN_DESCRIPTION, y, "GameFontDisableSmall")
    testAdminStatus, y = CreateInfoText(adminContent, "", y - 2, "GameFontHighlight")
    testGuildStatus, y = CreateInfoText(adminContent, "", y, "GameFontHighlight")
    testGuildMasterCheck, y = CreateSettingsCheckbox(adminContent, L.TEST_ADMIN_GUILD_MASTER, L.TEST_ADMIN_GUILD_MASTER_DESC, y - 4,
        function() return iRC:IsTestAdminGuildMaster() end,
        function(value)
            iRC:GetSettings().testGuildMasterOverride = value and true or false
            iRC:SendHello()
            iRC:PollGuildPresence()
            if iRC.RefreshOptionsIfShown then iRC:RefreshOptionsIfShown() end
        end)
    testActivateGuildButton, y = CreateSettingsButton(adminContent, L.TEST_ADMIN_ACTIVATE_GUILD, 190, y - 4, function()
        iRC:ActivateGuildForTesting()
    end, L.TEST_ADMIN_ACTIVATE_GUILD_DESC)
    adminContent:SetHeight(math.abs(y) + 20)
end

local function Refresh()
    notificationCheck:Refresh()
    if debugModeCheck then debugModeCheck:Refresh() end
    if testGuildMasterCheck then
        testGuildMasterCheck:Refresh()
        local testGuildMaster = iRC:IsTestAdminGuildMaster()
        testAdminStatus:SetText((testGuildMaster and iRC.Colors.Green or iRC.Colors.Yellow)
            .. iRC:Text(testGuildMaster and "TEST_ADMIN_STATUS_GUILD_MASTER" or "TEST_ADMIN_STATUS_MEMBER") .. iRC.Colors.Reset)
        local testConnection = iRC:GetConnection()
        if testConnection then
            testGuildStatus:SetText((iRC:IsGuildConnectionActive() and iRC.Colors.Green or iRC.Colors.Yellow)
                .. iRC:Text(iRC:IsGuildConnectionActive() and "TEST_ADMIN_STATUS_ACTIVE" or "TEST_ADMIN_STATUS_INACTIVE") .. iRC.Colors.Reset)
            testActivateGuildButton:SetEnabled(true)
        else
            testGuildStatus:SetText(iRC.Colors.Gray .. L.TEST_ADMIN_NO_GUILD .. iRC.Colors.Reset)
            testActivateGuildButton:SetEnabled(false)
        end
    end
    globalRaceGridCheck:Refresh()
    minimapCheck:Refresh()
    slider:SetValue(iRC:GetSettings().achievementScale or 1)
    local connection = iRC:GetConnection()
    if connection then
        if iRC:IsGuildConnectionActive() then
            connectionStatus:SetText(iRC.Colors.Green .. "Connected" .. iRC.Colors.Reset)
            connectionDetail:SetText("Guild: " .. iRC.Colors.Orange .. connection.guildName .. iRC.Colors.Reset .. "  |  Sharing and checks are active.")
        else
            connectionStatus:SetText(iRC.Colors.Yellow .. L.CONNECTION_STATUS_INACTIVE .. iRC.Colors.Reset)
            connectionDetail:SetText(string.format(L.CONNECTION_DETAIL_INACTIVE, iRC.Colors.Orange .. connection.guildName .. iRC.Colors.Reset))
        end
    else
        connectionStatus:SetText(iRC.Colors.Red .. "No active guild connection" .. iRC.Colors.Reset)
        connectionDetail:SetText("Join a guild to use shared progress and rules.")
    end
    guildActivationCheck:Refresh()
    guildRaceDropdown:Refresh()
    nativeTongueCheck:Refresh()
    selfFoundOnlyCheck:Refresh()
    level60GuildFoundCheck:Refresh()
    level60SelfFoundExceptionCheck:Refresh()
    sameRaceGroupsCheck:Refresh()
    level60SameRaceExceptionCheck:Refresh()
    local isGuildMaster = connection and iRC:IsGuildMaster()
    local guildActive = connection and iRC:IsGuildConnectionActive()
    overrideVerifiedDropdown:Refresh()
    overrideCleanDropdown:Refresh()
    overrideApply:SetEnabled(isGuildMaster and guildActive and true or false)
    overrideName:SetEnabled(isGuildMaster and guildActive and true or false)
    local enableOverride = isGuildMaster and guildActive and UIDropDownMenu_EnableDropDown or UIDropDownMenu_DisableDropDown
    enableOverride(overrideVerifiedDropdown)
    enableOverride(overrideCleanDropdown)
    broadcastButton:SetEnabled(guildActive and true or false)
    guildActivationCheck:SetEnabled(isGuildMaster and true or false)
    if isGuildMaster and guildActive then
        UIDropDownMenu_EnableDropDown(guildRaceDropdown)
    else
        UIDropDownMenu_DisableDropDown(guildRaceDropdown)
    end
    nativeTongueCheck:SetEnabled(isGuildMaster and guildActive and true or false)
    selfFoundOnlyCheck:SetEnabled(isGuildMaster and guildActive and true or false)
    local selfFoundOptionsEnabled = isGuildMaster and guildActive and iRC:GetConnectionRules().selfFoundOnly
    level60GuildFoundCheck:SetEnabled(selfFoundOptionsEnabled and true or false)
    level60SelfFoundExceptionCheck:SetEnabled(selfFoundOptionsEnabled and true or false)
    sameRaceGroupsCheck:SetEnabled(isGuildMaster and guildActive and true or false)
    local sameRaceExceptionEnabled = isGuildMaster and guildActive and iRC:GetConnectionRules().sameRaceGroupsOnly
    level60SameRaceExceptionCheck:SetEnabled(sameRaceExceptionEnabled and true or false)
    local rules = iRC:GetConnectionRules()
    SetRuleVisualState(guildActivationCheck, guildActive)
    SetRuleVisualState(nativeTongueCheck, rules.nativeTongueOnly)
    SetRuleVisualState(selfFoundOnlyCheck, rules.selfFoundOnly)
    SetRuleVisualState(level60GuildFoundCheck, rules.selfFoundOnly and rules.level60GuildFound)
    SetRuleVisualState(level60SelfFoundExceptionCheck, rules.selfFoundOnly and rules.allowLevel60WithoutSelfFound)
    SetRuleVisualState(sameRaceGroupsCheck, rules.sameRaceGroupsOnly)
    SetRuleVisualState(level60SameRaceExceptionCheck, rules.sameRaceGroupsOnly and rules.allowLevel60MixedRaceGroups)
    if not connection then
        guildRulesStatus:SetText(iRC.Colors.Gray .. L.GUILD_STATUS_NO_GUILD .. iRC.Colors.Reset)
    elseif not guildActive and isGuildMaster then
        guildRulesStatus:SetText(iRC.Colors.Yellow .. L.GUILD_STATUS_GM_INACTIVE .. iRC.Colors.Reset)
    elseif not guildActive then
        guildRulesStatus:SetText(iRC.Colors.Yellow .. L.GUILD_STATUS_MEMBER_INACTIVE .. iRC.Colors.Reset)
    elseif isGuildMaster then
        guildRulesStatus:SetText(iRC.Colors.Green .. L.GUILD_STATUS_GM_ACTIVE .. iRC.Colors.Reset)
    else
        guildRulesStatus:SetText(iRC.Colors.Yellow .. L.GUILD_STATUS_MEMBER_ACTIVE .. iRC.Colors.Reset)
    end
    trollTalkCheck:Refresh()
    local isTroll = iRC.Roleplay and iRC.Roleplay:IsTroll()
    trollTalkCheck:SetEnabled(isTroll and true or false)
    if isTroll then
        trollTalkStatus:SetText(iRC.Colors.Green .. "Troll character detected." .. iRC.Colors.Reset .. " This setting only affects this character.")
    else
        trollTalkStatus:SetText(iRC.Colors.Gray .. "Only Troll characters can use Troll Talk." .. iRC.Colors.Reset)
    end
    for _, addon in ipairs(companionAddons) do
        local loaded = IsAddonLoadedCompat(addon.addonName)
        addon.installedFrame:SetShown(loaded)
        addon.promoFrame:SetShown(not loaded)
    end
end

iRC.RefreshOptionsIfShown = function()
    if settingsFrame:IsShown() then Refresh() end
end

settingsFrame:SetScript("OnShow", Refresh)
ShowTab(1)
iRC.SettingsFrame = settingsFrame

local stubPanel = CreateFrame("Frame", "iRacelockConnectionOptionsPanel", UIParent)
stubPanel.name = iRC.DisplayName
local stubTitle = stubPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
stubTitle:SetPoint("TOPLEFT", 16, -16)
stubTitle:SetText(iRC.Colors.iRC .. iRC.DisplayName .. iRC.Colors.Reset .. " " .. iRC.Colors.Green .. "v" .. iRC:GetDisplayVersion() .. iRC.Colors.Reset)
local stubDescription = stubPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
stubDescription:SetPoint("TOPLEFT", stubTitle, "BOTTOMLEFT", 0, -10)
stubDescription:SetText("Open the full iRacelockConnection settings panel.")
local stubButton = CreateFrame("Button", nil, stubPanel, "UIPanelButtonTemplate")
stubButton:SetSize(180, 28)
stubButton:SetPoint("TOPLEFT", stubDescription, "BOTTOMLEFT", 0, -15)
stubButton:SetText("Open settings")
stubButton:SetScript("OnClick", function() iRC:OpenOptions() end)
if InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(stubPanel)
elseif Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(stubPanel, iRC.DisplayName)
    Settings.RegisterAddOnCategory(category)
end

function iRC:OpenOptions()
    if self.CloseWindowsExcept then
        self:CloseWindowsExcept(settingsFrame)
    end
    settingsFrame:Show()
end

function iRC:ToggleOptions()
    if settingsFrame:IsShown() then
        settingsFrame:Hide()
    else
        self:OpenOptions()
    end
end
