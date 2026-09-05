local iRL = _G.iRaceLocked
if not iRL then return end

local ORANGE = iRL.ColorValues.Orange
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

local function CreateSettingsCheckbox(parent, label, description, yOffset, getValue, setValue)
    local checkbox = CreateFrame("CheckButton", nil, parent, CHECKBOX_TEMPLATE)
    checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    if not checkbox.Text then
        checkbox.Text = checkbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        checkbox.Text:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
    end
    checkbox.Text:SetText(label)
    checkbox.Text:SetFontObject(GameFontHighlight)
    checkbox.Refresh = function() checkbox:SetChecked(getValue() and true or false) end
    checkbox:SetScript("OnClick", function(self) setValue(self:GetChecked() and true or false) end)

    local nextY = yOffset - 22
    if description and description ~= "" then
        local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        desc:SetPoint("TOPLEFT", parent, "TOPLEFT", 48, nextY)
        desc:SetWidth(470)
        desc:SetJustifyH("LEFT")
        desc:SetText(description)
        local height = math.max(desc:GetStringHeight(), 12)
        nextY = nextY - height - 6
    end
    return checkbox, nextY
end

local function CreateSettingsButton(parent, text, width, yOffset, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 26)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
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

local settingsFrame = CreateFrame("Frame", "iRaceLockedSettingsFrame", UIParent, "BackdropTemplate")
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
title:SetText(iRL.Colors.iRC .. iRL.DisplayName .. iRL.Colors.Reset .. " " .. iRL.Colors.Green .. "v" .. iRL.Version .. iRL.Colors.Reset)

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
local aboutContainer, aboutContent = CreateTabContent()
local iWRContainer, iWRContent = CreateTabContent()
local iNIFContainer, iNIFContent = CreateTabContent()
local iSPContainer, iSPContent = CreateTabContent()
local iSTContainer, iSTContent = CreateTabContent()
local tabContents = { generalContainer, connectionContainer, aboutContainer, iWRContainer, iNIFContainer, iSPContainer, iSTContainer }
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
    { type = "header", label = iRL.DisplayName },
    { type = "tab", label = "General", index = 1 },
    { type = "tab", label = "Connection", index = 2 },
    { type = "tab", label = "About", index = 3 },
    { type = "header", label = "Other Addons" },
    { type = "tab", label = "iWillRemember", index = 4 },
    { type = "tab", label = "iNeedIfYouNeed", index = 5 },
    { type = "tab", label = "iSoundPlayer", index = 6 },
    { type = "tab", label = "iSealTwist", index = 7 },
}
local sidebarY = -6
for _, item in ipairs(sidebarItems) do
    if item.type == "header" then
        local headerText = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        headerText:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 12, sidebarY - 2)
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
local notificationCheck
notificationCheck, y = CreateSettingsCheckbox(generalContent, "Show achievement notifications", "Shows a chat message when this character earns an iRacelockConnection achievement.", y,
    function() return iRL:GetSettings().showAchievementNotifications end,
    function(value) iRL:GetSettings().showAchievementNotifications = value end)
_, y = CreateSectionHeader(generalContent, "Minimap Settings", y - 4)
local minimapCheck
minimapCheck, y = CreateSettingsCheckbox(generalContent, "Show minimap button", "Toggles the iRacelockConnection minimap button. Position and visibility are stored per account.", y,
    function() return not iRL:GetSettings().minimapButton.hide end,
    function(value)
        iRL:GetSettings().minimapButton.hide = not value
        if iRL.Minimap then iRL.Minimap:UpdateVisibility() end
    end)
_, y = CreateSectionHeader(generalContent, "Achievement Window", y - 4)
local scaleLabel = generalContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
scaleLabel:SetPoint("TOPLEFT", generalContent, "TOPLEFT", 20, y)
scaleLabel:SetText("Achievement window scale")
local scaleValue = generalContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
scaleValue:SetPoint("LEFT", scaleLabel, "RIGHT", 10, 0)
scaleValue:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
local slider = CreateFrame("Slider", "iRaceLockedAchievementScaleSlider", generalContent, "OptionsSliderTemplate")
slider:SetPoint("TOPLEFT", generalContent, "TOPLEFT", 20, y - 22)
slider:SetWidth(240)
slider:SetMinMaxValues(0.8, 1.2)
slider:SetValueStep(0.05)
_G[slider:GetName() .. "Low"]:SetText("80%")
_G[slider:GetName() .. "High"]:SetText("120%")
_G[slider:GetName() .. "Text"]:SetText("")
slider:SetScript("OnValueChanged", function(_, value)
    value = math.floor(value * 20 + 0.5) / 20
    iRL:GetSettings().achievementScale = value
    scaleValue:SetText(math.floor(value * 100 + 0.5) .. "%")
    if iRL.AchievementsUI and iRL.AchievementsUI.frame then iRL.AchievementsUI.frame:SetScale(value) end
end)
y = y - 74
_, y = CreateSettingsButton(generalContent, "Open achievements", 180, y, function() iRL.AchievementsUI:Open() end)
_, y = CreateSettingsButton(generalContent, "Reset achievement window position", 220, y, function()
    local achievementFrame = iRL.AchievementsUI:Create()
    achievementFrame:ClearAllPoints()
    achievementFrame:SetPoint("CENTER")
    iRL:Print("Achievement window position reset.")
end)
generalContent:SetHeight(math.abs(y) + 20)

y = -12
_, y = CreateSectionHeader(connectionContent, "Guild Connection", y)
local connectionStatus
connectionStatus, y = CreateInfoText(connectionContent, "", y, "GameFontHighlight")
_, y = CreateSectionHeader(connectionContent, "Shared Progress", y - 4)
_, y = CreateInfoText(connectionContent, "Your guild is the connection. Members using iRacelockConnection automatically share presence, points, Self-Found status, local statistics, and inspectable achievement progress. No separate invite or local gameplay lock is used.", y, "GameFontDisableSmall")
_, y = CreateSettingsButton(connectionContent, "Open connection dashboard", 210, y - 6, function()
    iRL:OpenConnectionDashboard()
end)
_, y = CreateSettingsButton(connectionContent, "Broadcast my current status", 210, y - 6, function()
    iRL:SendHello()
    iRL:Print("Guild connection status broadcast.")
end)
connectionContent:SetHeight(math.abs(y) + 20)

do
    local y = -15
    local aboutIcon = aboutContent:CreateTexture(nil, "ARTWORK")
    aboutIcon:SetSize(64, 64)
    aboutIcon:SetPoint("TOP", aboutContent, "TOP", 0, y)
    aboutIcon:SetTexture(iRL.IconPath)
    y = y - 70

    local aboutTitle = aboutContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    aboutTitle:SetPoint("TOP", aboutContent, "TOP", 0, y)
    aboutTitle:SetText(iRL.Colors.iRC .. iRL.DisplayName .. iRL.Colors.Reset .. " " .. iRL.Colors.Green .. "v" .. iRL.Version .. iRL.Colors.Reset)
    y = y - 20

    local aboutAuthor = aboutContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    aboutAuthor:SetPoint("TOP", aboutContent, "TOP", 0, y)
    aboutAuthor:SetText("Created by: " .. iRL.Colors.Orange .. "Crasling" .. iRL.Colors.Reset)
    y = y - 25

    local aboutDescription = aboutContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    aboutDescription:SetPoint("TOPLEFT", aboutContent, "TOPLEFT", 25, y)
    aboutDescription:SetWidth(470)
    aboutDescription:SetJustifyH("LEFT")
    aboutDescription:SetWordWrap(true)
    aboutDescription:SetText(iRL.Colors.iRC .. iRL.DisplayName .. " " .. iRL.Colors.Reset .. "is a guild-connected race progression and achievement framework. Guild members using iRC can share progress, verification status, Self-Found state, and local leaderboard statistics.")
    y = y - aboutDescription:GetStringHeight() - 15

    _, y = CreateSectionHeader(aboutContent, "Links", y)
    _, y = CreateInfoText(aboutContent, "GitHub: github.com/Crasling/iRacelockConnection", y, "GameFontDisableSmall")
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
        _, y = CreateSectionHeader(addon.installedFrame, iRL.Colors.iRC .. addon.name .. iRL.Colors.Reset, y)
        _, y = CreateInfoText(addon.installedFrame, iRL.Colors.iRC .. addon.name .. iRL.Colors.Reset .. " is installed. Open its settings to configure the addon.", y, "GameFontHighlight")
        _, y = CreateSettingsButton(addon.installedFrame, addon.button, 180, y - 6, function()
            local frame = companion.getFrame()
            if not frame then return end
            local point, _, relativePoint, xOffset, yOffset = settingsFrame:GetPoint()
            frame:ClearAllPoints()
            frame:SetPoint(point, UIParent, relativePoint, xOffset, yOffset)
            settingsFrame:Hide()
            frame:Show()
        end)
        addon.content:SetHeight(math.abs(y) + 20)
    end

    addon.promoFrame = CreateFrame("Frame", nil, addon.content)
    addon.promoFrame:SetAllPoints(addon.content)
    addon.promoFrame:Hide()
    do
        local y = -12
        _, y = CreateSectionHeader(addon.promoFrame, iRL.Colors.iRC .. addon.name .. iRL.Colors.Reset, y)
        _, y = CreateInfoText(addon.promoFrame, addon.description, y, "GameFontHighlight")
        _, y = CreateInfoText(addon.promoFrame, "Available on CurseForge: " .. addon.link, y - 4, "GameFontDisableSmall")
        addon.content:SetHeight(math.abs(y) + 20)
    end
end

local function Refresh()
    notificationCheck:Refresh()
    minimapCheck:Refresh()
    slider:SetValue(iRL:GetSettings().achievementScale or 1)
    local connection = iRL:GetConnection()
    if connection then
        connectionStatus:SetText(iRL.Colors.Green .. "Connected" .. iRL.Colors.Reset .. " to " .. connection.guildName .. ".")
    else
        connectionStatus:SetText(iRL.Colors.Red .. "No active guild connection." .. iRL.Colors.Reset .. " Join a guild to enable shared progress.")
    end
    for _, addon in ipairs(companionAddons) do
        local loaded = IsAddonLoadedCompat(addon.addonName)
        addon.installedFrame:SetShown(loaded)
        addon.promoFrame:SetShown(not loaded)
    end
end

settingsFrame:SetScript("OnShow", Refresh)
ShowTab(1)
iRL.SettingsFrame = settingsFrame

local stubPanel = CreateFrame("Frame", "iRaceLockedOptionsPanel", UIParent)
stubPanel.name = iRL.DisplayName
local stubTitle = stubPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
stubTitle:SetPoint("TOPLEFT", 16, -16)
stubTitle:SetText(iRL.Colors.iRC .. iRL.DisplayName .. iRL.Colors.Reset .. " " .. iRL.Colors.Green .. "v" .. iRL.Version .. iRL.Colors.Reset)
local stubDescription = stubPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
stubDescription:SetPoint("TOPLEFT", stubTitle, "BOTTOMLEFT", 0, -10)
stubDescription:SetText("Open the full iRacelockConnection settings panel.")
local stubButton = CreateFrame("Button", nil, stubPanel, "UIPanelButtonTemplate")
stubButton:SetSize(180, 28)
stubButton:SetPoint("TOPLEFT", stubDescription, "BOTTOMLEFT", 0, -15)
stubButton:SetText("Open settings")
stubButton:SetScript("OnClick", function() settingsFrame:Show() end)
if InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(stubPanel)
elseif Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(stubPanel, iRL.DisplayName)
    Settings.RegisterAddOnCategory(category)
end

function iRL:OpenOptions()
    settingsFrame:Show()
end
