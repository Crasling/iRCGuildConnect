local _, private = ...
local iRC = private and private.iRC
if not iRC then return end
local L = iRC.L

-- Blizzard Settings panel and guild-management pages
--
-- Personal options are stored per character/account as appropriate. Synced
-- guild controls write through Core/Connection and are shown read-only when
-- the current character lacks the required permission.

local ORANGE = iRC.ColorValues.Orange
local CHECKBOX_TEMPLATE = InterfaceOptionsCheckButtonTemplate and "InterfaceOptionsCheckButtonTemplate" or "UICheckButtonTemplate"

local function IsAddonLoadedCompat(addonName)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(addonName) end
    return false
end

local function CanUseManagementTools()
    return iRC:HasAnyManagementPermission()
end

local function BuildActiveRulesExplanation()
    if not iRC:IsGuildConnectionActive() then return iRC:Text("RULES_READ_ONLY_INACTIVE") end
    local rules, lines = iRC:GetConnectionRules(), {}
    if rules.classLock == true then
        lines[#lines + 1] = iRC:Text("RULES_READ_ONLY_CLASS_LOCK", iRC:GetClassDisplayName(rules.guildClass))
    end
    if rules.raceLock == true then
        local race = iRC:GetGuildRace()
        lines[#lines + 1] = iRC:Text("RULES_READ_ONLY_RACE_LOCK",
            race ~= "" and iRC:Text("GUILD_RACE_" .. race) or iRC:Text("GUILD_STATS_UNKNOWN_GUILD"))
        if rules.nativeTongueOnly then lines[#lines + 1] = iRC:Text("RULES_READ_ONLY_NATIVE_LANGUAGE") end
    end
    local progression = iRC:GetProgressionMode(rules)
    if progression == "SELF_FOUND" then
        lines[#lines + 1] = iRC:Text("RULES_READ_ONLY_SELF_FOUND")
        if iRC:GetMaxLevelProgressionMode(rules) == "GUILD_FOUND" then
            lines[#lines + 1] = iRC:Text("RULES_READ_ONLY_SWITCH_TO_GUILD_FOUND")
        elseif iRC:GetMaxLevelProgressionMode(rules) == "UNRESTRICTED" then
            lines[#lines + 1] = iRC:Text("RULES_READ_ONLY_UNRESTRICTED_AT_60")
        end
    elseif progression == "GUILD_FOUND" then
        lines[#lines + 1] = iRC:Text("RULES_READ_ONLY_GUILD_FOUND_ONLY")
    elseif progression == "SELF_FOUND_OR_GUILD_FOUND" then
        lines[#lines + 1] = iRC:Text("RULES_READ_ONLY_GUILD_FOUND")
    end
    if rules.guildFoundTradeExceptions then lines[#lines + 1] = iRC:Text("RULES_READ_ONLY_TRADE_EXCEPTIONS") end
    if rules.raceLock == true and rules.sameRaceGroupsOnly then
        local minimumLevel = tonumber(rules.sameRaceMinimumLevel) or 1
        local race = iRC:GetGuildRace()
        local raceName = race ~= "" and iRC:Text("GUILD_RACE_" .. race) or iRC:Text("GUILD_STATS_UNKNOWN_GUILD")
        lines[#lines + 1] = minimumLevel <= 1
            and iRC:Text("RULES_READ_ONLY_SAME_RACE", raceName)
            or iRC:Text("RULES_READ_ONLY_SAME_RACE_LEVEL", minimumLevel, raceName)
        if rules.allowLevel60MixedRaceGroups then lines[#lines + 1] = iRC:Text("RULES_READ_ONLY_MIXED_60") end
    end
    if rules.guildGroupsOnly then lines[#lines + 1] = iRC:Text("RULES_READ_ONLY_GUILD_GROUPS", rules.guildGroupsMinimumLevel or 1) end
    if rules.guildMapEnabled then lines[#lines + 1] = iRC:Text("RULES_READ_ONLY_GUILD_MAP") end
    if rules.enableGuildLevel60Message then
        lines[#lines + 1] = iRC:Text("ENABLE_GUILD_LEVEL60_MESSAGE") .. " (Level "
            .. tostring(rules.guildLevelAnnouncementMinimum or 60) .. "+)"
    end
    if rules.enableGuildProfessionMessage then
        lines[#lines + 1] = iRC:Text("ENABLE_GUILD_PROFESSION_MESSAGE") .. " (from "
            .. tostring(rules.guildProfessionAnnouncementSkill or 300) .. ")"
    end
    if iRC:IsOfficialHardcoreRealm() and rules.enableGuildDeathMessage then
        lines[#lines + 1] = iRC:Text("ENABLE_GUILD_DEATH_MESSAGE")
    end
    if #lines == 0 then return iRC:Text("RULES_READ_ONLY_NONE") end
    for index, line in ipairs(lines) do lines[index] = "|cffffa31a•|r " .. line end
    return table.concat(lines, "\n\n")
end

-- Reusable settings controls ------------------------------------------------

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

local function CreateSyncBadge(parent, yOffset)
    local badge = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    badge:SetSize(38, 17)
    badge:EnableMouse(true)
    badge:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, yOffset - 2)
    badge:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 9,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    badge:SetBackdropColor(0.015, 0.075, 0.16, 0.92)
    badge:SetBackdropBorderColor(0.18, 0.55, 1, 1)
    badge.text = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    badge.text:SetPoint("CENTER", 0, 1)
    badge.text:SetText("Sync")
    badge.text:SetTextColor(0.45, 0.75, 1)
    SetSimpleTooltip(badge, "Sync", "This setting is shared with the guild.")
    return badge
end

local function CreateSettingsCheckbox(parent, label, description, yOffset, getValue, setValue, indent, synced)
    indent = indent or 0
    local checkbox = CreateFrame("CheckButton", nil, parent, CHECKBOX_TEMPLATE)
    local left = (synced and 48 or 20) + indent
    checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", left, yOffset)
    if synced then checkbox.syncBadge = CreateSyncBadge(parent, yOffset) end
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
        desc:SetPoint("TOPLEFT", parent, "TOPLEFT", left + 28, nextY)
        desc:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -18, nextY)
        desc:SetJustifyH("LEFT")
        desc:SetText(description)
        checkbox.description = desc
        local height = math.max(desc:GetStringHeight(), 12)
        nextY = nextY - height - 6
    end
    return checkbox, nextY
end

local function CreateSettingsDropdown(frameName, parent, label, description, yOffset, getValue, setValue, getOptions, getOptionLabel, synced)
    local left = synced and 48 or 20
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", left, yOffset)
    title:SetText(label)
    if synced then CreateSyncBadge(parent, yOffset) end

    -- Classic's enable/disable helpers look up template children by frame name.
    local dropdown = CreateFrame("Frame", frameName, parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", left - 12, yOffset - 15)
    UIDropDownMenu_SetWidth(dropdown, 220)
    UIDropDownMenu_JustifyText(dropdown, "LEFT")
    dropdown.Refresh = function()
        UIDropDownMenu_SetText(dropdown, getOptionLabel(getValue()))
    end
    dropdown.title = title
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
        desc:SetPoint("TOPLEFT", parent, "TOPLEFT", left + 28, nextY)
        desc:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -18, nextY)
        desc:SetJustifyH("LEFT")
        desc:SetText(description)
        dropdown.description = desc
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
    info:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -25, yOffset)
    info:SetJustifyH("LEFT")
    info:SetText(text)
    local height = math.max(info:GetStringHeight(), 14)
    return info, yOffset - height - 6
end

local function CreateConnectionStatusCard(parent, yOffset)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetHeight(112)
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
    detail:SetPoint("RIGHT", card, "RIGHT", -18, 0)
    detail:SetJustifyH("LEFT")

    return { status = status, detail = detail }, yOffset - 122
end

local function CreateManagementSettingsCard(parent, title, description, yOffset)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, yOffset)
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, yOffset)
    card:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    card:SetBackdropColor(0.045, 0.04, 0.035, 0.96)
    card:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.48)

    local accent = card:CreateTexture(nil, "ARTWORK")
    accent:SetWidth(3)
    accent:SetPoint("TOPLEFT", card, "TOPLEFT", 5, -7)
    accent:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 5, 7)
    accent:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.88)

    local heading = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -13)
    heading:SetText(title)

    local body = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    body:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -5)
    body:SetPoint("TOPRIGHT", card, "TOPRIGHT", -18, -36)
    body:SetJustifyH("LEFT")
    body:SetText(description or "")

    return card, -48 - math.max(body:GetStringHeight(), 12)
end

local function CreateCompactManagementRow(parent, yOffset, height)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(height)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, yOffset)
    row:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    row:SetBackdropColor(0.065, 0.055, 0.045, 0.96)
    row:SetBackdropBorderColor(0.34, 0.28, 0.20, 0.92)
    local accent = row:CreateTexture(nil, "ARTWORK")
    accent:SetWidth(2)
    accent:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -5)
    accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 5)
    accent:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.72)
    return row
end

local function CreateCompactManagementToggle(parent, label, description, yOffset, getValue, setValue, synced)
    local rowHeight = 54
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(rowHeight)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, yOffset)
    row:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetPoint("TOPLEFT", 4, -4)
    row.highlight:SetPoint("BOTTOMRIGHT", -4, 4)
    row.highlight:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.08)
    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetWidth(3)
    row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -5)
    row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 5)

    local scopeDivider = row:CreateTexture(nil, "ARTWORK")
    scopeDivider:SetWidth(1)
    scopeDivider:SetPoint("TOPLEFT", row, "TOPLEFT", 72, -7)
    scopeDivider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 72, 7)
    scopeDivider:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.20)

    local scopeBadge = CreateSyncBadge(row, 0)
    scopeBadge:ClearAllPoints()
    scopeBadge:SetPoint("CENTER", row, "LEFT", 37, 0)
    if synced then
        scopeBadge:SetSize(44, 19)
        scopeBadge.text:SetText(iRC:Text("MANAGEMENT_SCOPE_SYNC"))
        SetSimpleTooltip(scopeBadge, iRC:Text("MANAGEMENT_SCOPE_SYNC"), iRC:Text("MANAGEMENT_SCOPE_SYNC_DESC"))
    else
        scopeBadge:SetSize(54, 19)
        scopeBadge:SetBackdropColor(0.025, 0.14, 0.055, 0.92)
        scopeBadge:SetBackdropBorderColor(0.20, 0.78, 0.32, 1)
        scopeBadge.text:SetText(iRC:Text("MANAGEMENT_SCOPE_PERSONAL"))
        scopeBadge.text:SetTextColor(0.38, 1, 0.48)
        SetSimpleTooltip(scopeBadge, iRC:Text("MANAGEMENT_SCOPE_PERSONAL"), iRC:Text("MANAGEMENT_SCOPE_PERSONAL_DESC"))
    end

    local left = 86
    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", left, -9)
    row.title:SetPoint("RIGHT", row, "RIGHT", -112, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetText(label)
    row.description = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.description:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
    row.description:SetPoint("RIGHT", row, "RIGHT", -112, 0)
    row.description:SetHeight(24)
    row.description:SetJustifyH("LEFT")
    row.description:SetJustifyV("TOP")
    row.description:SetWordWrap(true)
    if row.description.SetMaxLines then row.description:SetMaxLines(2) end
    row.description:SetText(description or "")
    row.stateBackground = row:CreateTexture(nil, "ARTWORK")
    row.stateBackground:SetSize(88, 25)
    row.stateBackground:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row.state = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.state:SetPoint("CENTER", row.stateBackground, "CENTER", 0, 0)

    row.Refresh = function(self)
        local active = getValue() and true or false
        self.state:SetText(iRC:Text(active and "GUILDFOUND_STATUS_ENABLED" or "GUILDFOUND_STATUS_DISABLED"):upper())
        self.state:SetTextColor(active and 0.25 or 0.65, active and 1 or 0.65, active and 0.35 or 0.65)
        self.stateBackground:SetColorTexture(active and 0.04 or 0.10, active and 0.24 or 0.085, active and 0.08 or 0.06, 0.86)
        self.accent:SetColorTexture(active and 0.20 or ORANGE[1], active and 0.86 or ORANGE[2], active and 0.30 or ORANGE[3], 0.90)
        self:SetBackdropColor(active and 0.045 or 0.075, active and 0.12 or 0.065, active and 0.055 or 0.05, 0.98)
        self:SetBackdropBorderColor(active and 0.20 or 0.34, active and 0.72 or 0.28, active and 0.27 or 0.20, 1)
    end
    row:SetScript("OnClick", function(self)
        if not self:IsEnabled() then return end
        setValue(not (getValue() and true or false))
        self:Refresh()
    end)
    SetSimpleTooltip(row, label, description)
    row.managementRow = row
    row:Refresh()
    return row, yOffset - rowHeight - 7
end

local managementDropdowns = {}

local function CloseManagementDropdowns(except)
    for _, control in ipairs(managementDropdowns) do
        if control ~= except and control.menu then control.menu:Hide() end
    end
end

local function CreateCompactManagementDropdown(frameName, parent, label, yOffset, getValue, setValue, getOptions,
    getOptionLabel, getAccessNames)
    local rowHeight = getAccessNames and 108 or 54
    local row = CreateCompactManagementRow(parent, yOffset, rowHeight)
    local scopeDivider = row:CreateTexture(nil, "ARTWORK")
    scopeDivider:SetWidth(1)
    scopeDivider:SetPoint("TOPLEFT", row, "TOPLEFT", 72, -7)
    scopeDivider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 72, 7)
    scopeDivider:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.20)
    local scopeBadge = CreateSyncBadge(row, 0)
    scopeBadge:ClearAllPoints()
    scopeBadge:SetPoint("CENTER", row, "LEFT", 37, 0)
    scopeBadge:SetSize(44, 19)
    scopeBadge.text:SetText(iRC:Text("MANAGEMENT_SCOPE_SYNC"))

    local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", row, "TOPLEFT", 86, -10)
    title:SetPoint("RIGHT", row, "RIGHT", -245, 0)
    title:SetJustifyH("LEFT")
    title:SetText(label)
    local description = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    description:SetPoint("RIGHT", row, "RIGHT", -245, 0)
    description:SetJustifyH("LEFT")
    description:SetText("Lowest permitted rank and every rank above it.")

    if getAccessNames then
        row.accessDivider = row:CreateTexture(nil, "ARTWORK")
        row.accessDivider:SetPoint("TOPLEFT", row, "TOPLEFT", 86, -55)
        row.accessDivider:SetPoint("TOPRIGHT", row, "TOPRIGHT", -14, -55)
        row.accessDivider:SetHeight(1)
        row.accessDivider:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.18)
        row.accessLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.accessLabel:SetPoint("TOPLEFT", row, "TOPLEFT", 86, -63)
        row.accessLabel:SetTextColor(0.62, 0.86, 0.62)
        row.access = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.access:SetPoint("TOPLEFT", row.accessLabel, "BOTTOMLEFT", 0, -3)
        row.access:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -14, 8)
        row.access:SetJustifyH("LEFT")
        row.access:SetJustifyV("TOP")
        row.access:SetWordWrap(true)
        if row.access.SetMaxLines then row.access:SetMaxLines(2) end
        row.access:SetTextColor(0.56, 0.78, 0.56)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            if not self.accessTooltipNames or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label)
            if #self.accessTooltipNames == 0 then
                GameTooltip:AddLine("No current roster members have effective access.", 0.72, 0.72, 0.72, true)
            else
                GameTooltip:AddLine("Roster members with effective access:", 1, 1, 1, true)
                for index = 1, #self.accessTooltipNames, 2 do
                    GameTooltip:AddDoubleLine(self.accessTooltipNames[index],
                        self.accessTooltipNames[index + 1] or "", 0.62, 0.86, 0.62, 0.62, 0.86, 0.62)
                end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("* Individual member grant", 0.72, 0.72, 0.72)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end

    local dropdown = CreateFrame("Button", frameName, row, "BackdropTemplate")
    dropdown:SetSize(220, 30)
    if getAccessNames then dropdown:SetPoint("TOPRIGHT", row, "TOPRIGHT", -14, -10)
    else dropdown:SetPoint("RIGHT", row, "RIGHT", -14, 0) end
    dropdown:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 9,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    dropdown:SetBackdropColor(0.035, 0.030, 0.022, 0.99)
    dropdown:SetBackdropBorderColor(0.62, 0.39, 0.10, 1)
    dropdown:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    dropdown.text = dropdown:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dropdown.text:SetPoint("LEFT", dropdown, "LEFT", 11, 0)
    dropdown.text:SetPoint("RIGHT", dropdown, "RIGHT", -30, 0)
    dropdown.text:SetJustifyH("LEFT")
    dropdown.text:SetWordWrap(false)
    dropdown.arrow = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dropdown.arrow:SetPoint("RIGHT", dropdown, "RIGHT", -10, 0)
    dropdown.arrow:SetText("v")
    dropdown.arrow:SetTextColor(1, 0.72, 0.12)

    dropdown.menu = CreateFrame("Frame", frameName .. "Menu", UIParent, "BackdropTemplate")
    dropdown.menu:SetWidth(220)
    dropdown.menu:SetFrameStrata("FULLSCREEN_DIALOG")
    dropdown.menu:SetClampedToScreen(true)
    dropdown.menu:SetToplevel(true)
    dropdown.menu:EnableMouse(true)
    dropdown.menu:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    dropdown.menu:SetBackdropColor(0.018, 0.016, 0.012, 0.995)
    dropdown.menu:SetBackdropBorderColor(0.78, 0.48, 0.12, 1)
    dropdown.menu.buttons = {}
    dropdown.menu:Hide()

    function dropdown:Refresh()
        self.text:SetText(getOptionLabel(getValue()))
        if row.access then
            local names = getAccessNames() or {}
            local shown = {}
            for index = 1, math.min(6, #names) do shown[index] = names[index] end
            local suffix = #names > #shown and ("  |  +" .. tostring(#names - #shown) .. " more") or ""
            row.accessLabel:SetText("Roster access (" .. tostring(#names) .. ")")
            row.access:SetText(#names > 0 and (table.concat(shown, "  |  ") .. suffix)
                or "Nobody currently inherits access.")
            row.accessTooltipNames = names
        end
    end

    function dropdown:RefreshMenu()
        local options = getOptions() or {}
        local currentValue = getValue()
        for index, value in ipairs(options) do
            local selectedValue = value
            local button = self.menu.buttons[index]
            if not button then
                button = CreateFrame("Button", nil, self.menu, "BackdropTemplate")
                button:SetHeight(25)
                button:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
                button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                button.text:SetPoint("LEFT", button, "LEFT", 10, 0)
                button.text:SetPoint("RIGHT", button, "RIGHT", -10, 0)
                button.text:SetJustifyH("LEFT")
                button.check = button:CreateTexture(nil, "ARTWORK")
                button.check:SetWidth(3)
                button.check:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -3)
                button.check:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 3)
                button.check:SetColorTexture(0.25, 1, 0.35, 1)
                button:SetScript("OnEnter", function(menuButton)
                    menuButton:SetBackdropColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.16)
                end)
                button:SetScript("OnLeave", function(menuButton)
                    menuButton:SetBackdropColor(0, 0, 0, menuButton.selected and 0.30 or 0)
                end)
                self.menu.buttons[index] = button
            end
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", self.menu, "TOPLEFT", 5, -5 - ((index - 1) * 25))
            button:SetPoint("TOPRIGHT", self.menu, "TOPRIGHT", -5, -5 - ((index - 1) * 25))
            button.value = selectedValue
            button.selected = selectedValue == currentValue
            button.text:SetText(getOptionLabel(selectedValue))
            button.text:SetTextColor(button.selected and 0.35 or 0.92,
                button.selected and 1 or 0.92, button.selected and 0.42 or 0.92)
            button.check:SetShown(button.selected)
            button:SetBackdropColor(0, 0, 0, button.selected and 0.30 or 0)
            button:SetScript("OnClick", function()
                setValue(selectedValue)
                self:Refresh()
                self.menu:Hide()
            end)
            button:Show()
        end
        for index = #options + 1, #self.menu.buttons do self.menu.buttons[index]:Hide() end
        self.menu:SetHeight(math.max(12, (#options * 25) + 10))
    end

    dropdown:SetScript("OnClick", function(self)
        if not self:IsEnabled() then return end
        if self.menu:IsShown() then
            self.menu:Hide()
            return
        end
        CloseManagementDropdowns(self)
        self:RefreshMenu()
        self.menu:ClearAllPoints()
        local bottom = self:GetBottom() or 0
        local menuHeight = self.menu:GetHeight() or 0
        if bottom > menuHeight + 12 then
            self.menu:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -2)
        else
            self.menu:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", 0, 2)
        end
        self.menu:Show()
    end)
    dropdown:SetScript("OnEnable", function(self)
        self.text:SetTextColor(1, 1, 1)
        self.arrow:SetTextColor(1, 0.72, 0.12)
        self:SetBackdropColor(0.035, 0.030, 0.022, 0.99)
        self:SetBackdropBorderColor(0.62, 0.39, 0.10, 1)
    end)
    dropdown:SetScript("OnDisable", function(self)
        self.menu:Hide()
        self.text:SetTextColor(0.48, 0.48, 0.48)
        self.arrow:SetTextColor(0.48, 0.42, 0.32)
        self:SetBackdropColor(0.025, 0.023, 0.020, 0.92)
        self:SetBackdropBorderColor(0.25, 0.22, 0.18, 0.80)
    end)
    dropdown:HookScript("OnHide", function(self) self.menu:Hide() end)
    managementDropdowns[#managementDropdowns + 1] = dropdown
    dropdown:Refresh()
    dropdown.managementRow = row
    return dropdown, yOffset - rowHeight - 7
end

-- Synchronization status cards ---------------------------------------------

local function FormatRulesetTime(timestamp)
    timestamp = tonumber(timestamp) or 0
    if timestamp <= 0 then return L.RULESET_METADATA_UNKNOWN end
    return date("%Y-%m-%d %H:%M:%S", timestamp)
end

local function GetRulesetMetadataText(connection)
    if not connection then return nil end
    local createdAt = tonumber(tostring(connection.rulesTimestampHex or "0"), 16) or 0
    local createdBy = tostring(connection.rulesTimestampSource or "")
    local relayedBy = tostring(connection.rulesRelayedBy or "")
    if createdBy == "" then createdBy = L.RULESET_METADATA_UNKNOWN end
    if relayedBy == "" then relayedBy = L.RULESET_METADATA_UNKNOWN end
    if iRC:NormalizeName(relayedBy) == iRC:NormalizeName(iRC:GetPlayerName()) then
        relayedBy = L.RULESET_METADATA_LOCAL
    end
    return table.concat({
        iRC:Text("RULESET_CREATED_BY", iRC:FormatPlayerName(createdBy)),
        iRC:Text("RULESET_RELAYED_BY", iRC:FormatPlayerName(relayedBy)),
        iRC:Text("RULESET_CREATED_AT", FormatRulesetTime(createdAt)),
        iRC:Text("RULESET_RECEIVED_AT", FormatRulesetTime(connection.rulesReceivedAt)),
    }, "\n")
end

local managementConnectionCards = {}

local function GetManagementConnectionStatus(connection, category)
    local saved = connection and connection.managementConnectionStatus
        and connection.managementConnectionStatus[category]
    if saved and tonumber(saved.createdAt) and tonumber(saved.createdAt) > 0 then return saved end
    local candidates = {}
    local function addCandidate(source, timestamp)
        timestamp = math.floor(tonumber(timestamp) or 0)
        if timestamp > 0 then candidates[#candidates + 1] = { createdBy = source, createdAt = timestamp } end
    end
    if connection and category == "notifications" then
        addCandidate(connection.guildNotifications and connection.guildNotifications.source,
            connection.guildNotifications and connection.guildNotifications.timestamp)
    elseif connection and category == "permissions" then
        addCandidate("", connection.rankPermissionsTimestamp)
        addCandidate("", connection.guildMasterRankTimestamp)
        for _, entry in pairs(connection.memberPermissions or {}) do
            addCandidate(entry.source, entry.timestamp)
        end
    elseif connection and category == "homepage" then
        addCandidate(connection.guildHomepageDescription and connection.guildHomepageDescription.editedBy,
            connection.guildHomepageDescription and connection.guildHomepageDescription.timestamp)
        addCandidate(connection.guildHomepageIcon and connection.guildHomepageIcon.editedBy,
            connection.guildHomepageIcon and connection.guildHomepageIcon.timestamp)
        addCandidate(connection.guildHomepageTag and connection.guildHomepageTag.editedBy,
            connection.guildHomepageTag and connection.guildHomepageTag.timestamp)
        addCandidate(connection.guildHomepageClassBreakdown and connection.guildHomepageClassBreakdown.editedBy,
            connection.guildHomepageClassBreakdown and connection.guildHomepageClassBreakdown.timestamp)
        addCandidate(connection.guildContactsSource, connection.guildContactsTimestamp)
    elseif connection and category == "guildFound" then
        addCandidate(connection.guildFoundTradeExceptionSettings and connection.guildFoundTradeExceptionSettings.source,
            connection.guildFoundTradeExceptionSettings and connection.guildFoundTradeExceptionSettings.timestamp)
    end
    table.sort(candidates, function(a, b) return a.createdAt > b.createdAt end)
    return candidates[1]
end

local function RefreshManagementConnectionCard(card, category, connection)
    local metadata = GetManagementConnectionStatus(connection, category)
    if not metadata then
        card.status:SetText(iRC.Colors.Gray .. L.MANAGEMENT_CONNECTION_EMPTY .. iRC.Colors.Reset)
        card.detail:SetText("")
        return
    end
    local createdBy = tostring(metadata.createdBy or "")
    local relayedBy = tostring(metadata.relayedBy or "")
    if createdBy == "" then createdBy = L.RULESET_METADATA_UNKNOWN end
    if relayedBy == "" then relayedBy = L.RULESET_METADATA_UNKNOWN end
    if iRC:NormalizeName(relayedBy) == iRC:NormalizeName(iRC:GetPlayerName()) then relayedBy = L.RULESET_METADATA_LOCAL end
    card.status:SetText(iRC.Colors.Green .. L.MANAGEMENT_CONNECTION_READY .. iRC.Colors.Reset)
    card.detail:SetText(table.concat({
        iRC:Text("MANAGEMENT_CREATED_BY", iRC:FormatPlayerName(createdBy)),
        iRC:Text("MANAGEMENT_RELAYED_BY", iRC:FormatPlayerName(relayedBy)),
        iRC:Text("RULESET_CREATED_AT", FormatRulesetTime(metadata.createdAt)),
        iRC:Text("RULESET_RECEIVED_AT", FormatRulesetTime(metadata.receivedAt)),
    }, "\n"))
end

local function RefreshAllManagementConnectionCards(connection)
    for category, card in pairs(managementConnectionCards) do
        RefreshManagementConnectionCard(card, category, connection)
    end
end

local settingsFrame = CreateFrame("Frame", "iRCSettingsFrame", UIParent, "BackdropTemplate")
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

-- Panel construction and sidebar navigation --------------------------------

local function CreateTabContent()
    local container = CreateFrame("Frame", nil, contentArea)
    container:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 5, -5)
    container:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", -5, 5)
    container:Hide()

    local scrollFrame = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
    iRC:StyleScrollFrame(scrollFrame)
    scrollFrame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -22, 0)
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(550)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    container.scrollFrame = scrollFrame
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
local iSTContainer, iSTContent = CreateTabContent()
local guildFoundContainer, guildFoundContent = CreateTabContent()
local adminContainer, adminContent = CreateTabContent()
local guildNotificationsContainer, guildNotificationsContent = CreateTabContent()
local guildHomepageContainer, guildHomepageContent = CreateTabContent()
local diagnosticsContainer, diagnosticsContent, diagnosticsScroll = CreateTabContent()
local guildPermissionsContainer, guildPermissionsContent = CreateTabContent()
local tabContents = { generalContainer, connectionContainer, roleplayContainer, aboutContainer, iWRContainer, iNIFContainer, iSTContainer, guildFoundContainer, adminContainer, guildNotificationsContainer, guildHomepageContainer, diagnosticsContainer, guildPermissionsContainer }
local sidebarButtons = {}
local selectedTab = 2

local function ShowTab(index)
    selectedTab = index
    for tabIndex, tab in ipairs(tabContents) do tab:SetShown(tabIndex == index) end
    for tabIndex, button in pairs(sidebarButtons) do
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
    { type = "tab", label = "Connection & Rules", index = 2 },
}
local standardSidebarItems = {
    { type = "tab", label = "About", index = 4 },
    { type = "tab", label = "Diagnostic Tools", index = 12 },
    { type = "header", label = "Other Addons" },
    { type = "tab", label = "iWillRemember", index = 5 },
    { type = "tab", label = "iNeedIfYouNeed", index = 6 },
    { type = "tab", label = "iSealTwist", index = 7 },
}
for _, item in ipairs(standardSidebarItems) do sidebarItems[#sidebarItems + 1] = item end
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
        item.widget = headerText
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
        button.guildFoundOnly = item.guildFoundOnly
        button.managementOnly = item.managementOnly
        button.homepageOnly = item.homepageOnly
        item.widget = button
        sidebarButtons[item.index] = button
        sidebarY = sidebarY - 28
    end
end

local function LayoutSidebar(managementAvailable)
    local offset = -6
    for _, item in ipairs(sidebarItems) do
        local widget = item.widget
        local restricted = item.managementOnly or item.homepageOnly or item.guildFoundOnly
        local visible = not restricted or managementAvailable
        widget:SetShown(visible)
        if visible then
            widget:ClearAllPoints()
            if item.type == "header" then
                widget:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 12, offset - 2)
                offset = offset - 20
            else
                widget:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 6, offset)
                offset = offset - 28
            end
        end
    end
end

local diagnosticOutput, diagnosticsEnabledCheck
do
    local diagnostics = iRC.Diagnostics
    local diagnosticY = -12
    _, diagnosticY = CreateSectionHeader(diagnosticsContent, "Diagnostic Tools", diagnosticY)
    _, diagnosticY = CreateInfoText(diagnosticsContent,
        "Session-only troubleshooting tools. Nothing is saved. Reports may contain character, guild, and addon names; review them before sharing.",
        diagnosticY, "GameFontDisableSmall")

    diagnosticsEnabledCheck, diagnosticY = CreateSettingsCheckbox(diagnosticsContent, "Enable Diagnostic Tools",
        "Enables bounded event/sync capture, traffic measurement, and function timing until logout or until switched off.", diagnosticY,
        function() return diagnostics and diagnostics.enabled end,
        function(value)
            if not diagnostics then return end
            diagnostics:SetEnabled(value)
            iRC:SetTrafficMonitorEnabled(value)
            iRC:SetFunctionProfilerEnabled(value)
        end)

    local memberLabel = diagnosticsContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    memberLabel:SetPoint("TOPLEFT", diagnosticsContent, "TOPLEFT", 20, diagnosticY)
    memberLabel:SetText("Member name (optional)")
    local memberInput = CreateFrame("EditBox", nil, diagnosticsContent, "InputBoxTemplate")
    memberInput:SetSize(300, 24)
    memberInput:SetPoint("TOPLEFT", diagnosticsContent, "TOPLEFT", 20, diagnosticY - 20)
    memberInput:SetAutoFocus(false)
    memberInput:SetMaxLetters(80)
    local memberSuggestions = CreateFrame("Frame", nil, diagnosticsContent, "BackdropTemplate")
    memberSuggestions:SetSize(300, 128)
    memberSuggestions:SetPoint("TOPLEFT", memberInput, "BOTTOMLEFT", 0, -2)
    memberSuggestions:SetFrameStrata("DIALOG")
    memberSuggestions:SetFrameLevel(diagnosticsContent:GetFrameLevel() + 30)
    memberSuggestions:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    memberSuggestions:SetBackdropColor(0.03, 0.03, 0.03, 0.98)
    memberSuggestions:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.85)
    memberSuggestions:Hide()
    local memberSuggestionButtons = {}
    for index = 1, 5 do
        local button = CreateFrame("Button", nil, memberSuggestions)
        button:SetSize(282, 23)
        button:SetPoint("TOPLEFT", memberSuggestions, "TOPLEFT", 7, -6 - (index - 1) * 23)
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        button.text:SetPoint("LEFT", button, "LEFT", 7, 0)
        button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
        button.highlight:SetAllPoints()
        button.highlight:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.18)
        button:SetScript("OnMouseDown", function(self, mouseButton)
            if mouseButton ~= "LeftButton" then return end
            if not self.fullName then return end
            memberInput:SetText(iRC:FormatPlayerName(self.fullName))
            memberInput:SetCursorPosition(#memberInput:GetText())
            memberInput:ClearFocus()
            memberSuggestions:Hide()
        end)
        memberSuggestionButtons[index] = button
    end
    local function UpdateMemberSuggestions()
        local query = memberInput:GetText():gsub("^%s+", ""):gsub("%s+$", ""):lower()
        local matches, seen = {}, {}
        if query ~= "" and GetNumGuildMembers and GetGuildRosterInfo then
            for rosterIndex = 1, GetNumGuildMembers(true) do
                local rosterName = GetGuildRosterInfo(rosterIndex)
                local displayName = rosterName and iRC:FormatPlayerName(rosterName)
                local key = displayName and displayName:lower()
                if key and not seen[key] and key:find(query, 1, true) then
                    seen[key] = true
                    matches[#matches + 1] = { fullName = rosterName, displayName = displayName,
                        starts = key:find(query, 1, true) == 1 }
                end
            end
            table.sort(matches, function(a, b)
                if a.starts ~= b.starts then return a.starts end
                return a.displayName:lower() < b.displayName:lower()
            end)
        end
        for index, button in ipairs(memberSuggestionButtons) do
            local match = matches[index]
            button.fullName = match and match.fullName or nil
            button:SetShown(match ~= nil)
            if match then button.text:SetText(match.displayName) end
        end
        memberSuggestions:SetShown(memberInput:HasFocus() and matches[1] ~= nil)
    end
    memberInput:SetScript("OnTextChanged", UpdateMemberSuggestions)
    memberInput:SetScript("OnEditFocusGained", UpdateMemberSuggestions)
    memberInput:SetScript("OnEditFocusLost", function(self)
        C_Timer.After(0, function()
            if not self:HasFocus() and not iRC:IsMouseOverFrame(memberSuggestions) then
                memberSuggestions:Hide()
            end
        end)
    end)
    memberInput:SetScript("OnTabPressed", function(self)
        local first = memberSuggestionButtons[1]
        if first and first:IsShown() and first.fullName then
            self:SetText(iRC:FormatPlayerName(first.fullName))
            self:SetCursorPosition(#self:GetText())
            memberSuggestions:Hide()
        end
    end)
    memberInput:SetScript("OnEnterPressed", function(self)
        local first = memberSuggestionButtons[1]
        if first and first:IsShown() and first.fullName then
            self:SetText(iRC:FormatPlayerName(first.fullName))
            self:SetCursorPosition(#self:GetText())
            self:ClearFocus()
            memberSuggestions:Hide()
        else
            self:ClearFocus()
        end
    end)
    memberInput:SetScript("OnEscapePressed", function(self) memberSuggestions:Hide(); self:ClearFocus() end)
    diagnosticY = diagnosticY - 54

    local function SetReport(text)
        if not diagnosticOutput then return end
        diagnosticOutput:SetText(tostring(text or ""))
        diagnosticOutput:SetCursorPosition(0)
        diagnosticOutput:HighlightText(0, 0)
        diagnosticOutput:ClearFocus()
        C_Timer.After(0, function()
            if not diagnosticsContainer:IsShown() then return end
            diagnosticsScroll:UpdateScrollChildRect()
            diagnosticsScroll:SetVerticalScroll(math.max(0,
                diagnosticsContent:GetHeight() - diagnosticsScroll:GetHeight()))
        end)
    end

    local function AddGroupLabel(text, yOffset)
        local label = diagnosticsContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", diagnosticsContent, "TOPLEFT", 20, diagnosticY + yOffset)
        label:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
        label:SetText(text)
    end

    local function AddButton(text, column, yOffset, callback)
        local button = CreateFrame("Button", nil, diagnosticsContent, "UIPanelButtonTemplate")
        button:SetSize(240, 25)
        button:SetPoint("TOPLEFT", diagnosticsContent, "TOPLEFT", 20 + column * 250, diagnosticY + yOffset)
        button:SetText(text)
        button:SetScript("OnClick", callback)
        return button
    end

    AddGroupLabel("Capture", 0)
    AddButton("Start event / sync log", 0, -22, function()
        if diagnostics and diagnostics:StartLog() then SetReport("Capture started. Reproduce the problem, then use Show captured log.") end
    end)
    AddButton("Stop capture", 1, -22, function()
        if diagnostics then diagnostics:StopLog(); SetReport("Capture stopped. Captured data is retained until diagnostics are disabled.") end
    end)
    AddButton("Show captured log", 0, -51, function() if diagnostics then SetReport(diagnostics:BuildLogReport()) end end)
    AddButton("Clear captured log", 1, -51, function()
        if diagnostics then diagnostics:DiscardLog(); SetReport("Captured diagnostic data cleared.") end
    end)

    AddGroupLabel("Reports", -88)
    AddButton("Connection health", 0, -110, function() if diagnostics then SetReport(diagnostics:BuildHealthReport()) end end)
    AddButton("Diagnose member", 1, -110, function() if diagnostics then SetReport(diagnostics:BuildMemberReport(memberInput:GetText())) end end)
    AddButton("Cache inventory", 0, -139, function() if diagnostics then SetReport(diagnostics:BuildCacheReport()) end end)
    AddButton("Performance report", 1, -139, function() if diagnostics then SetReport(diagnostics:BuildPerformanceReport()) end end)
    AddButton("Test WoW API endpoints", 0, -168, function() if diagnostics then SetReport(diagnostics:BuildApiReport()) end end)
    AddButton("Test event registration", 1, -168, function() if diagnostics then SetReport(diagnostics:BuildEventReport()) end end)
    AddButton("Loaded addons", 0, -197, function() if diagnostics then SetReport(diagnostics:BuildAddOnReport()) end end)
    AddButton("Build complete bug report", 1, -197, function() if diagnostics then SetReport(diagnostics:BuildBugReport(memberInput:GetText())) end end)

    AddGroupLabel("Advanced", -234)
    AddButton("Enable verbose taint log", 0, -256, function()
        if diagnostics then diagnostics:SetTaintLog(true); SetReport("Taint logging set to 2. Reload before reproducing the protected-action problem. Logs are written to Logs\\taint.log.") end
    end)
    AddButton("Disable taint log", 1, -256, function()
        if diagnostics then diagnostics:SetTaintLog(false); SetReport("Taint logging disabled.") end
    end)
    diagnosticY = diagnosticY - 295

    local outputFrame = CreateFrame("Frame", nil, diagnosticsContent, "BackdropTemplate")
    outputFrame:SetPoint("TOPLEFT", diagnosticsContent, "TOPLEFT", 16, diagnosticY)
    outputFrame:SetSize(510, 390)
    outputFrame:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    outputFrame:SetBackdropColor(0.015, 0.015, 0.02, 0.95)
    outputFrame:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.55)
    local outputScroll = CreateFrame("ScrollFrame", nil, outputFrame, "UIPanelScrollFrameTemplate")
    iRC:StyleScrollFrame(outputScroll)
    outputScroll:SetPoint("TOPLEFT", 8, -8)
    outputScroll:SetPoint("BOTTOMRIGHT", -28, 8)
    diagnosticOutput = CreateFrame("EditBox", nil, outputScroll)
    diagnosticOutput:SetMultiLine(true)
    diagnosticOutput:SetAutoFocus(false)
    diagnosticOutput:SetFontObject("GameFontHighlightSmall")
    diagnosticOutput:SetWidth(460)
    diagnosticOutput:SetHeight(360)
    diagnosticOutput:SetTextInsets(4, 4, 4, 4)
    diagnosticOutput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    diagnosticOutput:SetScript("OnEditFocusLost", function(self)
        self.copyShortcutDown = nil
        self:HighlightText(0, 0)
    end)
    diagnosticOutput:SetScript("OnKeyDown", function(self, key)
        self.copyShortcutDown = tostring(key or ""):upper() == "C"
            and IsControlKeyDown and IsControlKeyDown() or false
    end)
    diagnosticOutput:SetScript("OnKeyUp", function(self, key)
        if tostring(key or ""):upper() ~= "C" or not self.copyShortcutDown then return end
        self.copyShortcutDown = nil
        self:HighlightText(0, 0)
        self:ClearFocus()
    end)
    diagnosticOutput:SetScript("OnTextChanged", function(self)
        local lineCount = 1
        for _ in tostring(self:GetText() or ""):gmatch("\n") do lineCount = lineCount + 1 end
        self:SetHeight(math.max(360, lineCount * 14 + 20))
        outputScroll:UpdateScrollChildRect()
    end)
    outputScroll:SetScrollChild(diagnosticOutput)
    diagnosticOutput:SetText("Enable Diagnostic Tools, then choose a report.")

    local copyLogButton = CreateFrame("Button", nil, diagnosticsContent, "UIPanelButtonTemplate")
    copyLogButton:SetSize(150, 25)
    copyLogButton:SetPoint("TOPRIGHT", outputFrame, "BOTTOMRIGHT", 0, -8)
    copyLogButton:SetText("Copy Log")
    copyLogButton:SetScript("OnClick", function()
        diagnosticOutput:SetFocus()
        diagnosticOutput:HighlightText()
    end)
    local copyHint = diagnosticsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    copyHint:SetPoint("RIGHT", copyLogButton, "LEFT", -10, 0)
    copyHint:SetText("Press Ctrl+C to copy")
    diagnosticsContent:SetHeight(math.abs(diagnosticY) + 455)
end

local y = -12
local debugModeCheck
_, y = CreateSectionHeader(generalContent, "Personal Characters", y - 4)
generalContent.identityMainDropdown, y = CreateSettingsDropdown("iRCPersonalMainDropdown", generalContent, "Main character",
    "Characters you log into while they belong to this guild are added automatically. You can also add or remove a character from the Guild Members right-click menu.", y,
    function() return iRC.Identity and iRC.Identity:GetMainName() or "" end,
    function(value) if iRC.Identity then iRC.Identity:SetMain(value) end end,
    function()
        if iRC.Identity then iRC.Identity:RegisterCharacter(iRC:GetPlayerName()) end
        local options = {}
        for _, character in ipairs(iRC.Identity and iRC.Identity:GetCharacters() or {}) do options[#options + 1] = character.name end
        return options
    end,
    function(value) return value ~= "" and value or "No character registered" end)
_, y = CreateSectionHeader(generalContent, "Minimap Settings", y - 4)
local minimapCheck
minimapCheck, y = CreateSettingsCheckbox(generalContent, "Show minimap button", "Show or hide the iRC button by your minimap.", y,
    function() return not iRC:GetSettings().minimapButton.hide end,
    function(value)
        iRC:GetSettings().minimapButton.hide = not value
        if iRC.Minimap then iRC.Minimap:UpdateVisibility() end
    end)
_, y = CreateSectionHeader(generalContent, L.GUILD_MAP_PERSONAL_HEADER, y - 4)
local layerPanelCheck
layerPanelCheck, y = CreateSettingsCheckbox(generalContent, L.LAYER_PANEL_SHOW, L.LAYER_PANEL_SHOW_DESC, y,
    function() return iRC:GetSettings().showLayerPanel ~= false end,
    function(value)
        if iRC.GuildMap then iRC.GuildMap:SetLayerPanelShown(value)
        else iRC:GetSettings().showLayerPanel = value and true or false end
    end)
local pinSizeLabel = generalContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
pinSizeLabel:SetPoint("TOPLEFT", generalContent, "TOPLEFT", 20, y)
pinSizeLabel:SetText(L.GUILD_MAP_PIN_SIZE)
local pinSizeValue = generalContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
pinSizeValue:SetPoint("LEFT", pinSizeLabel, "RIGHT", 10, 0)
pinSizeValue:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
local pinSizeSlider = CreateFrame("Slider", "iRCGuildMapPinSizeSlider", generalContent, "OptionsSliderTemplate")
pinSizeSlider:SetPoint("TOPLEFT", generalContent, "TOPLEFT", 20, y - 22)
pinSizeSlider:SetWidth(240)
pinSizeSlider:SetMinMaxValues(5, 15)
pinSizeSlider:SetValueStep(1)
_G[pinSizeSlider:GetName() .. "Low"]:SetText("5")
_G[pinSizeSlider:GetName() .. "High"]:SetText("15")
_G[pinSizeSlider:GetName() .. "Text"]:SetText("")
SetSimpleTooltip(pinSizeSlider, L.GUILD_MAP_PIN_SIZE, L.GUILD_MAP_PIN_SIZE_DESC)
pinSizeSlider:SetScript("OnValueChanged", function(_, value)
    value = math.floor(value + 0.5)
    pinSizeValue:SetText(tostring(value))
    if iRC.GuildMap then iRC.GuildMap:SetPinSize(value) else iRC:GetSettings().guildMapPinSize = value end
end)
pinSizeSlider:SetValue(math.max(5, math.min(15, math.floor(tonumber(iRC:GetSettings().guildMapPinSize) or 12))))
y = y - 74
_, y = CreateSectionHeader(generalContent, L.CHAT_ICON_HEADER, y - 4)
local hideChatIconCheck
hideChatIconCheck, y = CreateSettingsCheckbox(generalContent, L.HIDE_MY_CHAT_ICON, L.HIDE_MY_CHAT_ICON_DESC, y,
    function() return iRCCharDB and iRCCharDB.hideChatIcon == true end,
    function(value)
        if iRC.GuildAnnouncements then iRC.GuildAnnouncements:SetHidden(value) end
    end)
local hideAllChatIconsCheck
hideAllChatIconsCheck, y = CreateSettingsCheckbox(generalContent, L.HIDE_ALL_CHAT_ICONS, L.HIDE_ALL_CHAT_ICONS_DESC, y,
    function() return iRCCharDB and iRCCharDB.hideAllChatIcons == true end,
    function(value)
        iRCCharDB = iRCCharDB or {}
        iRCCharDB.hideAllChatIcons = value and true or false
    end)
_, y = CreateSectionHeader(generalContent, L.IRC_MAIN_WINDOW_SETTINGS, y - 4)
local scaleLabel = generalContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
scaleLabel:SetPoint("TOPLEFT", generalContent, "TOPLEFT", 20, y)
scaleLabel:SetText(L.IRC_MAIN_WINDOW_SCALE)
local scaleValue = generalContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
scaleValue:SetPoint("LEFT", scaleLabel, "RIGHT", 10, 0)
scaleValue:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
local slider = CreateFrame("Slider", "iRCMainWindowScaleSlider", generalContent, "OptionsSliderTemplate")
slider:SetPoint("TOPLEFT", generalContent, "TOPLEFT", 20, y - 22)
slider:SetWidth(240)
slider:SetMinMaxValues(0.6, 2.0)
slider:SetValueStep(0.05)
_G[slider:GetName() .. "Low"]:SetText("60%")
_G[slider:GetName() .. "High"]:SetText("200%")
_G[slider:GetName() .. "Text"]:SetText("")
SetSimpleTooltip(slider, L.IRC_MAIN_WINDOW_SCALE, L.IRC_MAIN_WINDOW_SCALE_DESC)
slider:SetScript("OnValueChanged", function(_, value)
    value = math.floor(value * 20 + 0.5) / 20
    iRC:GetSettings().mainWindowScale = value
    scaleValue:SetText(math.floor(value * 100 + 0.5) .. "%")
    if iRC.MainUI and iRC.MainUI.frame then iRC.MainUI.frame:SetScale(value) end
end)
y = y - 74
_, y = CreateSettingsButton(generalContent, L.IRC_MAIN_OPEN, 180, y, function() iRC.MainUI:Open(nil, true) end, L.IRC_MAIN_OPEN_DESC)
_, y = CreateSettingsButton(generalContent, L.IRC_MAIN_WINDOW_RESET, 220, y, function()
    local mainFrame = iRC.MainUI:Create()
    mainFrame:ClearAllPoints()
    mainFrame:SetPoint("CENTER")
    iRC:Print(L.MAIN_WINDOW_RESET_DONE)
end, L.IRC_MAIN_WINDOW_RESET_DESC)
generalContent:SetHeight(math.abs(y) + 20)

y = -12
_, y = CreateSectionHeader(connectionContent, "Guild Connection", y)
local connectionCard
connectionCard, y = CreateConnectionStatusCard(connectionContent, y)
local connectionStatus, connectionDetail = connectionCard.status, connectionCard.detail
_, y = CreateInfoText(connectionContent, "Your guild shares rules, roster status, and statistics through iRC.", y - 2, "GameFontDisableSmall")
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
CreateSettingsButton(connectionContent, L.FORCE_GUILD_SYNC, 210, connectionActionsY - 34, function()
    iRC:ForceGuildSync()
end, L.FORCE_GUILD_SYNC_DESC)
y = connectionActionsY - 70
local rulesEditorTopY = y - 2

local guildRulesStatus
local guildActivationCheck, progressionModeDropdown, maxLevelProgressionDropdown, guildFoundTradeExceptionsCheck, guildMapRuleCheck, levelAnnouncementDropdown, professionAnnouncementDropdown, sameRaceLevelSlider, guildGroupsOnlyCheck, guildGroupsLevelSlider
local raceRuleUI = {}
local homepageDescriptionUI = {}
y = select(2, CreateSectionHeader(connectionContent, "Guild Enforced Rules", y - 2))
guildRulesStatus, y = CreateInfoText(connectionContent, "", y, "GameFontHighlight")
_, y = CreateInfoText(connectionContent, L.GUILD_RULES_INTRO, y, "GameFontDisableSmall")
guildActivationCheck, y = CreateSettingsCheckbox(connectionContent, L.GUILD_ACTIVATION_LABEL, L.GUILD_ACTIVATION_DESC, y,
    function() return iRC:IsGuildConnectionActive() end,
    function(value)
        if not value and iRC.MainUI and iRC.MainUI.ConfirmDisableGuildConnection then
            iRC.MainUI:ConfirmDisableGuildConnection()
            guildActivationCheck:Refresh()
            return
        end
        iRC:SetGuildConnectionActive(value)
    end, nil, true)
_, y = CreateSubcategoryHeader(connectionContent, "Class Rules", y - 2)
raceRuleUI.classLock, y = CreateSettingsCheckbox(connectionContent, L.CLASS_LOCK_RULE, L.CLASS_LOCK_RULE_DESC, y,
    function() return iRC:GetConnectionRules().classLock == true end,
    function(value) iRC:SetConnectionRule("classLock", value) end, nil, true)
_, y = CreateSubcategoryHeader(connectionContent, "Race Rules", y - 2)
raceRuleUI.lock, y = CreateSettingsCheckbox(connectionContent, L.RACE_LOCK_RULE, L.RACE_LOCK_RULE_DESC, y,
    function() return iRC:GetConnectionRules().raceLock end,
    function(value) iRC:SetConnectionRule("raceLock", value) end, nil, true)
raceRuleUI.race, y = CreateSettingsDropdown("iRCGuildRaceDropdown", connectionContent, L.GUILD_RACE_LABEL, L.GUILD_RACE_DESC, y,
    function() return iRC:GetGuildRace() end,
    function(value) iRC:SetGuildRace(value) end,
    function() return iRC:GetAvailableGuildRaces() end,
    function(value) return iRC:Text("GUILD_RACE_" .. value) end, true)
raceRuleUI.language, y = CreateSettingsCheckbox(connectionContent, "Native language chat", "Forces your chat boxes to use your character's racial language when you send a message.", y,
    function() return iRC:GetConnectionRules().nativeTongueOnly end,
    function(value) iRC:SetConnectionRule("nativeTongueOnly", value) end, nil, true)
_, y = CreateSubcategoryHeader(connectionContent, "Group Rules", y - 2)
raceRuleUI.groups, y = CreateSettingsCheckbox(connectionContent, "Same-race groups only", "Warn the group and leave any party or raid that includes a different race.", y,
    function() return iRC:GetConnectionRules().sameRaceGroupsOnly end,
    function(value) iRC:SetConnectionRule("sameRaceGroupsOnly", value) end, nil, true)
local sameRaceLevelLabel = connectionContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
CreateSyncBadge(connectionContent, y)
sameRaceLevelLabel:SetPoint("TOPLEFT", connectionContent, "TOPLEFT", 58, y)
sameRaceLevelLabel:SetText(L.SAME_RACE_MINIMUM_LEVEL)
local sameRaceLevelValue = connectionContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
sameRaceLevelValue:SetPoint("LEFT", sameRaceLevelLabel, "RIGHT", 8, 0)
sameRaceLevelValue:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
sameRaceLevelSlider = CreateFrame("Slider", "iRCSameRaceMinimumLevelSlider", connectionContent, "OptionsSliderTemplate")
sameRaceLevelSlider:SetPoint("TOPLEFT", connectionContent, "TOPLEFT", 58, y - 22)
sameRaceLevelSlider:SetWidth(220)
sameRaceLevelSlider:SetMinMaxValues(1, 60)
sameRaceLevelSlider:SetValueStep(1)
_G[sameRaceLevelSlider:GetName() .. "Low"]:SetText("1")
_G[sameRaceLevelSlider:GetName() .. "High"]:SetText("60")
_G[sameRaceLevelSlider:GetName() .. "Text"]:SetText("")
SetSimpleTooltip(sameRaceLevelSlider, L.SAME_RACE_MINIMUM_LEVEL, L.SAME_RACE_MINIMUM_LEVEL_DESC)
local refreshingSameRaceLevel = false
sameRaceLevelSlider:SetScript("OnValueChanged", function(_, value)
    value = math.floor(value + 0.5)
    sameRaceLevelValue:SetText(tostring(value))
    if not refreshingSameRaceLevel then iRC:SetSameRaceMinimumLevel(value) end
end)
y = y - 66
raceRuleUI.level60Exception, y = CreateSettingsCheckbox(connectionContent, "Level 60 Mixed-Race Exception", "At level 60, allow mixed-race parties and raids. Same-race groups remain required while leveling.", y,
    function() return iRC:GetConnectionRules().allowLevel60MixedRaceGroups end,
    function(value) iRC:SetConnectionRule("allowLevel60MixedRaceGroups", value) end, 18, true)
guildGroupsOnlyCheck, y = CreateSettingsCheckbox(connectionContent, L.GUILD_GROUPS_ONLY, L.GUILD_GROUPS_ONLY_DESC, y,
    function() return iRC:GetConnectionRules().guildGroupsOnly end,
    function(value) iRC:SetConnectionRule("guildGroupsOnly", value) end, nil, true)
local guildGroupsLevelLabel = connectionContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
CreateSyncBadge(connectionContent, y)
guildGroupsLevelLabel:SetPoint("TOPLEFT", connectionContent, "TOPLEFT", 58, y)
guildGroupsLevelLabel:SetText(L.GUILD_GROUPS_MINIMUM_LEVEL)
local guildGroupsLevelValue = connectionContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
guildGroupsLevelValue:SetPoint("LEFT", guildGroupsLevelLabel, "RIGHT", 8, 0)
guildGroupsLevelValue:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
guildGroupsLevelSlider = CreateFrame("Slider", "iRCGuildGroupsMinimumLevelSlider", connectionContent, "OptionsSliderTemplate")
guildGroupsLevelSlider:SetPoint("TOPLEFT", connectionContent, "TOPLEFT", 58, y - 22)
guildGroupsLevelSlider:SetWidth(220)
guildGroupsLevelSlider:SetMinMaxValues(1, 60)
guildGroupsLevelSlider:SetValueStep(1)
_G[guildGroupsLevelSlider:GetName() .. "Low"]:SetText("1")
_G[guildGroupsLevelSlider:GetName() .. "High"]:SetText("60")
_G[guildGroupsLevelSlider:GetName() .. "Text"]:SetText("")
SetSimpleTooltip(guildGroupsLevelSlider, L.GUILD_GROUPS_MINIMUM_LEVEL, L.GUILD_GROUPS_MINIMUM_LEVEL_DESC)
local refreshingGuildGroupsLevel = false
guildGroupsLevelSlider:SetScript("OnValueChanged", function(_, value)
    value = math.floor(value + 0.5)
    guildGroupsLevelValue:SetText(tostring(value))
    if not refreshingGuildGroupsLevel then iRC:SetGuildGroupsMinimumLevel(value) end
end)
y = y - 66
_, y = CreateSubcategoryHeader(connectionContent, "Progression Rules", y - 2)
progressionModeDropdown, y = CreateSettingsDropdown("iRCProgressionModeDropdown", connectionContent,
    L.PROGRESSION_MODE, L.PROGRESSION_MODE_DESC, y,
    function() return iRC:GetProgressionMode() end,
    function(value) iRC:SetProgressionMode(value) end,
    function() return { "NONE", "SELF_FOUND", "GUILD_FOUND", "SELF_FOUND_OR_GUILD_FOUND" } end,
    function(value)
        if value == "SELF_FOUND" then return L.PROGRESSION_SELF_FOUND end
        if value == "GUILD_FOUND" then return L.PROGRESSION_GUILD_FOUND end
        if value == "SELF_FOUND_OR_GUILD_FOUND" then return L.PROGRESSION_HYBRID end
        return L.PROGRESSION_NONE
    end, true)
maxLevelProgressionDropdown, y = CreateSettingsDropdown("iRCMaxLevelProgressionDropdown", connectionContent,
    L.PROGRESSION_MAX_LEVEL, L.PROGRESSION_MAX_LEVEL_DESC, y,
    function() return iRC:GetMaxLevelProgressionMode() end,
    function(value) iRC:SetMaxLevelProgressionMode(value) end,
    function() return { "SELF_FOUND", "GUILD_FOUND", "UNRESTRICTED" } end,
    function(value)
        if value == "GUILD_FOUND" then return L.PROGRESSION_MAX_GUILD_FOUND end
        if value == "UNRESTRICTED" then return L.PROGRESSION_MAX_UNRESTRICTED end
        return L.PROGRESSION_MAX_SELF_FOUND
    end, true)
guildFoundTradeExceptionsCheck, y = CreateSettingsCheckbox(connectionContent,
    L.GUILD_FOUND_TRADE_EXCEPTIONS_RULE, L.GUILD_FOUND_TRADE_EXCEPTIONS_RULE_DESC, y,
    function() return iRC:GetConnectionRules().guildFoundTradeExceptions end,
    function(value) iRC:SetConnectionRule("guildFoundTradeExceptions", value) end, nil, true)
_, y = CreateSubcategoryHeader(connectionContent, "Miscellaneous", y - 2)
guildMapRuleCheck, y = CreateSettingsCheckbox(connectionContent,
    L.GUILD_MAP_RULE, L.GUILD_MAP_RULE_DESC, y,
    function() return iRC:GetConnectionRules().guildMapEnabled end,
    function(value) iRC:SetConnectionRule("guildMapEnabled", value) end, nil, true)
raceRuleUI.level60Message, y = CreateSettingsCheckbox(connectionContent,
    L.ENABLE_GUILD_LEVEL60_MESSAGE, L.ENABLE_GUILD_LEVEL60_MESSAGE_DESC, y,
    function() return iRC:GetConnectionRules().enableGuildLevel60Message == true end,
    function(value) iRC:SetConnectionRule("enableGuildLevel60Message", value) end, nil, true)
levelAnnouncementDropdown, y = CreateSettingsDropdown("iRCLevelAnnouncementTargetDropdown", connectionContent,
    "First announced level", "Choose the first 10-level milestone announced in Guild Chat.", y,
    function() return iRC:GetConnectionRules().guildLevelAnnouncementMinimum or 60 end,
    function(value) iRC:SetGuildAnnouncementTarget("guildLevelAnnouncementMinimum", value) end,
    function() return { 10, 20, 30, 40, 50, 60 } end,
    function(value) return "Level " .. tostring(value) end, true)
raceRuleUI.professionMessage, y = CreateSettingsCheckbox(connectionContent,
    L.ENABLE_GUILD_PROFESSION_MESSAGE, L.ENABLE_GUILD_PROFESSION_MESSAGE_DESC, y,
    function() return iRC:GetConnectionRules().enableGuildProfessionMessage == true end,
    function(value) iRC:SetConnectionRule("enableGuildProfessionMessage", value) end, nil, true)
professionAnnouncementDropdown, y = CreateSettingsDropdown("iRCProfessionAnnouncementTargetDropdown", connectionContent,
    "First announced profession milestone", "Choose the first 75-skill milestone announced in Guild Chat.", y,
    function() return iRC:GetConnectionRules().guildProfessionAnnouncementSkill or 300 end,
    function(value) iRC:SetGuildAnnouncementTarget("guildProfessionAnnouncementSkill", value) end,
    function() return { 75, 150, 225, 300 } end,
    function(value) return tostring(value) end, true)
raceRuleUI.deathMessage, y = CreateSettingsCheckbox(connectionContent,
    L.ENABLE_GUILD_DEATH_MESSAGE, L.ENABLE_GUILD_DEATH_MESSAGE_DESC, y,
    function() return iRC:GetConnectionRules().enableGuildDeathMessage == true end,
    function(value) iRC:SetConnectionRule("enableGuildDeathMessage", value) end, nil, true)
local deathMessageBottomY = y
connectionContent:SetHeight(math.abs(y) + 20)

raceRuleUI.readOnly = CreateFrame("Frame", nil, connectionContent, "BackdropTemplate")
local readOnlyRules = raceRuleUI.readOnly
readOnlyRules:SetPoint("TOPLEFT", connectionContent, "TOPLEFT", 0, rulesEditorTopY)
readOnlyRules:SetPoint("TOPRIGHT", connectionContent, "TOPRIGHT", 0, rulesEditorTopY)
readOnlyRules:SetHeight(math.abs(y - rulesEditorTopY) + 24)
readOnlyRules:SetFrameLevel(connectionContent:GetFrameLevel() + 20)
readOnlyRules:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
readOnlyRules:SetBackdropColor(0.025, 0.022, 0.018, 1)
readOnlyRules.header = readOnlyRules:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
readOnlyRules.header:SetPoint("TOPLEFT", 20, -18)
readOnlyRules.header:SetText(L.RULES_READ_ONLY_HEADER)
readOnlyRules.header:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
readOnlyRules.intro = readOnlyRules:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
readOnlyRules.intro:SetPoint("TOPLEFT", readOnlyRules.header, "BOTTOMLEFT", 0, -8)
readOnlyRules.intro:SetWidth(470); readOnlyRules.intro:SetJustifyH("LEFT"); readOnlyRules.intro:SetWordWrap(true)
readOnlyRules.intro:SetText(L.RULES_READ_ONLY_DESC)
readOnlyRules.rules = readOnlyRules:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
readOnlyRules.rules:SetPoint("TOPLEFT", readOnlyRules.intro, "BOTTOMLEFT", 0, -18)
readOnlyRules.rules:SetWidth(470); readOnlyRules.rules:SetJustifyH("LEFT"); readOnlyRules.rules:SetJustifyV("TOP"); readOnlyRules.rules:SetWordWrap(true)

local tradeExceptionPopup = CreateFrame("Frame", "iRCTradeExceptionReadOnlyPopup", UIParent, "BackdropTemplate")
tradeExceptionPopup:SetSize(500, 410)
tradeExceptionPopup:SetPoint("CENTER", UIParent, "CENTER", 0, 10)
tradeExceptionPopup:SetFrameStrata("FULLSCREEN_DIALOG")
tradeExceptionPopup:SetClampedToScreen(true)
tradeExceptionPopup:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 } })
tradeExceptionPopup:SetBackdropColor(0.012, 0.010, 0.008, 1)
tradeExceptionPopup:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.9)
tradeExceptionPopup:EnableMouse(true)
tradeExceptionPopup:Hide()
tinsert(UISpecialFrames, tradeExceptionPopup:GetName())

tradeExceptionPopup.title = tradeExceptionPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
tradeExceptionPopup.title:SetPoint("TOPLEFT", 22, -18)
tradeExceptionPopup.title:SetText(L.RULES_TRADE_EXCEPTIONS_POPUP_TITLE)
tradeExceptionPopup.title:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
tradeExceptionPopup.description = tradeExceptionPopup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
tradeExceptionPopup.description:SetPoint("TOPLEFT", tradeExceptionPopup.title, "BOTTOMLEFT", 0, -8)
tradeExceptionPopup.description:SetWidth(445)
tradeExceptionPopup.description:SetJustifyH("LEFT")
tradeExceptionPopup.description:SetWordWrap(true)
tradeExceptionPopup.description:SetText(L.RULES_TRADE_EXCEPTIONS_POPUP_DESC)
local tradeExceptionClose = CreateFrame("Button", nil, tradeExceptionPopup, "UIPanelCloseButton")
tradeExceptionClose:SetPoint("TOPRIGHT", -5, -5)
tradeExceptionClose:SetScript("OnClick", function() tradeExceptionPopup:Hide() end)
local tradeExceptionScroll = CreateFrame("ScrollFrame", nil, tradeExceptionPopup, "UIPanelScrollFrameTemplate")
iRC:StyleScrollFrame(tradeExceptionScroll)
tradeExceptionScroll:SetPoint("TOPLEFT", 20, -78)
tradeExceptionScroll:SetPoint("BOTTOMRIGHT", -34, 18)
local tradeExceptionContent = CreateFrame("Frame", nil, tradeExceptionScroll)
tradeExceptionContent:SetWidth(430)
tradeExceptionContent:SetHeight(1)
tradeExceptionScroll:SetScrollChild(tradeExceptionContent)
local tradeExceptionDisplayRows = {}

-- Guild rules and Guild-Found exceptions -----------------------------------

local function GetActiveTradeExceptionGroups()
    local rules, settings = iRC:GetConnectionRules(), iRC:GetGuildFoundTradeExceptionSettings()
    if not rules.guildFoundTradeExceptions then return {} end
    local definitions = {
        { setting = "conjured", items = "conjured", label = L.GUILD_FOUND_EXCEPTION_CONJURED },
        { setting = "healthstones", items = "healthstones", label = L.GUILD_FOUND_EXCEPTION_HEALTHSTONES },
        { setting = "questItems", items = "questItems", label = L.GUILD_FOUND_EXCEPTION_QUEST_ITEMS },
        { setting = "lockpickOutgoing", items = "lockpickOutgoing", label = L.GUILD_FOUND_EXCEPTION_LOCKPICK_OUT },
        { setting = "lockpickIncoming", items = "lockpickIncoming", label = L.GUILD_FOUND_EXCEPTION_LOCKPICK_IN },
    }
    local groups = {}
    for _, definition in ipairs(definitions) do
        local items = {}
        if settings[definition.setting] == true then
            for _, itemId in ipairs(iRC.GuildFoundTradeExceptionItems[definition.items] or {}) do
                if settings.items and settings.items[definition.items] and settings.items[definition.items][itemId] then
                    items[#items + 1] = itemId
                end
            end
        end
        if #items > 0 then groups[#groups + 1] = { label = definition.label, items = items } end
    end
    return groups
end

local function RefreshTradeExceptionPopup(groups)
    for _, row in ipairs(tradeExceptionDisplayRows) do row:Hide() end
    local yOffset, rowIndex = 0, 0
    local function acquireRow(isHeader)
        rowIndex = rowIndex + 1
        local row = tradeExceptionDisplayRows[rowIndex]
        if not row then
            row = CreateFrame("Frame", nil, tradeExceptionContent)
            row:SetSize(415, 22)
            row.marker = row:CreateTexture(nil, "ARTWORK")
            row.marker:SetSize(8, 8); row.marker:SetPoint("LEFT", 0, 0); row.marker:SetColorTexture(0.15, 0.9, 0.2, 1)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            tradeExceptionDisplayRows[rowIndex] = row
        end
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", isHeader and 4 or 8, -yOffset)
        row.marker:SetShown(not isHeader)
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", isHeader and row or row.marker, isHeader and "LEFT" or "RIGHT", isHeader and 0 or 8, 0)
        row.text:SetFontObject(isHeader and GameFontNormal or GameFontHighlightSmall)
        row.text:SetTextColor(isHeader and ORANGE[1] or 1, isHeader and ORANGE[2] or 1, isHeader and ORANGE[3] or 1)
        row:Show()
        return row
    end
    for _, group in ipairs(groups or GetActiveTradeExceptionGroups()) do
        local header = acquireRow(true)
        header.text:SetText(group.label)
        yOffset = yOffset + 22
        for _, itemId in ipairs(group.items) do
            local row = acquireRow(false)
            local itemName = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(itemId)
            row.text:SetText((itemName or iRC.GuildFoundTradeExceptionItemNames[itemId] or "Unknown item") .. " (" .. itemId .. ")")
            yOffset = yOffset + 23
        end
        yOffset = yOffset + 8
    end
    if yOffset == 0 then
        local empty = acquireRow(true)
        empty.text:SetFontObject(GameFontDisable)
        empty.text:SetTextColor(0.5, 0.5, 0.5)
        empty.text:SetText(L.RULES_TRADE_EXCEPTIONS_POPUP_EMPTY)
        yOffset = 24
    end
    tradeExceptionContent:SetHeight(math.max(1, yOffset))
end

readOnlyRules.tradeExceptionsButton = CreateFrame("Button", nil, readOnlyRules, "UIPanelButtonTemplate")
readOnlyRules.tradeExceptionsButton:SetSize(190, 25)
readOnlyRules.tradeExceptionsButton:SetPoint("TOPLEFT", readOnlyRules.rules, "BOTTOMLEFT", 0, -12)
readOnlyRules.tradeExceptionsButton:SetText(L.RULES_TRADE_EXCEPTIONS_OPEN)
readOnlyRules.tradeExceptionsButton:SetScript("OnClick", function()
    RefreshTradeExceptionPopup()
    tradeExceptionPopup:Show()
    tradeExceptionPopup:Raise()
end)
readOnlyRules.tradeExceptionsButton:Hide()
readOnlyRules:Hide()
raceRuleUI.showReadOnly = false
raceRuleUI.viewToggle = CreateFrame("Button", nil, connectionContent, "BackdropTemplate")
raceRuleUI.viewToggle:SetSize(160, 27)
raceRuleUI.viewToggle:SetPoint("TOPRIGHT", connectionContent, "TOPRIGHT", -12, rulesEditorTopY + 2)
raceRuleUI.viewToggle:SetFrameLevel(connectionContent:GetFrameLevel() + 30)
raceRuleUI.viewToggle:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
raceRuleUI.viewToggle.activeGlow = raceRuleUI.viewToggle:CreateTexture(nil, "BACKGROUND")
raceRuleUI.viewToggle.activeGlow:SetPoint("TOPLEFT", 3, -3)
raceRuleUI.viewToggle.activeGlow:SetPoint("BOTTOMRIGHT", -3, 3)
raceRuleUI.viewToggle.activeGlow:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.18)
raceRuleUI.viewToggle.text = raceRuleUI.viewToggle:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
raceRuleUI.viewToggle.text:SetPoint("CENTER")
raceRuleUI.viewToggle.highlight = raceRuleUI.viewToggle:CreateTexture(nil, "HIGHLIGHT")
raceRuleUI.viewToggle.highlight:SetAllPoints()
raceRuleUI.viewToggle.highlight:SetColorTexture(1, 0.72, 0.22, 0.10)
raceRuleUI.viewToggle:SetScript("OnClick", function()
    raceRuleUI.showReadOnly = not raceRuleUI.showReadOnly
    if iRC.RefreshOptionsIfShown then iRC:RefreshOptionsIfShown() end
end)
raceRuleUI.viewToggle:Hide()

local function RefreshRulesView(canSwitchRulesView)
    local showReadOnlyRules = not canSwitchRulesView or raceRuleUI.showReadOnly
    raceRuleUI.readOnly:SetShown(showReadOnlyRules)
    raceRuleUI.viewToggle:SetShown(canSwitchRulesView)
    if showReadOnlyRules then
        raceRuleUI.readOnly.rules:SetText(BuildActiveRulesExplanation())
        raceRuleUI.readOnly.tradeExceptionsButton:SetShown(#GetActiveTradeExceptionGroups() > 0)
    else
        raceRuleUI.readOnly.tradeExceptionsButton:Hide()
        tradeExceptionPopup:Hide()
    end
    if canSwitchRulesView then
        raceRuleUI.viewToggle.text:SetText(iRC:Text(showReadOnlyRules and "RULES_VIEW_EDITOR" or "RULES_VIEW_ACTIVE"))
        raceRuleUI.viewToggle:SetBackdropColor(showReadOnlyRules and 0.18 or 0.055,
            showReadOnlyRules and 0.09 or 0.045, showReadOnlyRules and 0.025 or 0.035, 0.98)
        raceRuleUI.viewToggle:SetBackdropBorderColor(showReadOnlyRules and ORANGE[1] or 0.28,
            showReadOnlyRules and ORANGE[2] or 0.23, showReadOnlyRules and ORANGE[3] or 0.16,
            showReadOnlyRules and 1 or 0.9)
        raceRuleUI.viewToggle.activeGlow:SetAlpha(showReadOnlyRules and 1 or 0)
    end
end

(function()
local editor = homepageDescriptionUI
editor.tabs, editor.panels, editor.dropdowns, editor.contactRows = {}, {}, {}, {}
editor.activeTab = "presentation"
editor.draft = { description = "", icon = 0, tag = "NORMAL", contacts = {}, contactNotes = {},
    classBreakdown = { mode = "ALL", minLevel = 1, maxLevel = 60 } }

local function cleanText(value)
    return tostring(value or ""):gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s%s+", " ")
end
local function copyDraft(source)
    local result = { description = source.description, icon = source.icon, tag = source.tag,
        contacts = {}, contactNotes = {}, classBreakdown = {} }
    for _, name in ipairs(source.contacts) do result.contacts[#result.contacts + 1] = name end
    for key, note in pairs(source.contactNotes) do result.contactNotes[key] = note end
    for key, value in pairs(source.classBreakdown) do result.classBreakdown[key] = value end
    return result
end
local function snapshot(connection)
    local data = connection and connection.guildHomepageDescription or {}
    local icon = connection and connection.guildHomepageIcon or {}
    local classes = iRC:GetGuildHomepageClassBreakdown()
    local result = { description = data.text or "", icon = tonumber(icon.icon) or 0,
        tag = iRC:GetGuildHomepageTag(), contacts = {}, contactNotes = {},
        classBreakdown = { mode = classes.mode or "ALL", minLevel = classes.minLevel or 1, maxLevel = classes.maxLevel or 60 } }
    for name in tostring(connection and connection.rules and connection.rules.guildContacts or ""):gmatch("[^,]+") do
        local contactName = cleanText(name)
        if contactName ~= "" then
            result.contacts[#result.contacts + 1] = contactName
            result.contactNotes[iRC:NormalizeName(contactName)] = (iRC:GetGuildContactDetails(contactName) or {}).note or ""
        end
    end
    return result
end
local function fingerprint(draft)
    local values = { draft.description, draft.icon, draft.tag, draft.classBreakdown.mode,
        draft.classBreakdown.minLevel, draft.classBreakdown.maxLevel }
    for _, name in ipairs(draft.contacts) do
        values[#values + 1] = name
        values[#values + 1] = draft.contactNotes[iRC:NormalizeName(name)] or ""
    end
    return table.concat(values, "\031")
end

local function button(parent, label, width, height)
    local control = CreateFrame("Button", nil, parent, "BackdropTemplate")
    control:SetSize(width or 130, height or 28)
    control:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 9,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    control:SetBackdropColor(0.045, 0.038, 0.025, 0.98)
    control:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.65)
    control.text = control:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    control.text:SetPoint("CENTER")
    control.text:SetText(label)
    control.text:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
    control:SetFontString(control.text)
    control:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    control:HookScript("OnEnable", function(self) self:SetAlpha(1) end)
    control:HookScript("OnDisable", function(self) self:SetAlpha(0.42) end)
    return control
end
local function closeDropdowns()
    for _, dropdown in ipairs(editor.dropdowns) do dropdown.menu:Hide() end
end
local function dropdown(parent, label, width, getter, setter, options)
    local control = button(parent, "", width or 240, 30)
    control.text:ClearAllPoints()
    control.text:SetPoint("LEFT", 11, 0)
    control.text:SetPoint("RIGHT", -27, 0)
    control.text:SetJustifyH("LEFT")
    control.text:SetWordWrap(false)
    control.arrow = control:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    control.arrow:SetPoint("RIGHT", -10, 0)
    control.arrow:SetText("v")
    control.menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    control.menu:SetWidth(width or 240)
    control.menu:SetFrameStrata("FULLSCREEN_DIALOG")
    control.menu:SetClampedToScreen(true)
    control.menu:EnableMouse(true)
    control.menu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 9 })
    control.menu:SetBackdropColor(0.025, 0.022, 0.016, 1)
    control.menu:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.8)
    control.menu.buttons = {}
    control.menu:Hide()
    function control:Refresh()
        local value = getter()
        for _, option in ipairs(options()) do
            if option.value == value then self.text:SetText(option.label); return end
        end
        self.text:SetText(label)
    end
    control:SetScript("OnClick", function(self)
        if self.menu:IsShown() then self.menu:Hide(); return end
        closeDropdowns()
        local entries, current = options(), getter()
        for index, entry in ipairs(entries) do
            local option = entry
            local item = self.menu.buttons[index]
            if not item then
                item = button(self.menu, "", 1, 26)
                item.text:ClearAllPoints()
                item.text:SetPoint("LEFT", 10, 0)
                item.text:SetPoint("RIGHT", -10, 0)
                item.text:SetJustifyH("LEFT")
                item.text:SetWordWrap(false)
                self.menu.buttons[index] = item
            end
            item:ClearAllPoints()
            item:SetPoint("TOPLEFT", self.menu, "TOPLEFT", 5, -5 - (index - 1) * 28)
            item:SetPoint("TOPRIGHT", self.menu, "TOPRIGHT", -5, -5 - (index - 1) * 28)
            item:SetText(option.label)
            item.text:SetTextColor(option.value == current and 0.35 or 1, option.value == current and 1 or 0.82, 0.35)
            item:SetScript("OnClick", function()
                if editor.canEdit then setter(option.value) end
                self:Refresh()
                self.menu:Hide()
            end)
            item:Show()
        end
        for index = #entries + 1, #self.menu.buttons do self.menu.buttons[index]:Hide() end
        self.menu:SetHeight(#entries * 28 + 10)
        self.menu:ClearAllPoints()
        if (self:GetBottom() or 0) > self.menu:GetHeight() + 12 then
            self.menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
        else
            self.menu:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 2)
        end
        self.menu:Show()
        self.menu:Raise()
    end)
    control:HookScript("OnHide", function(self) self.menu:Hide() end)
    editor.dropdowns[#editor.dropdowns + 1] = control
    return control
end

editor.heading = guildHomepageContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
editor.heading:SetPoint("TOPLEFT", 16, -12)
editor.heading:SetText(L.GUILD_CONTACTS_HEADER)
editor.hint = guildHomepageContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
editor.hint:SetPoint("TOPLEFT", 16, -37)
editor.hint:SetPoint("TOPRIGHT", -16, -37)
editor.hint:SetJustifyH("LEFT")
editor.hint:SetText(L.GUILD_HOMEPAGE_DRAFT_HINT)
editor.save = button(guildHomepageContent, L.GUILD_HOMEPAGE_SAVE, 112)
editor.save:SetPoint("TOPRIGHT", -16, -61)
editor.discard = button(guildHomepageContent, L.GUILD_HOMEPAGE_DISCARD, 142)
editor.discard:SetPoint("RIGHT", editor.save, "LEFT", -8, 0)
editor.status = guildHomepageContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
editor.status:SetPoint("TOPLEFT", 16, -65)
editor.status:SetPoint("TOPRIGHT", editor.discard, "TOPLEFT", -12, -3)
editor.status:SetHeight(32)
editor.status:SetJustifyH("LEFT")
editor.status:SetWordWrap(true)
editor.preview = iRC.MainUI and iRC.MainUI:CreateGuildHomepagePreview(guildHomepageContent)
if editor.preview then
    editor.preview:SetPoint("TOPLEFT", guildHomepageContent, "TOPLEFT", 12, -106)
    editor.preview:SetPoint("TOPRIGHT", guildHomepageContent, "TOPRIGHT", -12, -106)
end

local definitions = {
    { key = "presentation", label = L.GUILD_HOMEPAGE_TAB_PRESENTATION },
    { key = "appearance", label = L.GUILD_HOMEPAGE_TAB_APPEARANCE },
    { key = "contacts", label = L.GUILD_HOMEPAGE_TAB_CONTACTS },
    { key = "statistics", label = L.GUILD_HOMEPAGE_TAB_STATISTICS },
}
for _, definition in ipairs(definitions) do
    local key = definition.key
    local panel = CreateFrame("Frame", nil, guildHomepageContent)
    panel:SetPoint("TOPLEFT", guildHomepageContent, "TOPLEFT", 0, 0)
    panel:SetPoint("TOPRIGHT", guildHomepageContent, "TOPRIGHT", 0, 0)
    panel:SetHeight(1)
    panel:Hide()
    editor.panels[key] = panel
    local tab = button(guildHomepageContent, definition.label, 120)
    tab:SetScript("OnClick", function()
        editor:ClearInputFocus()
        editor.activeTab = key
        editor:Layout()
    end)
    editor.tabs[key] = tab
end
function editor:Layout()
    local width = math.max(520, guildHomepageContent:GetWidth() or 550)
    local previewHeight = self.preview and self.preview:GetHeight() or 0
    local tabY = -118 - previewHeight
    local tabWidth = (width - 42) / 4
    for index, definition in ipairs(definitions) do
        local tab, panel = self.tabs[definition.key], self.panels[definition.key]
        local active = definition.key == self.activeTab
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", guildHomepageContent, "TOPLEFT", 12 + (index - 1) * (tabWidth + 6), tabY)
        tab:SetWidth(tabWidth)
        tab:SetBackdropColor(active and 0.17 or 0.045, active and 0.09 or 0.038, 0.025, 1)
        tab:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], active and 1 or 0.35)
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", guildHomepageContent, "TOPLEFT", 0, tabY - 42)
        panel:SetPoint("TOPRIGHT", guildHomepageContent, "TOPRIGHT", 0, tabY - 42)
        panel:SetShown(active)
    end
    if self.LayoutIcons then self:LayoutIcons(width) end
    guildHomepageContent:SetHeight(math.abs(tabY - 42) + self.panels[self.activeTab]:GetHeight() + 16)
end
if editor.preview then editor.preview.onHeightChanged = function() editor:Layout() end end
guildHomepageContent:HookScript("OnSizeChanged", function() editor:Layout() end)

function editor:IsDirty()
    return self.baseline and (fingerprint(self.draft) ~= fingerprint(self.baseline)
        or self.contactInput and cleanText(self.contactInput:GetText()) ~= "") or false
end
function editor:UpdateStatus()
    local dirty = self:IsDirty()
    local key = self.message or (not self.canEdit and "GUILD_HOMEPAGE_READ_ONLY")
        or (self.remoteChanged and dirty and "GUILD_HOMEPAGE_EXTERNAL_CHANGED")
        or (dirty and "GUILD_HOMEPAGE_UNSAVED" or "GUILD_HOMEPAGE_SAVED")
    self.status:SetText(iRC:Text(key))
    self.status:SetTextColor(self.message and 1 or (dirty and 1 or 0.6), self.message and 0.4 or (dirty and 0.78 or 0.6), 0.4)
    self.save:SetEnabled(self.canEdit == true and dirty and not self.saving)
    self.discard:SetEnabled(dirty and not self.saving)
end
function editor:UpdatePreview()
    if self.previewPending then return end
    self.previewPending = true
    local function update()
        self.previewPending = nil
        if self.preview and self.guildKey == iRC:GetGuildKey() then self.preview:Refresh(self.draft) end
        self:Layout()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.1, update) else update() end
end
function editor:Changed()
    if self.refreshing then return end
    self.message = nil
    self:UpdateStatus()
    self:UpdatePreview()
end
local function fail(key)
    editor.message = key
    editor:UpdateStatus()
    iRC:Print(iRC.Colors.Red .. iRC:Text(key) .. iRC.Colors.Reset)
    return false
end

local presentation = editor.panels.presentation
local descriptionCard, descriptionY = CreateManagementSettingsCard(presentation, L.GUILD_DESCRIPTION_HEADER, L.GUILD_DESCRIPTION_DESC, 0)
local presets = {
    { value = 0, label = L.GUILD_DESCRIPTION_PRESET_CUSTOM },
    { value = 1, label = L.GUILD_DESCRIPTION_PRESET_RACE, text = L.GUILD_DESCRIPTION_TEXT_RACE },
    { value = 2, label = L.GUILD_DESCRIPTION_PRESET_SF, text = L.GUILD_DESCRIPTION_TEXT_SF },
    { value = 3, label = L.GUILD_DESCRIPTION_PRESET_GF, text = L.GUILD_DESCRIPTION_TEXT_GF },
    { value = 4, label = L.GUILD_DESCRIPTION_PRESET_COMMUNITY, text = L.GUILD_DESCRIPTION_TEXT_COMMUNITY },
}
editor.selectedPreset = 0
editor.preset = dropdown(descriptionCard, L.GUILD_DESCRIPTION_PRESET_LABEL, 285,
    function() return editor.selectedPreset end,
    function(value)
        editor.selectedPreset = value
        if presets[value + 1].text then editor.description:SetText(presets[value + 1].text) end
    end, function() return presets end)
editor.preset:SetPoint("TOPLEFT", 18, descriptionY)
editor.description = CreateFrame("EditBox", nil, descriptionCard, "BackdropTemplate")
editor.description:SetPoint("TOPLEFT", 18, descriptionY - 44)
editor.description:SetPoint("TOPRIGHT", -18, descriptionY - 44)
editor.description:SetHeight(84)
editor.description:SetMultiLine(true)
editor.description:SetAutoFocus(false)
editor.description:SetFontObject(GameFontHighlight)
editor.description:SetTextInsets(8, 8, 7, 7)
editor.description:SetMaxLetters(iRC.GuildHomepageDescriptionMaxLength)
editor.description:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 9,
    insets = { left = 3, right = 3, top = 3, bottom = 3 } })
editor.description:SetBackdropColor(0.02, 0.018, 0.014, 1)
editor.description:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.5)
editor.description:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
editor.counter = descriptionCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
editor.counter:SetPoint("TOPRIGHT", editor.description, "BOTTOMRIGHT", 0, -5)
editor.description:SetScript("OnTextChanged", function(self)
    editor.counter:SetFormattedText("%d / %d", #self:GetText(), iRC.GuildHomepageDescriptionMaxLength)
    if editor.refreshing then return end
    editor.draft.description = self:GetText()
    editor.selectedPreset = 0
    editor.preset:Refresh()
    editor:Changed()
end)
local tagLabel = descriptionCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
tagLabel:SetPoint("TOPLEFT", 18, descriptionY - 158)
tagLabel:SetText(L.GUILD_HOMEPAGE_TAG_LABEL)
editor.tag = dropdown(descriptionCard, L.GUILD_HOMEPAGE_TAG_LABEL, 220,
    function() return editor.draft.tag end,
    function(value) editor.draft.tag = value; editor:Changed() end,
    function() return {
        { value = "NORMAL", label = L.GUILD_HOMEPAGE_TAG_NORMAL }, { value = "PVE", label = L.GUILD_HOMEPAGE_TAG_PVE },
        { value = "PVP", label = L.GUILD_HOMEPAGE_TAG_PVP }, { value = "RP", label = L.GUILD_HOMEPAGE_TAG_RP },
    } end)
editor.tag:SetPoint("TOPRIGHT", -18, descriptionY - 151)
local rulesHint = descriptionCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
rulesHint:SetPoint("TOPLEFT", 18, descriptionY - 194)
rulesHint:SetPoint("TOPRIGHT", -18, descriptionY - 194)
rulesHint:SetJustifyH("LEFT")
rulesHint:SetText(L.GUILD_HOMEPAGE_RULESET_LOCKED)
descriptionCard:SetHeight(math.abs(descriptionY) + 230)
presentation:SetHeight(descriptionCard:GetHeight())

local appearance = editor.panels.appearance
local iconCard, iconY = CreateManagementSettingsCard(appearance, L.GUILD_HOMEPAGE_ICON_HEADER, L.GUILD_HOMEPAGE_ICON_DESC, 0)
editor.iconButtons = {}
for index, texture in ipairs(iRC.GuildHomepageIcons) do
    local iconIndex = index
    local control = button(iconCard, "", 42, 42)
    control.icon = control:CreateTexture(nil, "ARTWORK")
    control.icon:SetSize(32, 32)
    control.icon:SetPoint("CENTER")
    control.icon:SetTexture(texture)
    control:SetScript("OnClick", function()
        if editor.canChooseIcon then editor.draft.icon = iconIndex; editor:PaintIcons(); editor:Changed() end
    end)
    SetSimpleTooltip(control, iRC:Text("GUILD_HOMEPAGE_ICON_NUMBER", index))
    editor.iconButtons[index] = control
end
editor.iconHint = iconCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
editor.iconHint:SetJustifyH("LEFT")
function editor:LayoutIcons(width)
    local columns = math.max(1, math.floor((width - 60) / 46))
    for index, control in ipairs(self.iconButtons) do
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", iconCard, "TOPLEFT", 18 + ((index - 1) % columns) * 46,
            iconY - math.floor((index - 1) / columns) * 46)
    end
    local rows = math.ceil(#self.iconButtons / columns)
    self.iconHint:ClearAllPoints()
    self.iconHint:SetPoint("TOPLEFT", iconCard, "TOPLEFT", 18, iconY - rows * 46 - 7)
    self.iconHint:SetPoint("TOPRIGHT", iconCard, "TOPRIGHT", -18, iconY - rows * 46 - 7)
    iconCard:SetHeight(math.abs(iconY) + rows * 46 + 48)
    appearance:SetHeight(iconCard:GetHeight())
end
function editor:PaintIcons()
    for index, control in ipairs(self.iconButtons) do
        control:SetEnabled(self.canChooseIcon == true)
        control:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], self.draft.icon == index and 1 or 0.3)
        control.icon:SetDesaturated(not self.canChooseIcon)
    end
    self.iconHint:SetText(self.canChooseIcon and L.GUILD_HOMEPAGE_DRAFT_HINT or L.GUILD_HOMEPAGE_ICON_LOCKED)
end

local statistics = editor.panels.statistics
local classCard, classY = CreateManagementSettingsCard(statistics, L.GUILD_HOMEPAGE_CLASSES_HEADER, L.GUILD_HOMEPAGE_STATISTICS_HELP, 0)
editor.classMode = dropdown(classCard, L.GUILD_HOMEPAGE_CLASSES_MODE, 260,
    function() return editor.draft.classBreakdown.mode end,
    function(value) editor.draft.classBreakdown.mode = value; editor:PaintClassRange(); editor:Changed() end,
    function() return {
        { value = "ALL", label = L.GUILD_HOMEPAGE_CLASSES_ALL },
        { value = "RANGE", label = L.GUILD_HOMEPAGE_CLASSES_RANGE },
        { value = "MAX", label = L.GUILD_HOMEPAGE_CLASSES_MAX },
    } end)
editor.classMode:SetPoint("TOPLEFT", 18, classY)
local function classSlider(label, left, field)
    local title = classCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", left, classY - 48)
    title:SetText(label)
    local valueLabel = classCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueLabel:SetPoint("LEFT", title, "RIGHT", 8, 0)
    valueLabel:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
    local slider = CreateFrame("Slider", nil, classCard, "BackdropTemplate")
    slider:SetSize(210, 18)
    slider:SetPoint("TOPLEFT", left, classY - 72)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(1, 60)
    slider:SetValueStep(1)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 9 })
    slider:SetBackdropColor(0.02, 0.018, 0.014, 1)
    slider:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.5)
    slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    slider:GetThumbTexture():SetSize(10, 22)
    slider:GetThumbTexture():SetVertexColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        valueLabel:SetText(tostring(value))
        if editor.refreshing then return end
        editor.draft.classBreakdown[field] = value
        if field == "minLevel" and value > editor.draft.classBreakdown.maxLevel then
            editor.draft.classBreakdown.maxLevel = value
        elseif field == "maxLevel" and value < editor.draft.classBreakdown.minLevel then
            editor.draft.classBreakdown.minLevel = value
        end
        editor:PaintClassRange()
        editor:Changed()
    end)
    return slider, title, valueLabel
end
editor.classMin, editor.classMinTitle, editor.classMinValue = classSlider(L.GUILD_HOMEPAGE_CLASSES_MIN, 18, "minLevel")
editor.classMax, editor.classMaxTitle, editor.classMaxValue = classSlider(L.GUILD_HOMEPAGE_CLASSES_MAXIMUM, 274, "maxLevel")
function editor:PaintClassRange()
    local wasRefreshing = self.refreshing
    self.refreshing = true
    self.classMin:SetValue(self.draft.classBreakdown.minLevel)
    self.classMax:SetValue(self.draft.classBreakdown.maxLevel)
    self.refreshing = wasRefreshing
    local enabled = self.canEdit and self.draft.classBreakdown.mode == "RANGE"
    self.classMin:SetEnabled(enabled == true)
    self.classMax:SetEnabled(enabled == true)
    self.classMin:SetAlpha(enabled and 1 or 0.42)
    self.classMax:SetAlpha(enabled and 1 or 0.42)
end
classCard:SetHeight(math.abs(classY) + 112)
statistics:SetHeight(classCard:GetHeight())

local contactsPanel = editor.panels.contacts
local contactsCard, contactsY = CreateManagementSettingsCard(contactsPanel, L.GUILD_CONTACTS_LABEL, L.GUILD_CONTACTS_DESC, 0)
editor.contactInput = CreateFrame("EditBox", nil, contactsCard, "InputBoxTemplate")
editor.contactInput:SetHeight(26)
editor.contactInput:SetPoint("TOPLEFT", 18, contactsY)
editor.contactInput:SetPoint("TOPRIGHT", -112, contactsY)
editor.contactInput:SetAutoFocus(false)
editor.contactInput:SetMaxLetters(80)
editor.addContact = button(contactsCard, L.GUILD_CONTACTS_ADD, 82)
editor.addContact:SetPoint("LEFT", editor.contactInput, "RIGHT", 10, 0)
editor.suggestions = CreateFrame("Frame", nil, contactsCard, "BackdropTemplate")
editor.suggestions:SetPoint("TOPLEFT", editor.contactInput, "BOTTOMLEFT", 0, -3)
editor.suggestions:SetPoint("TOPRIGHT", editor.contactInput, "BOTTOMRIGHT", 0, -3)
editor.suggestions:SetHeight(140)
editor.suggestions:SetFrameStrata("FULLSCREEN_DIALOG")
editor.suggestions:SetFrameLevel(contactsCard:GetFrameLevel() + 20)
editor.suggestions:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 9 })
editor.suggestions:SetBackdropColor(0.02, 0.018, 0.014, 1)
editor.suggestions:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.7)
editor.suggestions:Hide()
editor.suggestionButtons = {}
for index = 1, 5 do
    local control = button(editor.suggestions, "", 1, 25)
    control:SetPoint("TOPLEFT", 5, -5 - (index - 1) * 26)
    control:SetPoint("TOPRIGHT", -5, -5 - (index - 1) * 26)
    control.text:ClearAllPoints()
    control.text:SetPoint("LEFT", 8, 0)
    control.text:SetJustifyH("LEFT")
    control:SetScript("OnClick", function(self)
        editor.contactInput:SetText(iRC:FormatInviteContactName(self.contactName))
        editor.contactInput:SetCursorPosition(#editor.contactInput:GetText())
        editor.suggestions:Hide()
        editor.contactInput:SetFocus()
    end)
    editor.suggestionButtons[index] = control
end
local function hasContact(name, names)
    local key = iRC:NormalizeName(name)
    for _, contact in ipairs(names or editor.draft.contacts) do
        if iRC:NormalizeName(contact) == key then return true end
    end
    return false
end
local function contactSuggestions()
    local query = cleanText(editor.contactInput:GetText()):lower()
    local matches = {}
    if editor.canEdit and editor.contactInput:HasFocus() and query ~= "" then
        for _, member in ipairs(iRC:GetGuildRosterSnapshot()) do
            local name = member.name
            if name and not hasContact(name) then
                local label = iRC:FormatInviteContactName(name)
                if label:lower():find(query, 1, true) then matches[#matches + 1] = { name = name, label = label } end
            end
        end
        table.sort(matches, function(a, b)
            local aStarts, bStarts = a.label:lower():find(query, 1, true) == 1, b.label:lower():find(query, 1, true) == 1
            if aStarts ~= bStarts then return aStarts end
            return a.label < b.label
        end)
    end
    for index, control in ipairs(editor.suggestionButtons) do
        local match = matches[index]
        control:SetShown(match ~= nil)
        if match then control.contactName = match.name; control:SetText(match.label) end
    end
    editor.suggestions:SetHeight(math.min(5, #matches) * 26 + 10)
    editor.suggestions:SetShown(matches[1] ~= nil)
end
local function stageContact()
    if not editor.canEdit then return false end
    local input = cleanText(editor.contactInput:GetText())
    if input == "" then return true end
    local fullName = iRC:ResolveGuildMemberFullName(input)
    if not fullName then return fail("GUILD_HOMEPAGE_CONTACT_INVALID") end
    if hasContact(fullName) then editor.contactInput:SetText(""); return true end
    local names = {}
    for _, name in ipairs(editor.draft.contacts) do names[#names + 1] = name end
    names[#names + 1] = fullName
    if #names > 5 or #table.concat(names, ", ") > 140 then return fail("GUILD_CONTACTS_TOO_LONG") end
    editor.draft.contacts = names
    editor.draft.contactNotes[iRC:NormalizeName(fullName)] = ""
    editor.contactInput:SetText("")
    editor.contactInput:ClearFocus()
    editor.suggestions:Hide()
    editor:PaintContacts()
    editor:Changed()
    return true
end
editor.addContact:SetScript("OnClick", stageContact)
editor.contactInput:SetScript("OnEnterPressed", stageContact)
editor.contactInput:SetScript("OnTextChanged", function() contactSuggestions(); editor:Changed() end)
editor.contactInput:SetScript("OnEditFocusGained", contactSuggestions)
editor.contactInput:SetScript("OnEscapePressed", function(self) editor.suggestions:Hide(); self:ClearFocus() end)
editor.contactInput:SetScript("OnTabPressed", function(self)
    local first = editor.suggestionButtons[1]
    if editor.suggestions:IsShown() and first:IsShown() and first.contactName then
        self:SetText(iRC:FormatInviteContactName(first.contactName)); editor.suggestions:Hide()
    end
end)
editor.contactInput:SetScript("OnEditFocusLost", function()
    C_Timer.After(0, function()
        if not iRC:IsMouseOverFrame(editor.suggestions) then editor.suggestions:Hide() end
    end)
end)
editor.contactsEmpty = contactsCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
editor.contactsEmpty:SetPoint("TOPLEFT", 18, contactsY - 48)
editor.contactsEmpty:SetText(L.GUILD_CONTACTS_EMPTY)
function editor:PaintContacts()
    for index, name in ipairs(self.draft.contacts) do
        local row, contactName = self.contactRows[index], name
        if not row then
            row = CreateFrame("Frame", nil, contactsCard, "BackdropTemplate")
            row:SetHeight(72)
            row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8 })
            row:SetBackdropColor(0.02, 0.018, 0.014, 0.9)
            row:SetBackdropBorderColor(0.28, 0.23, 0.16, 0.8)
            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.name:SetPoint("TOPLEFT", 10, -10)
            row.note = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
            row.note:SetAutoFocus(false)
            row.note:SetMaxLetters(80)
            row.note:SetHeight(24)
            row.note:SetPoint("BOTTOMLEFT", 12, 9)
            row.note:SetPoint("BOTTOMRIGHT", -14, 9)
            row.remove = button(row, L.GUILD_CONTACTS_REMOVE, 74, 23)
            row.remove:SetPoint("TOPRIGHT", -9, -6)
            self.contactRows[index] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", contactsCard, "TOPLEFT", 18, contactsY - 46 - (index - 1) * 80)
        row:SetPoint("TOPRIGHT", contactsCard, "TOPRIGHT", -18, contactsY - 46 - (index - 1) * 80)
        row.name:SetText(iRC:FormatInviteContactName(contactName))
        row:EnableMouse(true)
        local metadata = iRC:GetGuildContactDetails(contactName)
        local contactDetail = L.GUILD_HOMEPAGE_UNSAVED
        if metadata and metadata.addedBy then
            contactDetail = iRC:Text("CONTACT_ADDED_BY", iRC:FormatPlayerName(metadata.addedBy))
            if metadata.addedAt then
                contactDetail = contactDetail .. "\n" .. iRC:Text("CONTACT_ADDED_AT", date("%Y-%m-%d %H:%M", metadata.addedAt))
            end
        end
        SetSimpleTooltip(row, iRC:FormatInviteContactName(contactName), contactDetail)
        row.note:SetEnabled(self.canEdit == true)
        if self.rebinding or not row.note:HasFocus() then
            local wasRefreshing = self.refreshing
            self.refreshing = true
            row.note:SetText(self.draft.contactNotes[iRC:NormalizeName(contactName)] or "")
            self.refreshing = wasRefreshing
        end
        SetSimpleTooltip(row.note, L.CONTACT_COLUMN_NOTE, L.GUILD_HOMEPAGE_CONTACT_NOTE_HELP)
        row.note:SetScript("OnTextChanged", function(control)
            if self.refreshing or not self.canEdit then return end
            self.draft.contactNotes[iRC:NormalizeName(contactName)] = control:GetText()
            self:Changed()
        end)
        row.note:SetScript("OnEnterPressed", function(control) control:ClearFocus() end)
        row.note:SetScript("OnEscapePressed", function(control) control:ClearFocus() end)
        row.remove:SetEnabled(self.canEdit == true)
        row.remove:SetScript("OnClick", function()
            if not self.canEdit then return end
            local kept = {}
            for _, value in ipairs(self.draft.contacts) do
                if iRC:NormalizeName(value) ~= iRC:NormalizeName(contactName) then kept[#kept + 1] = value end
            end
            self.draft.contacts = kept
            self:PaintContacts()
            self:Changed()
        end)
        row:Show()
    end
    for index = #self.draft.contacts + 1, #self.contactRows do self.contactRows[index]:Hide() end
    self.contactsEmpty:SetShown(#self.draft.contacts == 0)
    contactsCard:SetHeight(math.abs(contactsY) + 62 + math.max(1, #self.draft.contacts) * 80)
    contactsPanel:SetHeight(contactsCard:GetHeight())
    self:Layout()
end

function editor:Paint()
    self.refreshing = true
    if self.rebinding or not self.description:HasFocus() then self.description:SetText(self.draft.description) end
    self.description:SetEnabled(self.canEdit == true)
    self.preset:SetEnabled(self.canEdit == true)
    self.tag:SetEnabled(self.canEdit == true)
    self.classMode:SetEnabled(self.canEdit == true)
    self.contactInput:SetEnabled(self.canEdit == true)
    self.addContact:SetEnabled(self.canEdit == true and #self.draft.contacts < 5)
    self.preset:Refresh()
    self.tag:Refresh()
    self.classMode:Refresh()
    self:PaintClassRange()
    self:PaintIcons()
    self:PaintContacts()
    self.refreshing = nil
    self:UpdateStatus()
    self:UpdatePreview()
end
function editor:ClearInputFocus()
    self.description:ClearFocus()
    self.contactInput:ClearFocus()
    for _, row in ipairs(self.contactRows) do row.note:ClearFocus() end
    self.suggestions:Hide()
    closeDropdowns()
end
function editor:Refresh(connection, canEdit)
    local current, guildKey = snapshot(connection), iRC:GetGuildKey()
    local changedGuild = self.guildKey ~= guildKey
    if changedGuild or not self.baseline or (not self.saving and not self:IsDirty()) then
        if changedGuild then self:ClearInputFocus() end
        self.baseline, self.draft = current, copyDraft(current)
        self.rebinding = true
        self.refreshing = true
        self.contactInput:SetText("")
        self.refreshing = nil
        self.remoteChanged, self.message = nil, nil
    elseif not self.saving then
        self.remoteChanged = fingerprint(current) ~= fingerprint(self.baseline)
    end
    self.guildKey = guildKey
    self.canEdit = canEdit == true and not iRC:IsLowTrafficMode()
    if not self.canEdit then self:ClearInputFocus() end
    local rules = iRC:GetConnectionRules()
    self.canChooseIcon = self.canEdit and rules.raceLock ~= true and rules.classLock ~= true
    if rules.raceLock == true or rules.classLock == true then self.draft.icon = current.icon end
    self:Paint()
    self.rebinding = nil
end
function editor:Discard()
    self.baseline = nil
    self:ClearInputFocus()
    self:Refresh(iRC:GetConnection(), iRC:IsGuildConnectionActive() and iRC:HasGuildPermission("homepage"))
end
editor.discard:SetScript("OnClick", function() editor:Discard() end)
function editor:Save()
    if self.saving or self.guildKey ~= iRC:GetGuildKey() or not iRC:IsGuildConnectionActive()
        or not iRC:HasGuildPermission("homepage") or iRC:IsLowTrafficMode() then return false end
    if not stageContact() then return false end
    local draft, base, current = copyDraft(self.draft), self.baseline, snapshot(iRC:GetConnection())
    draft.description = cleanText(draft.description):sub(1, iRC.GuildHomepageDescriptionMaxLength)
    if draft.description ~= base.description and iRC:ContainsProfanity(draft.description) then return fail("GUILD_DESCRIPTION_PROFANITY") end
    if draft.tag ~= "NORMAL" and draft.tag ~= "PVE" and draft.tag ~= "PVP" and draft.tag ~= "RP" then return false end
    local classes = draft.classBreakdown
    if classes.mode ~= "ALL" and classes.mode ~= "RANGE" and classes.mode ~= "MAX" then return false end
    classes.minLevel = math.max(1, math.min(60, math.floor(tonumber(classes.minLevel) or 1)))
    classes.maxLevel = math.max(classes.minLevel, math.min(60, math.floor(tonumber(classes.maxLevel) or 60)))
    if classes.mode == "ALL" then classes.minLevel, classes.maxLevel = 1, 60
    elseif classes.mode == "MAX" then classes.minLevel, classes.maxLevel = 60, 60 end
    local names, seen = {}, {}
    for _, name in ipairs(draft.contacts) do
        local fullName = iRC:ResolveGuildMemberFullName(name)
        if not fullName then return fail("GUILD_HOMEPAGE_CONTACT_INVALID") end
        local key = iRC:NormalizeName(fullName)
        if not seen[key] then names[#names + 1] = fullName; seen[key] = true end
    end
    if #names > 5 or #table.concat(names, ", ") > 140 then return fail("GUILD_CONTACTS_TOO_LONG") end
    local contactsChanged = table.concat(draft.contacts, ", ") ~= table.concat(base.contacts, ", ")
    local publishedContacts = contactsChanged and names or current.contacts
    for _, name in ipairs(names) do
        local key = iRC:NormalizeName(name)
        if (draft.contactNotes[key] or "") ~= (base.contactNotes[key] or "") and not hasContact(name, publishedContacts) then
            return fail("GUILD_HOMEPAGE_CONTACT_INVALID")
        end
    end
    if self.canChooseIcon and draft.icon ~= base.icon
        and (draft.icon < 1 or draft.icon > #iRC.GuildHomepageIcons or draft.icon ~= math.floor(draft.icon)) then return false end
    self.saving = true
    self:UpdateStatus()
    local success = true
    local function apply(changed, setter, ...)
        if success and changed and setter(iRC, ...) ~= true then success = false end
    end
    -- An earlier attempt may have saved some fields before a later setter
    -- failed. Skip values already present in current state when retrying.
    apply(draft.description ~= base.description and draft.description ~= current.description,
        iRC.SetGuildHomepageDescription, draft.description)
    apply(self.canChooseIcon and draft.icon ~= base.icon and draft.icon ~= current.icon,
        iRC.SetGuildHomepageIcon, draft.icon)
    apply(draft.tag ~= base.tag and draft.tag ~= current.tag, iRC.SetGuildHomepageTag, draft.tag)
    local classesChanged = classes.mode ~= base.classBreakdown.mode or classes.minLevel ~= base.classBreakdown.minLevel
        or classes.maxLevel ~= base.classBreakdown.maxLevel
    local classesCurrent = classes.mode == current.classBreakdown.mode and classes.minLevel == current.classBreakdown.minLevel
        and classes.maxLevel == current.classBreakdown.maxLevel
    apply(classesChanged and not classesCurrent,
        iRC.SetGuildHomepageClassBreakdown, classes.mode, classes.minLevel, classes.maxLevel)
    apply(contactsChanged and table.concat(names, ", ") ~= table.concat(current.contacts, ", "),
        iRC.SetGuildContacts, table.concat(names, ", "))
    for _, name in ipairs(names) do
        local key = iRC:NormalizeName(name)
        local note = cleanText(draft.contactNotes[key]):sub(1, 80)
        apply(note ~= (base.contactNotes[key] or "") and note ~= (current.contactNotes[key] or ""),
            iRC.SetGuildContactNote, name, note)
    end
    self.saving = nil
    if not success then self:Paint(); return fail("GUILD_HOMEPAGE_SAVE_FAILED") end
    self.baseline = nil
    self:ClearInputFocus()
    self:Refresh(iRC:GetConnection(), true)
    if iRC.RefreshOptionsIfShown then iRC:RefreshOptionsIfShown() end
    iRC:Print(iRC:Text("GUILD_HOMEPAGE_SAVED_MESSAGE"))
    return true
end
editor.save:SetScript("OnClick", function() editor:Save() end)
guildHomepageContainer:HookScript("OnHide", function()
    editor:ClearInputFocus()
end)
local outsideClick = CreateFrame("Frame")
outsideClick:RegisterEvent("GLOBAL_MOUSE_DOWN")
outsideClick:SetScript("OnEvent", function()
    for _, control in ipairs(editor.dropdowns) do
        if control.menu:IsShown() and not iRC:IsMouseOverFrame(control) and not iRC:IsMouseOverFrame(control.menu) then control.menu:Hide() end
    end
end)
editor:Layout()
end)()

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
_, y = CreateSectionHeader(roleplayContent, L.TAUREN_TALK_TITLE, y - 4)
local taurenTalkCheck
taurenTalkCheck, y = CreateSettingsCheckbox(roleplayContent, L.TAUREN_TALK_ENABLE, L.TAUREN_TALK_DESC, y,
    function() return iRC.Roleplay:GetPlayerSettings().taurenTalk end,
    function(value) iRC.Roleplay:GetPlayerSettings().taurenTalk = value and true or false end)
_, y = CreateInfoText(roleplayContent, L.TAUREN_TALK_EXAMPLE, y - 2, "GameFontDisableSmall")
_, y = CreateSectionHeader(roleplayContent, L.NIGHT_ELF_TALK_TITLE, y - 4)
local nightElfTalkCheck
nightElfTalkCheck, y = CreateSettingsCheckbox(roleplayContent, L.NIGHT_ELF_TALK_ENABLE, L.NIGHT_ELF_TALK_DESC, y,
    function() return iRC.Roleplay:GetPlayerSettings().nightElfTalk end,
    function(value) iRC.Roleplay:GetPlayerSettings().nightElfTalk = value and true or false end)
_, y = CreateInfoText(roleplayContent, L.NIGHT_ELF_TALK_EXAMPLE, y - 2, "GameFontDisableSmall")
_, y = CreateSectionHeader(roleplayContent, L.UNDEAD_SPEAK_TITLE, y - 4)
local undeadSpeakCheck
undeadSpeakCheck, y = CreateSettingsCheckbox(roleplayContent, L.UNDEAD_SPEAK_ENABLE, L.UNDEAD_SPEAK_DESC, y,
    function() return iRC.Roleplay:GetPlayerSettings().undeadSpeak end,
    function(value) iRC.Roleplay:GetPlayerSettings().undeadSpeak = value and true or false end)
_, y = CreateInfoText(roleplayContent, L.UNDEAD_SPEAK_EXAMPLE, y - 2, "GameFontDisableSmall")
roleplayContent:SetHeight(math.abs(y) + 20)

do
    local y = -10
    _, y = CreateSectionHeader(aboutContent, L.ABOUT_HEADER, y)
    y = y - 20

    local aboutIcon = aboutContent:CreateTexture(nil, "ARTWORK")
    aboutIcon:SetSize(64, 64)
    aboutIcon:SetPoint("TOP", aboutContent, "TOP", 0, y)
    aboutIcon:SetTexture(iRC.IconPath)
    y = y - 70

    local aboutTitle = aboutContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    aboutTitle:SetPoint("TOP", aboutContent, "TOP", 0, y)
    aboutTitle:SetText(iRC.Colors.iRC .. (iRC.Title or iRC.DisplayName) .. iRC.Colors.Reset .. " " .. iRC.Colors.Green .. "v" .. iRC:GetDisplayVersion() .. iRC.Colors.Reset)
    y = y - 20

    local aboutAuthor = aboutContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    aboutAuthor:SetPoint("TOP", aboutContent, "TOP", 0, y)
    aboutAuthor:SetText(L.ABOUT_CREATED_BY .. "|cFF00FFFF" .. tostring(iRC.Author or "Crasling") .. iRC.Colors.Reset)
    y = y - 16

    local aboutGameVersion = aboutContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    aboutGameVersion:SetPoint("TOP", aboutContent, "TOP", 0, y)
    aboutGameVersion:SetText(iRC.GameVersionName or "")
    y = y - 20

    local aboutDescription = aboutContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    aboutDescription:SetPoint("TOPLEFT", aboutContent, "TOPLEFT", 25, y)
    aboutDescription:SetWidth(470)
    aboutDescription:SetJustifyH("LEFT")
    aboutDescription:SetWordWrap(true)
    aboutDescription:SetText(L.ABOUT_DESCRIPTION)
    local descriptionHeight = math.max(14, aboutDescription:GetStringHeight())
    y = y - descriptionHeight - 8

    _, y = CreateSectionHeader(aboutContent, L.DISCORD_HEADER, y)
    y = y - 2

    local discordDescription = aboutContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    discordDescription:SetPoint("TOPLEFT", aboutContent, "TOPLEFT", 25, y)
    discordDescription:SetText(L.DISCORD_LINK_MESSAGE)
    y = y - 16

    local discordBox = CreateFrame("EditBox", nil, aboutContent, "InputBoxTemplate")
    discordBox:SetSize(280, 22)
    discordBox:SetPoint("TOPLEFT", aboutContent, "TOPLEFT", 25, y)
    discordBox:SetAutoFocus(false)
    discordBox:SetText(L.DISCORD_LINK)
    discordBox:SetFontObject(GameFontHighlight)
    discordBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    discordBox:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
        self:SetText(L.DISCORD_LINK)
    end)
    discordBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    y = y - 30

    _, y = CreateSectionHeader(aboutContent, "Links", y)
    _, y = CreateInfoText(aboutContent, "GitHub: github.com/Crasling/iRCGuildConnect", y, "GameFontDisableSmall")

    -- Translation credits are prepared here but intentionally hidden until
    -- iRC ships with additional maintained locales.
    local showTranslations = false
    if showTranslations then
        _, y = CreateSectionHeader(aboutContent, L.TRANSLATIONS_HEADER, y - 6)
        _, y = CreateInfoText(aboutContent, L.TRANSLATIONS_EMPTY, y, "GameFontDisableSmall")
    end

    _, y = CreateSectionHeader(aboutContent, L.DEVELOPER_HEADER, y - 6)
    debugModeCheck, y = CreateSettingsCheckbox(aboutContent, L.ENABLE_DEBUG_MODE, L.ENABLE_DEBUG_MODE_DESC, y,
        function() return iRC:GetSettings().debugMode end,
        function(value) iRC:GetSettings().debugMode = value and true or false end)
    aboutContent:SetHeight(math.abs(y) + 20)
end

local companionAddons = {
    { content = iWRContent, name = "iWillRemember", addonName = "iWillRemember", description = "A player notes addon for tracking and sharing memorable encounters with friends and guild members.", link = "curseforge.com/wow/addons/iwillremember", button = "Open iWR Settings", getFrame = function() return _G.iWR and _G.iWR.SettingsFrame end },
    { content = iNIFContent, name = "iNeedIfYouNeed", addonName = "iNeedIfYouNeed", description = "A smart loot companion that helps groups handle Need and Greed decisions for eligible items.", link = "curseforge.com/wow/addons/ineedifyouneed", button = "Open iNIF Settings", getFrame = function() return _G.iNIFSettingsFrame end },
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

local guildFoundAuditText
local guildFoundStatus = {}
local guildFoundTradeExceptionChecks = {}
local guildFoundTradeItemControls = {}
local refreshGuildFoundTradeItemList
do
    (function()
    local y = -12
    _, y = CreateSectionHeader(guildFoundContent, L.GUILDFOUND_TOOLS_TITLE, y)
    _, y = CreateInfoText(guildFoundContent, L.GUILDFOUND_TOOLS_DESC, y, "GameFontDisableSmall")
    managementConnectionCards.guildFound, y = CreateConnectionStatusCard(guildFoundContent, y)
    local statusPanel = CreateFrame("Frame", nil, guildFoundContent, "BackdropTemplate")
    statusPanel:SetPoint("TOPLEFT", guildFoundContent, "TOPLEFT", 12, y - 3)
    statusPanel:SetPoint("TOPRIGHT", guildFoundContent, "TOPRIGHT", -12, y - 3)
    statusPanel:SetHeight(54)
    statusPanel:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    statusPanel:SetBackdropColor(0.035, 0.03, 0.025, 0.88)
    statusPanel:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.50)
    guildFoundStatus.protection = statusPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    guildFoundStatus.protection:SetJustifyH("CENTER")
    guildFoundStatus.exceptions = statusPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    guildFoundStatus.exceptions:SetJustifyH("CENTER")
    guildFoundStatus.access = statusPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    guildFoundStatus.access:SetJustifyH("CENTER")
    local statusDividers = {}
    for index = 1, 2 do
        local divider = statusPanel:CreateTexture(nil, "ARTWORK")
        divider:SetWidth(1)
        divider:SetPoint("TOP", statusPanel, "TOP", 0, -9)
        divider:SetPoint("BOTTOM", statusPanel, "BOTTOM", 0, 9)
        divider:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.18)
        statusDividers[index] = divider
    end
    local function layoutStatusPanel(_, width)
        local columnWidth = width / 3
        for index, text in ipairs({ guildFoundStatus.protection, guildFoundStatus.exceptions, guildFoundStatus.access }) do
            text:ClearAllPoints()
            text:SetPoint("CENTER", statusPanel, "LEFT", columnWidth * (index - 0.5), 0)
            text:SetWidth(math.max(1, columnWidth - 24))
        end
        for index, divider in ipairs(statusDividers) do
            divider:ClearAllPoints()
            divider:SetPoint("TOPLEFT", statusPanel, "TOPLEFT", columnWidth * index, -9)
            divider:SetPoint("BOTTOMLEFT", statusPanel, "BOTTOMLEFT", columnWidth * index, 9)
        end
    end
    statusPanel:SetScript("OnSizeChanged", layoutStatusPanel)
    layoutStatusPanel(statusPanel, statusPanel:GetWidth())
    statusPanel:EnableMouse(true)
    SetSimpleTooltip(statusPanel, L.GUILDFOUND_SETTINGS_HEADER, L.GUILDFOUND_ENFORCEMENT_LOCKED)
    y = y - 62
    local exceptionTop = y - 4
    local exceptionCard, exceptionY = CreateManagementSettingsCard(guildFoundContent,
        L.GUILD_FOUND_TRADE_EXCEPTIONS_HEADER, L.GUILD_FOUND_TRADE_EXCEPTIONS_DESC, exceptionTop)
    local itemListFrame = CreateFrame("Frame", nil, exceptionCard, "BackdropTemplate")
    itemListFrame:SetPoint("TOPLEFT", exceptionCard, "TOPLEFT", 12, exceptionY - 2)
    itemListFrame:SetPoint("TOPRIGHT", exceptionCard, "TOPRIGHT", -12, exceptionY - 2)
    itemListFrame:SetHeight(285)
    itemListFrame:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    itemListFrame:SetBackdropColor(0.045, 0.038, 0.028, 0.92)
    itemListFrame:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.78)
    local itemScroll = CreateFrame("ScrollFrame", nil, itemListFrame, "UIPanelScrollFrameTemplate")
    iRC:StyleScrollFrame(itemScroll)
    itemScroll:SetPoint("TOPLEFT", 8, -8)
    itemScroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local itemContent = CreateFrame("Frame", nil, itemScroll)
    itemContent:SetWidth(1)
    itemContent:SetHeight(1)
    itemScroll:SetScrollChild(itemContent)
    itemListFrame:SetScript("OnSizeChanged", function(_, width)
        itemContent:SetWidth(math.max(1, width - 40))
    end)
    local expandedCategories = {}
    local categories = {
        { key = "conjured", setting = "conjured", label = L.GUILD_FOUND_EXCEPTION_CONJURED,
            description = L.GUILD_FOUND_EXCEPTION_CONJURED_DESC },
        { key = "healthstones", setting = "healthstones", label = L.GUILD_FOUND_EXCEPTION_HEALTHSTONES,
            description = L.GUILD_FOUND_EXCEPTION_HEALTHSTONES_DESC },
        { key = "questItems", setting = "questItems", label = L.GUILD_FOUND_EXCEPTION_QUEST_ITEMS,
            description = L.GUILD_FOUND_EXCEPTION_QUEST_ITEMS_DESC },
        { key = "lockpickOutgoing", setting = "lockpickOutgoing", label = L.GUILD_FOUND_EXCEPTION_LOCKPICK_OUT,
            description = L.GUILD_FOUND_EXCEPTION_LOCKPICK_OUT_DESC },
        { key = "lockpickIncoming", setting = "lockpickIncoming", label = L.GUILD_FOUND_EXCEPTION_LOCKPICK_IN,
            description = L.GUILD_FOUND_EXCEPTION_LOCKPICK_IN_DESC },
    }
    for _, category in ipairs(categories) do
        local categoryKey, itemCategoryKey, categorySetting = category.setting, category.key, category.setting
        local header = CreateFrame("Button", nil, itemContent, "BackdropTemplate")
        header:SetHeight(34)
        header:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        header:SetBackdropColor(0.10, 0.075, 0.04, 0.72)
        header:SetBackdropBorderColor(0.34, 0.28, 0.20, 0.92)
        header.accent = header:CreateTexture(nil, "ARTWORK")
        header.accent:SetWidth(3)
        header.accent:SetPoint("TOPLEFT", header, "TOPLEFT", 4, -5)
        header.accent:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 4, 5)
        header.accent:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.85)
        header.check = CreateFrame("CheckButton", nil, header, CHECKBOX_TEMPLATE)
        header.check:SetSize(22, 22)
        header.syncBadge = CreateSyncBadge(header, -3)
        header.syncBadge:ClearAllPoints()
        header.syncBadge:SetPoint("LEFT", header, "LEFT", 4, 0)
        header.check:SetPoint("LEFT", header, "LEFT", 43, 0)
        header.check:SetScript("OnClick", function(self)
            if not iRC:SetGuildFoundTradeException(categorySetting, self:GetChecked() == true) then
                -- The click can be rejected if permissions or the parent rule
                -- changed while this panel was open. Restore saved state.
                self:SetChecked(iRC:GetGuildFoundTradeExceptionSettings()[categorySetting] == true)
            end
            refreshGuildFoundTradeItemList()
        end)
        header.check.Refresh = function()
            header.check:SetChecked(iRC:GetGuildFoundTradeExceptionSettings()[categorySetting] == true)
        end
        SetSimpleTooltip(header.check, category.label, category.description)
        guildFoundTradeExceptionChecks[category.setting] = header.check
        header.text = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        header.text:SetPoint("LEFT", 73, 0)
        header.text:SetPoint("RIGHT", header, "RIGHT", -150, 0)
        header.text:SetJustifyH("LEFT")
        header.count = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        header.count:SetPoint("RIGHT", header, "RIGHT", -9, 0)
        header.count:SetWidth(105)
        header.count:SetJustifyH("RIGHT")
        header.highlight = header:CreateTexture(nil, "HIGHLIGHT")
        header.highlight:SetAllPoints()
        header.highlight:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.12)
        header:SetScript("OnClick", function()
            expandedCategories[categoryKey] = not expandedCategories[categoryKey]
            refreshGuildFoundTradeItemList()
        end)
        SetSimpleTooltip(header, category.label, category.description)
        category.header = header
        category.items = {}
        for _, itemId in ipairs(iRC.GuildFoundTradeExceptionItems[category.key] or {}) do
            local selectedItemId = itemId
            local checkbox = CreateFrame("CheckButton", nil, itemContent, CHECKBOX_TEMPLATE)
            checkbox:SetSize(22, 22)
            checkbox.Text = checkbox.Text or checkbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            checkbox.Text:ClearAllPoints()
            checkbox.Text:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
            checkbox.Text:SetWidth(355)
            checkbox.Text:SetJustifyH("LEFT")
            checkbox.rowBackground = checkbox:CreateTexture(nil, "BACKGROUND")
            checkbox.rowBackground:SetPoint("TOPLEFT", checkbox, "TOPLEFT", -5, 0)
            checkbox.rowBackground:SetSize(395, 22)
            checkbox.rowBackground:SetColorTexture(0.08, 0.07, 0.055, 0.48)
            checkbox:SetScript("OnClick", function(self)
                if not iRC:SetGuildFoundTradeExceptionItem(itemCategoryKey, selectedItemId, self:GetChecked() == true) then
                    local settings = iRC:GetGuildFoundTradeExceptionSettings()
                    local selected = settings.items and settings.items[itemCategoryKey]
                        and settings.items[itemCategoryKey][selectedItemId] == true
                    self:SetChecked(selected)
                end
                refreshGuildFoundTradeItemList()
            end)
            checkbox:SetScript("OnEnter", function(self)
                if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(selectedItemId); GameTooltip:Show() end
            end)
            checkbox:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            category.items[#category.items + 1] = { id = itemId, checkbox = checkbox }
            guildFoundTradeItemControls[#guildFoundTradeItemControls + 1] = checkbox
        end
    end
    refreshGuildFoundTradeItemList = function()
        local settings = iRC:GetGuildFoundTradeExceptionSettings()
        local canEdit = iRC:IsGuildConnectionActive() and iRC:HasGuildPermission("tradeExceptions")
            and iRC:GetConnectionRules().guildFoundTradeExceptions == true
        local offset = 0
        for _, category in ipairs(categories) do
            local categoryEnabled = settings[category.setting] == true
                or (category.secondarySetting and settings[category.secondarySetting] == true)
            category.header.check:SetChecked(categoryEnabled)
            category.header.check:SetEnabled(canEdit and true or false)
            category.header.check:SetAlpha(canEdit and 1 or 0.45)
            local selectedCount = 0
            for _, item in ipairs(category.items) do
                if settings.items and settings.items[category.key] and settings.items[category.key][item.id] then
                    selectedCount = selectedCount + 1
                end
            end
            category.header:ClearAllPoints()
            category.header:SetPoint("TOPLEFT", itemContent, "TOPLEFT", 2, -offset)
            category.header:SetPoint("TOPRIGHT", itemContent, "TOPRIGHT", -2, -offset)
            category.header.text:SetText((expandedCategories[category.setting] and "-  " or "+  ") .. category.label)
            category.header.text:SetTextColor(categoryEnabled and 1 or 0.65, categoryEnabled and 0.82 or 0.65, categoryEnabled and 0 or 0.65)
            category.header.count:SetText(iRC:Text("GUILD_FOUND_EXCEPTION_ITEMS_SELECTED", selectedCount))
            category.header.count:SetTextColor(selectedCount > 0 and 0.72 or 0.48, selectedCount > 0 and 0.82 or 0.48,
                selectedCount > 0 and 0.62 or 0.48)
            category.header:SetBackdropColor(categoryEnabled and 0.13 or 0.075, categoryEnabled and 0.09 or 0.065,
                categoryEnabled and 0.035 or 0.055, expandedCategories[category.setting] and 0.96 or 0.68)
            offset = offset + 36
            for _, item in ipairs(category.items) do
                local checkbox = item.checkbox
                checkbox:SetShown(expandedCategories[category.setting] == true)
                if expandedCategories[category.setting] then
                    checkbox:ClearAllPoints()
                    checkbox:SetPoint("TOPLEFT", itemContent, "TOPLEFT", 20, -offset)
                    local selected = settings.items and settings.items[category.key] and settings.items[category.key][item.id]
                    checkbox:SetChecked(selected == true)
                    checkbox:SetEnabled(canEdit and categoryEnabled and true or false)
                    checkbox.rowBackground:ClearAllPoints()
                    checkbox.rowBackground:SetPoint("TOPLEFT", checkbox, "TOPLEFT", -5, 0)
                    checkbox.rowBackground:SetPoint("RIGHT", itemContent, "RIGHT", -5, 0)
                    checkbox.rowBackground:SetColorTexture(selected and 0.08 or 0.055, selected and 0.18 or 0.05,
                        selected and 0.09 or 0.04, selected and 0.68 or 0.42)
                    local cachedItemName = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(item.id)
                    local itemName = cachedItemName or iRC.GuildFoundTradeExceptionItemNames[item.id] or "Unknown item"
                    checkbox.Text:SetText(itemName .. " (" .. item.id .. ")")
                    offset = offset + 23
                end
            end
        end
        itemContent:SetHeight(math.max(1, offset))
    end
    refreshGuildFoundTradeItemList()
    local exceptionCardHeight = math.abs(exceptionY) + 297
    exceptionCard:SetHeight(exceptionCardHeight)
    y = exceptionTop - exceptionCardHeight - 12

    local auditCard, auditY = CreateManagementSettingsCard(guildFoundContent,
        L.GUILDFOUND_AUDIT_HEADER, L.GUILDFOUND_AUDIT_DESC, y)
    guildFoundAuditText, auditY = CreateInfoText(auditCard, L.GUILDFOUND_AUDIT_EMPTY, auditY, "GameFontHighlightSmall")
    guildFoundAuditText:ClearAllPoints()
    guildFoundAuditText:SetPoint("TOPLEFT", auditCard, "TOPLEFT", 18, auditY + 16)
    guildFoundAuditText:SetPoint("RIGHT", auditCard, "RIGHT", -18, 0)
    local auditCardHeight = math.max(math.abs(auditY) + 24, 105)
    auditCard:SetHeight(auditCardHeight)
    guildFoundAuditText.managementCard = auditCard
    guildFoundAuditText.cardTop = y
    y = y - auditCardHeight - 12
    guildFoundContent:SetHeight(math.max(math.abs(y) + 20, 450))
    end)()

end

local newMemberWelcomeCheck, showAttentionRemindersCheck, automaticWarningChecks, welcomeConflictText, welcomeConflictAccept, welcomeConflictKeep
local notificationCard, permissionCard, notificationBaseHeight, notificationConflictHeight, permissionCardHeight, notificationCardTop
local rankPermissionDropdowns = {}
local namedPermissionChecks, selectedPermissionMember = {}, nil
local refreshMemberPermissionControls
do
    local y = -12
    _, y = CreateSectionHeader(guildNotificationsContent, L.GUILD_NOTIFICATIONS_TITLE, y)
    managementConnectionCards.notifications, y = CreateConnectionStatusCard(guildNotificationsContent, y)

    notificationCardTop = y - 2
    local notificationY
    notificationCard, notificationY = CreateManagementSettingsCard(guildNotificationsContent,
        L.GUILD_NOTIFICATIONS_CATEGORY, L.GUILD_NOTIFICATIONS_DESC, notificationCardTop)
    newMemberWelcomeCheck, notificationY = CreateCompactManagementToggle(notificationCard,
        L.NEW_MEMBER_WELCOME_OPTION, L.NEW_MEMBER_WELCOME_OPTION_DESC, notificationY - 4,
        function() return iRC:IsNewMemberWelcomeEnabled() end,
        function(value) iRC:SetNewMemberWelcomeEnabled(value) end, true)
    automaticWarningChecks = {}
    for _, entry in ipairs({
        { "OFFICER", L.ENABLE_OFFICER_WARNINGS, L.ENABLE_OFFICER_WARNINGS_DESC },
        { "WHISPER", L.ENABLE_WHISPER_WARNINGS, L.ENABLE_WHISPER_WARNINGS_DESC },
        { "GUILD", L.ENABLE_GUILD_WARNINGS, L.ENABLE_GUILD_WARNINGS_DESC },
    }) do
        local channel = entry[1]
        automaticWarningChecks[channel], notificationY = CreateCompactManagementToggle(notificationCard, entry[2], entry[3], notificationY,
            function() return iRC:IsAutomaticWarningEnabled(channel) end,
            function(value) iRC:SetAutomaticWarningEnabled(channel, value) end, true)
    end
    showAttentionRemindersCheck, notificationY = CreateCompactManagementToggle(notificationCard,
        L.SHOW_ATTENTION_REMINDERS_OPTION, L.SHOW_ATTENTION_REMINDERS_OPTION_DESC, notificationY,
        function() return iRC:GetSettings().showAttentionReminders == true end,
        function(value)
            iRC:GetSettings().showAttentionReminders = value and true or false
            if iRC.ConnectionDashboard and iRC.ConnectionDashboard.CheckAttentionReminder then
                iRC.ConnectionDashboard:CheckAttentionReminder(false)
            end
        end, false)
    notificationBaseHeight = math.abs(notificationY) + 6
    welcomeConflictText, notificationY = CreateInfoText(notificationCard, "", notificationY - 2, "GameFontNormal")
    welcomeConflictAccept, notificationY = CreateSettingsButton(notificationCard, L.MANAGEMENT_CONFLICT_ACCEPT, 130, notificationY, function()
        iRC:ResolveManagementConflict("WELCOME", true)
    end)
    welcomeConflictKeep = CreateSettingsButton(notificationCard, L.MANAGEMENT_CONFLICT_KEEP, 130, notificationY + 30, function()
        iRC:ResolveManagementConflict("WELCOME", false)
    end)
    welcomeConflictKeep:ClearAllPoints()
    welcomeConflictKeep:SetPoint("LEFT", welcomeConflictAccept, "RIGHT", 8, 0)
    notificationConflictHeight = math.abs(notificationY) + 18
    notificationCard:SetHeight(notificationBaseHeight)
    y = notificationCardTop - notificationBaseHeight - 12
    guildNotificationsContent:SetHeight(math.max(math.abs(y) + 8, 300))

    local permissionPageY = -12
    _, permissionPageY = CreateSectionHeader(guildPermissionsContent, L.DELEGATED_PERMISSIONS_CATEGORY, permissionPageY)
    managementConnectionCards.permissions, permissionPageY = CreateConnectionStatusCard(guildPermissionsContent, permissionPageY)
    local permissionStartY
    permissionCard, permissionStartY = CreateManagementSettingsCard(guildPermissionsContent,
        "Rank access",
        "Choose the lowest rank allowed to use each tool. That rank and every rank above it receive access.", permissionPageY - 2)
    local permissionLabels = {
        verification = "Verification decisions", presence = "Presence checks and automatic warnings",
        incidents = "Incident history", tradeExceptions = "Guild-Found trade exceptions",
        notifications = "Welcome notifications", homepage = "Guild Homepage contacts",
        rosterHistory = "Guild Log and member history", identity = "Assign member mains and alts",
        memberRemoval = "Review and remove inactive members",
        rankManagement = "Promote and demote guild members",
        recruitment = "Search for and invite guild recruits",
    }
    local function rankValues(minimumRankIndex)
        local values = {}
        minimumRankIndex = math.max(0, math.floor(tonumber(minimumRankIndex) or 0))
        for _, rank in ipairs(iRC:GetGuildRankOptions()) do
            if rank.index >= minimumRankIndex then values[#values + 1] = rank.index end
        end
        if #values == 0 then values = minimumRankIndex > 0 and { minimumRankIndex } or { 0, 1 } end
        return values
    end
    local function rankLabel(value)
        for _, rank in ipairs(iRC:GetGuildRankOptions()) do
            if rank.index == value then
                return value == 0 and (rank.name .. " (Guild Master)") or (rank.name .. " (Rank " .. value .. ")")
            end
        end
        if value == 0 then return "Guild Master" end
        return "Rank " .. tostring(value)
    end
    local function effectiveAccessNames(permission)
        local records = {}
        local guildMasterRank = iRC:GetGuildMasterRank()
        local allowedRank = permission and iRC:GetGuildRankPermission(permission) or nil
        for _, member in ipairs(iRC:GetGuildRosterSnapshot()) do
            local rankIndex = tonumber(member.rankIndex)
            if rankIndex then
                local guildMasterAccess = rankIndex == 0
                    or guildMasterRank > 0 and rankIndex <= guildMasterRank
                local rankAccess = permission and rankIndex <= allowedRank or guildMasterAccess
                local individual = permission and iRC:GetGuildMemberPermission(member.name, permission) or false
                if rankAccess or individual then
                    records[#records + 1] = {
                        name = member.name,
                        label = iRC:FormatPlayerName(member.name) .. (individual and "*" or ""),
                    }
                end
            end
        end
        table.sort(records, function(a, b) return iRC:NormalizeName(a.name) < iRC:NormalizeName(b.name) end)
        local names = {}
        for index, record in ipairs(records) do names[index] = record.label end
        return names
    end
    local permissionY = permissionStartY
    rankPermissionDropdowns.guildMasterRank, permissionY = CreateCompactManagementDropdown("iRCGuildMasterRankPermission",
        permissionCard, "Guild master rank", permissionY,
        function() return iRC:GetGuildMasterRank() end,
        function(value) iRC:SetGuildMasterRank(value) end,
        function() return rankValues(0) end, rankLabel,
        function() return effectiveAccessNames(nil) end)
    for _, permission in ipairs(iRC.PermissionOrder) do
        local permissionKey = permission
        rankPermissionDropdowns[permission], permissionY = CreateCompactManagementDropdown("iRCRankPermission" .. permission,
            permissionCard, permissionLabels[permission], permissionY,
            function()
                return math.max(iRC:GetGuildRankPermission(permissionKey), iRC:GetGuildMasterRank())
            end,
            function(value) iRC:SetGuildRankPermission(permissionKey, value) end,
            function() return rankValues(iRC:GetGuildMasterRank()) end, rankLabel,
            function() return effectiveAccessNames(permissionKey) end)
    end
    permissionCardHeight = math.abs(permissionY) + 12
    permissionCard:SetHeight(permissionCardHeight)
    permissionPageY = permissionPageY - permissionCardHeight - 14

    local memberCard, memberY = CreateManagementSettingsCard(guildPermissionsContent,
        "Specific member access",
        "Search the current roster and grant selected tools regardless of guild rank. These switches show individual grants only; rank access still applies separately.", permissionPageY)
    local selectPermissionMember
    local grantsLabel = memberCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    grantsLabel:SetPoint("TOPLEFT", memberCard, "TOPLEFT", 18, memberY - 2)
    grantsLabel:SetText("Members with special grants")
    grantsLabel:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
    local configuredText = memberCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    configuredText:SetPoint("TOPRIGHT", memberCard, "TOPRIGHT", -20, memberY - 2)
    configuredText:SetJustifyH("RIGHT")

    local grantsBox = CreateFrame("Frame", nil, memberCard, "BackdropTemplate")
    grantsBox:SetPoint("TOPLEFT", memberCard, "TOPLEFT", 18, memberY - 20)
    grantsBox:SetPoint("TOPRIGHT", memberCard, "TOPRIGHT", -18, memberY - 20)
    grantsBox:SetHeight(66)
    grantsBox:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 9,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    grantsBox:SetBackdropColor(0.025, 0.022, 0.018, 0.98)
    grantsBox:SetBackdropBorderColor(0.34, 0.28, 0.20, 0.95)
    local grantsScroll = CreateFrame("ScrollFrame", nil, grantsBox, "UIPanelScrollFrameTemplate")
    iRC:StyleScrollFrame(grantsScroll)
    grantsScroll:SetPoint("TOPLEFT", grantsBox, "TOPLEFT", 7, -6)
    grantsScroll:SetPoint("BOTTOMRIGHT", grantsBox, "BOTTOMRIGHT", -24, 6)
    local grantsContent = CreateFrame("Frame", nil, grantsScroll)
    grantsContent:SetSize(482, 1)
    grantsScroll:SetScrollChild(grantsContent)
    grantsBox:EnableMouseWheel(true)
    grantsBox:SetScript("OnMouseWheel", function(_, delta)
        local maximum = math.max(0, grantsContent:GetHeight() - grantsScroll:GetHeight())
        grantsScroll:SetVerticalScroll(math.max(0,
            math.min(maximum, grantsScroll:GetVerticalScroll() - delta * 26)))
    end)
    local grantsEmpty = grantsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    grantsEmpty:SetPoint("TOPLEFT", grantsContent, "TOPLEFT", 8, -8)
    grantsEmpty:SetText("No individual member grants are configured.")
    local grantButtons = {}
    memberY = memberY - 94

    local searchLabel = memberCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    searchLabel:SetPoint("TOPLEFT", memberCard, "TOPLEFT", 18, memberY)
    searchLabel:SetText("Roster member")
    local memberSearch = CreateFrame("EditBox", nil, memberCard, "InputBoxTemplate")
    memberSearch:SetSize(315, 24)
    memberSearch:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", 0, -6)
    memberSearch:SetAutoFocus(false)
    memberSearch:SetMaxLetters(80)
    memberSearch:SetTextInsets(6, 6, 0, 0)
    local selectedText = memberCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    selectedText:SetPoint("LEFT", memberSearch, "RIGHT", 18, 0)
    selectedText:SetPoint("RIGHT", memberCard, "RIGHT", -18, 0)
    selectedText:SetJustifyH("LEFT")

    local suggestions = CreateFrame("Frame", nil, memberCard, "BackdropTemplate")
    suggestions:SetSize(315, 148)
    suggestions:SetPoint("TOPLEFT", memberSearch, "BOTTOMLEFT", 0, -2)
    suggestions:SetFrameStrata("FULLSCREEN_DIALOG")
    suggestions:SetFrameLevel(memberCard:GetFrameLevel() + 30)
    suggestions:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    suggestions:SetBackdropColor(0.03, 0.025, 0.02, 0.99)
    suggestions:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.9)
    suggestions:Hide()
    local suggestionButtons = {}

    selectPermissionMember = function(name)
        local fullName = iRC:ResolveGuildMemberFullName(name)
        if not fullName then return false end
        selectedPermissionMember = fullName
        memberSearch:SetText(iRC:FormatPlayerName(fullName))
        memberSearch:SetCursorPosition(#memberSearch:GetText())
        memberSearch:ClearFocus()
        suggestions:Hide()
        if refreshMemberPermissionControls then refreshMemberPermissionControls() end
        return true
    end

    for index = 1, 6 do
        local button = CreateFrame("Button", nil, suggestions)
        button:SetSize(297, 23)
        button:SetPoint("TOPLEFT", suggestions, "TOPLEFT", 7, -6 - (index - 1) * 23)
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        button.text:SetPoint("LEFT", 7, 0)
        button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
        button.highlight:SetAllPoints()
        button.highlight:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.16)
        button:SetScript("OnMouseDown", function(self, mouseButton)
            if mouseButton == "LeftButton" and self.memberName then selectPermissionMember(self.memberName) end
        end)
        suggestionButtons[index] = button
    end

    local function updatePermissionSuggestions()
        local searchValue = memberSearch:GetText():match("^%s*(.-)%s*$")
        if selectedPermissionMember
            and searchValue:lower() ~= iRC:FormatPlayerName(selectedPermissionMember):lower() then
            selectedPermissionMember = nil
            if refreshMemberPermissionControls then refreshMemberPermissionControls() end
        end
        local query = searchValue:lower()
        local matches = {}
        if query ~= "" and GetNumGuildMembers and GetGuildRosterInfo then
            for index = 1, GetNumGuildMembers(true) do
                local name = GetGuildRosterInfo(index)
                local display = name and iRC:FormatPlayerName(name)
                if display and display:lower():find(query, 1, true) then
                    matches[#matches + 1] = { name = name, display = display,
                        starts = display:lower():find(query, 1, true) == 1 }
                end
            end
            table.sort(matches, function(a, b)
                if a.starts ~= b.starts then return a.starts end
                return a.display:lower() < b.display:lower()
            end)
        end
        for index, button in ipairs(suggestionButtons) do
            local match = matches[index]
            button.memberName = match and match.name or nil
            button:SetShown(match ~= nil)
            if match then button.text:SetText(match.display) end
        end
        suggestions:SetShown(memberSearch:HasFocus() and matches[1] ~= nil)
    end
    memberSearch:SetScript("OnTextChanged", updatePermissionSuggestions)
    memberSearch:SetScript("OnEditFocusGained", updatePermissionSuggestions)
    memberSearch:SetScript("OnEditFocusLost", function()
        C_Timer.After(0, function()
            if not memberSearch:HasFocus() and not iRC:IsMouseOverFrame(suggestions) then suggestions:Hide() end
        end)
    end)
    memberSearch:SetScript("OnEnterPressed", function(self)
        local first = suggestionButtons[1]
        if first and first:IsShown() and first.memberName then selectPermissionMember(first.memberName)
        else selectPermissionMember(self:GetText()) end
    end)
    memberSearch:SetScript("OnEscapePressed", function(self) suggestions:Hide(); self:ClearFocus() end)
    iRC:StyleSearchBox(memberSearch)
    memberY = memberY - 62

    for _, permission in ipairs(iRC.PermissionOrder) do
        local permissionKey = permission
        namedPermissionChecks[permission], memberY = CreateCompactManagementToggle(memberCard,
            permissionLabels[permission], "Additional access for only the selected roster member.", memberY,
            function()
                return selectedPermissionMember
                    and iRC:GetGuildMemberPermission(selectedPermissionMember, permissionKey)
            end,
            function(value)
                if selectedPermissionMember then
                    iRC:SetGuildMemberPermission(selectedPermissionMember, permissionKey, value)
                end
            end, true)
    end

    refreshMemberPermissionControls = function()
        local canEdit = iRC:IsGuildMaster() and selectedPermissionMember ~= nil
        selectedText:SetText(selectedPermissionMember
            and (iRC.Colors.Green .. "Editing " .. iRC:FormatPlayerName(selectedPermissionMember) .. iRC.Colors.Reset)
            or (iRC.Colors.Gray .. "Choose a roster member" .. iRC.Colors.Reset))
        local configuredEntries = iRC:GetGuildMemberPermissionEntries()
        local configuredCount = #configuredEntries
        configuredText:SetText(configuredCount > 0
            and (tostring(configuredCount) .. (configuredCount == 1 and " member" or " members") .. " · Click to edit")
            or "None configured")
        local classColors = {}
        for _, member in ipairs(iRC:GetGuildRosterSnapshot()) do
            classColors[iRC:NormalizeName(member.name)] = member.classFile
        end
        for index, entry in ipairs(configuredEntries) do
            local button = grantButtons[index]
            if not button then
                button = CreateFrame("Button", nil, grantsContent, "BackdropTemplate")
                button:SetSize(238, 24)
                button:SetBackdrop({
                    bgFile = "Interface\\BUTTONS\\WHITE8X8",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    edgeSize = 8,
                    insets = { left = 2, right = 2, top = 2, bottom = 2 },
                })
                button.name = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                button.name:SetPoint("LEFT", button, "LEFT", 9, 0)
                button.name:SetPoint("RIGHT", button, "RIGHT", -72, 0)
                button.name:SetJustifyH("LEFT")
                button.count = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                button.count:SetPoint("RIGHT", button, "RIGHT", -8, 0)
                button.count:SetJustifyH("RIGHT")
                button:SetScript("OnClick", function(self)
                    if self.memberName then selectPermissionMember(self.memberName) end
                end)
                button:SetScript("OnEnter", function(self)
                    self:SetBackdropColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.14)
                    if not GameTooltip then return end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(iRC:FormatPlayerName(self.memberName or ""))
                    GameTooltip:AddLine("Individual grants", 1, 0.72, 0.12)
                    for _, grantedLabel in ipairs(self.grantedLabels or {}) do
                        GameTooltip:AddLine("• " .. grantedLabel, 0.82, 0.82, 0.82)
                    end
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Click to review or change these grants.", 0.38, 1, 0.48, true)
                    GameTooltip:Show()
                end)
                button:SetScript("OnLeave", function(self)
                    self:SetBackdropColor(self.selected and 0.04 or 0.055,
                        self.selected and 0.15 or 0.045, self.selected and 0.06 or 0.035, 0.98)
                    if GameTooltip then GameTooltip:Hide() end
                end)
                grantButtons[index] = button
            end
            local column, rowIndex = (index - 1) % 2, math.floor((index - 1) / 2)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", grantsContent, "TOPLEFT", column * 244, -(rowIndex * 27))
            button.memberName = entry.name
            button.selected = selectedPermissionMember
                and iRC:NormalizeName(selectedPermissionMember) == iRC:NormalizeName(entry.name) or false
            button.name:SetText(iRC:FormatPlayerName(entry.name))
            local classFile = classColors[iRC:NormalizeName(entry.name)]
            local classColor = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
            if classColor then button.name:SetTextColor(classColor.r, classColor.g, classColor.b)
            else button.name:SetTextColor(1, 0.72, 0.12) end
            button.count:SetText(tostring(entry.count) .. (entry.count == 1 and " grant" or " grants"))
            button.grantedLabels = {}
            for _, permission in ipairs(iRC.PermissionOrder) do
                if entry.permissions and entry.permissions[permission] == true then
                    button.grantedLabels[#button.grantedLabels + 1] = permissionLabels[permission]
                end
            end
            button:SetBackdropColor(button.selected and 0.04 or 0.055,
                button.selected and 0.15 or 0.045, button.selected and 0.06 or 0.035, 0.98)
            button:SetBackdropBorderColor(button.selected and 0.20 or 0.34,
                button.selected and 0.78 or 0.28, button.selected and 0.32 or 0.20, 1)
            button:Show()
        end
        for index = configuredCount + 1, #grantButtons do grantButtons[index]:Hide() end
        grantsEmpty:SetShown(configuredCount == 0)
        grantsContent:SetHeight(math.max(1, math.ceil(configuredCount / 2) * 27))
        grantsScroll:UpdateScrollChildRect()
        for _, control in pairs(namedPermissionChecks) do
            control:Refresh()
            control:SetEnabled(canEdit)
            control:SetAlpha(canEdit and 1 or 0.42)
        end
    end
    refreshMemberPermissionControls()
    local memberCardHeight = math.abs(memberY) + 10
    memberCard:SetHeight(memberCardHeight)
    permissionPageY = permissionPageY - memberCardHeight - 12
    guildPermissionsContent:SetHeight(math.max(math.abs(permissionPageY) + 8, 300))
end

-- Notification and admin settings ------------------------------------------

local function LayoutGuildNotificationCards(showConflict)
    local notificationHeight = showConflict and notificationConflictHeight or notificationBaseHeight
    notificationCard:SetHeight(notificationHeight)
    local contentBottom = notificationCardTop - notificationHeight - 12
    guildNotificationsContent:SetHeight(math.max(math.abs(contentBottom) + 8, 300))
end

local testGuildMasterCheck, suppressWarningsCheck, suppressRulesCheck, testAdminStatus, testGuildStatus, testActivateGuildButton
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
    suppressWarningsCheck, y = CreateSettingsCheckbox(adminContent, L.TEST_ADMIN_SUPPRESS_WARNINGS, L.TEST_ADMIN_SUPPRESS_WARNINGS_DESC, y,
        function() return iRC:SuppressesPresenceWarnings() end,
        function(value) iRC:GetSettings().suppressPresenceWarnings = value and true or false end)
    suppressRulesCheck, y = CreateSettingsCheckbox(adminContent, L.TEST_ADMIN_SUPPRESS_RULES, L.TEST_ADMIN_SUPPRESS_RULES_DESC, y,
        function() return iRC:SuppressesRuleSending() end,
        function(value) iRC:GetSettings().suppressRuleSending = value and true or false end)
    _, y = CreateSubcategoryHeader(adminContent, L.TEST_ADMIN_ONLINE_HEADER, y - 5)
    _, y = CreateInfoText(adminContent, L.TEST_ADMIN_ONLINE_DESC, y, "GameFontDisableSmall")
    local adminOnlineStatus, adminOnlineRows = nil, {}
    _, y = CreateSettingsButton(adminContent, L.TEST_ADMIN_ONLINE_REFRESH, 190, y - 3, function()
        if not iRC.RaceGrid or not iRC.RaceGrid:RequestAdminOnlineUsers() then
            iRC:Print(L.TEST_ADMIN_ONLINE_UNAVAILABLE)
        end
    end, L.TEST_ADMIN_ONLINE_DESC)
    adminOnlineStatus = adminContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    adminOnlineStatus:SetPoint("TOPLEFT", adminContent, "TOPLEFT", 25, y - 1)
    adminOnlineStatus:SetPoint("RIGHT", adminContent, "RIGHT", -20, 0)
    adminOnlineStatus:SetHeight(34)
    adminOnlineStatus:SetJustifyH("LEFT")
    adminOnlineStatus:SetJustifyV("TOP")
    adminOnlineStatus:SetText(L.TEST_ADMIN_ONLINE_EMPTY)
    y = y - 39

    local onlineList = CreateFrame("Frame", nil, adminContent, "BackdropTemplate")
    onlineList:SetPoint("TOPLEFT", adminContent, "TOPLEFT", 20, y)
    onlineList:SetPoint("TOPRIGHT", adminContent, "TOPRIGHT", -15, y)
    onlineList:SetHeight(185)
    onlineList:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    onlineList:SetBackdropColor(0.035, 0.035, 0.055, 0.94)
    onlineList:SetBackdropBorderColor(0.34, 0.28, 0.20, 0.9)
    local onlineHeader = CreateFrame("Frame", nil, onlineList)
    onlineHeader:SetPoint("TOPLEFT", onlineList, "TOPLEFT", 5, -4)
    onlineHeader:SetPoint("TOPRIGHT", onlineList, "TOPRIGHT", -24, -4)
    onlineHeader:SetHeight(20)
    local function CreateOnlineColumn(parent, text, point, width)
        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", parent, "LEFT", point, 0)
        label:SetWidth(width)
        label:SetJustifyH("LEFT")
        label:SetText(text)
        label:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
        return label
    end
    CreateOnlineColumn(onlineHeader, "Player", 5, 175)
    CreateOnlineColumn(onlineHeader, "Version", 185, 85)
    CreateOnlineColumn(onlineHeader, "Guild", 275, 205)
    local onlineScroll = CreateFrame("ScrollFrame", nil, onlineList, "UIPanelScrollFrameTemplate")
    iRC:StyleScrollFrame(onlineScroll)
    onlineScroll:SetPoint("TOPLEFT", onlineList, "TOPLEFT", 5, -25)
    onlineScroll:SetPoint("BOTTOMRIGHT", onlineList, "BOTTOMRIGHT", -24, 5)
    local onlineChild = CreateFrame("Frame", nil, onlineScroll)
    onlineChild:SetSize(480, 1)
    onlineScroll:SetScrollChild(onlineChild)
    onlineList:EnableMouseWheel(true)
    onlineList:SetScript("OnMouseWheel", function(_, delta)
        local maximum = math.max(0, onlineChild:GetHeight() - onlineScroll:GetHeight())
        onlineScroll:SetVerticalScroll(math.max(0, math.min(maximum, onlineScroll:GetVerticalScroll() - delta * 44)))
    end)
    y = y - 193

    local function RefreshAdminOnlineUsers()
        if not iRC.RaceGrid then return end
        local rows, stats = iRC.RaceGrid:GetAdminOnlineUsers()
        if (stats.total or 0) == 0 then
            adminOnlineStatus:SetText(L.TEST_ADMIN_ONLINE_EMPTY)
        else
            local coverage = stats.total > 0 and stats.known * 100 / stats.total or 0
            local versions = {}
            for version, count in pairs(stats.versions or {}) do
                versions[#versions + 1] = { version = version, count = count }
            end
            table.sort(versions, function(a, b)
                if a.count ~= b.count then return a.count > b.count end
                return a.version < b.version
            end)
            local labels = {}
            for index, entry in ipairs(versions) do
                if index > 5 then break end
                labels[#labels + 1] = entry.version .. " (" .. entry.count .. ")"
            end
            if #versions > 5 then labels[#labels + 1] = "+" .. (#versions - 5) .. " more" end
            adminOnlineStatus:SetText(iRC:Text("TEST_ADMIN_ONLINE_STATS", stats.total, stats.known, coverage) .. "\n"
                .. iRC:Text("TEST_ADMIN_ONLINE_VERSIONS", #labels > 0 and table.concat(labels, ", ") or L.TEST_ADMIN_ONLINE_UNKNOWN))
        end
        for index, data in ipairs(rows) do
            local row = adminOnlineRows[index]
            if not row then
                row = CreateFrame("Button", nil, onlineChild)
                row:SetHeight(22)
                row:RegisterForClicks("RightButtonUp")
                row.bg = row:CreateTexture(nil, "BACKGROUND")
                row.bg:SetAllPoints()
                row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
                row.highlight:SetAllPoints()
                row.highlight:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.14)
                row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.name:SetPoint("LEFT", row, "LEFT", 5, 0); row.name:SetWidth(175); row.name:SetJustifyH("LEFT")
                row.version = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.version:SetPoint("LEFT", row, "LEFT", 185, 0); row.version:SetWidth(85); row.version:SetJustifyH("LEFT")
                row.guild = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.guild:SetPoint("LEFT", row, "LEFT", 275, 0); row.guild:SetWidth(205); row.guild:SetJustifyH("LEFT")
                row:SetScript("OnClick", function(self, mouseButton)
                    if mouseButton == "RightButton" and self.playerName then
                        iRC:OpenWhisper(self.playerName, L.TEST_ADMIN_ONLINE_WHISPER_MESSAGE)
                    end
                end)
                row:SetScript("OnEnter", function(self)
                    if not self.playerName or not GameTooltip then return end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(iRC:FormatPlayerName(self.playerName), 1, 0.82, 0)
                    GameTooltip:AddLine(iRC:Text("TEST_ADMIN_ONLINE_WHISPER", iRC:FormatPlayerName(self.playerName)), 1, 1, 1)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
                adminOnlineRows[index] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", onlineChild, "TOPLEFT", 0, -(index - 1) * 22)
            row:SetPoint("TOPRIGHT", onlineChild, "TOPRIGHT", 0, -(index - 1) * 22)
            row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.035 or 0.075)
            row.playerName = data.name
            row.name:SetText(iRC:FormatPlayerName(data.name))
            row.version:SetText(data.version or L.TEST_ADMIN_ONLINE_UNKNOWN)
            row.version:SetTextColor(data.version and 0.35 or 0.65, data.version and 1 or 0.65, data.version and 0.40 or 0.65)
            row.guild:SetText(data.guildName ~= "" and data.guildName or "-")
            row:Show()
        end
        for index = #rows + 1, #adminOnlineRows do adminOnlineRows[index]:Hide() end
        onlineChild:SetHeight(math.max(1, #rows * 22))
    end
    _, y = CreateSubcategoryHeader(adminContent, L.TEST_ADMIN_TRAFFIC_HEADER, y - 5)
    local trafficStatus
    _, y = CreateSettingsCheckbox(adminContent, L.TEST_ADMIN_TRAFFIC_OPTION, L.TEST_ADMIN_TRAFFIC_OPTION_DESC, y,
        function() return iRC:GetSettings().showTrafficMonitorForTesting == true end,
        function(value)
            iRC:GetSettings().showTrafficMonitorForTesting = value and true or false
            iRC:SetTrafficMonitorEnabled(value)
        end)
    trafficStatus, y = CreateInfoText(adminContent, L.TEST_ADMIN_TRAFFIC_DISABLED, y - 2, "GameFontHighlight")
    iRC:SetTrafficMonitorEnabled(iRC:GetSettings().showTrafficMonitorForTesting == true)
    _, y = CreateSubcategoryHeader(adminContent, L.TEST_ADMIN_TRAFFIC_TOP_HEADER, y - 5)
    local trafficTop = adminContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    trafficTop:SetPoint("TOPLEFT", adminContent, "TOPLEFT", 25, y - 2)
    trafficTop:SetSize(490, 94)
    trafficTop:SetJustifyH("LEFT")
    trafficTop:SetJustifyV("TOP")
    trafficTop:SetText(L.TEST_ADMIN_TRAFFIC_EMPTY)
    y = y - 100
    _, y = CreateSubcategoryHeader(adminContent, L.TEST_ADMIN_CPU_HEADER, y - 5)
    _, y = CreateSettingsCheckbox(adminContent, L.TEST_ADMIN_CPU_OPTION, L.TEST_ADMIN_CPU_OPTION_DESC, y,
        function() return iRC:GetSettings().showFunctionProfilerForTesting == true end,
        function(value)
            iRC:GetSettings().showFunctionProfilerForTesting = value and true or false
            iRC:SetFunctionProfilerEnabled(value)
        end)
    local cpuStatus = adminContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cpuStatus:SetPoint("TOPLEFT", adminContent, "TOPLEFT", 25, y - 2)
    cpuStatus:SetSize(490, 98)
    cpuStatus:SetJustifyH("LEFT")
    cpuStatus:SetJustifyV("TOP")
    cpuStatus:SetText(L.TEST_ADMIN_CPU_DISABLED)
    y = y - 106
    iRC:SetFunctionProfilerEnabled(iRC:GetSettings().showFunctionProfilerForTesting == true)
    local trafficRefreshElapsed = 1
    adminContainer:SetScript("OnUpdate", function(_, elapsed)
        trafficRefreshElapsed = trafficRefreshElapsed + elapsed
        if trafficRefreshElapsed < 1 then return end
        trafficRefreshElapsed = 0
        RefreshAdminOnlineUsers()
        if iRC.TrafficMonitorEnabled then
            local incoming, outgoing = iRC:GetTrafficBytesLastMinute()
            trafficStatus:SetText(iRC:Text("TEST_ADMIN_TRAFFIC_BYTES", incoming, outgoing))
            local rows, lines = iRC:GetTrafficHotspots(), {}
            for index = 1, math.min(5, #rows) do
                local row = rows[index]
                lines[#lines + 1] = iRC:Text("TEST_ADMIN_TRAFFIC_ROW", row.label, row.bytes, row.incoming, row.outgoing)
            end
            trafficTop:SetText(#lines > 0 and table.concat(lines, "\n") or L.TEST_ADMIN_TRAFFIC_EMPTY)
        else
            trafficStatus:SetText(L.TEST_ADMIN_TRAFFIC_DISABLED)
            trafficTop:SetText(L.TEST_ADMIN_TRAFFIC_DISABLED)
        end
        if iRC.FunctionProfilerEnabled then
            local rows, lines = iRC:GetFunctionHotspots(), {}
            for index = 1, math.min(5, #rows) do
                local row = rows[index]
                lines[#lines + 1] = iRC:Text("TEST_ADMIN_CPU_ROW", row.label, row.ms, row.calls)
            end
            cpuStatus:SetText(#lines > 0 and table.concat(lines, "\n") or L.TEST_ADMIN_CPU_EMPTY)
        else
            cpuStatus:SetText(type(debugprofilestop) == "function" and L.TEST_ADMIN_CPU_DISABLED or L.TEST_ADMIN_CPU_UNAVAILABLE)
        end
    end)
    testActivateGuildButton, y = CreateSettingsButton(adminContent, L.TEST_ADMIN_ACTIVATE_GUILD, 190, y - 4, function()
        iRC:ActivateGuildForTesting()
    end, L.TEST_ADMIN_ACTIVATE_GUILD_DESC)
    _, y = CreateSettingsButton(adminContent, L.TEST_ADMIN_CLEAR_REPORTS, 220, y, function()
        local removed = iRC.RaceGrid and iRC.RaceGrid:ClearCachedReportsForTesting()
        if removed then iRC:Print(iRC:Text("TEST_ADMIN_CLEAR_REPORTS_DONE", removed)) end
    end, L.TEST_ADMIN_CLEAR_REPORTS_DESC)
    _, y = CreateSubcategoryHeader(adminContent, L.TEST_ADMIN_ANNOUNCEMENTS, y - 6)
    _, y = CreateInfoText(adminContent, L.TEST_ADMIN_ANNOUNCEMENTS_DESC, y, "GameFontDisableSmall")
    _, y = CreateSettingsButton(adminContent, L.TEST_ADMIN_DEATH_MESSAGE, 190, y - 4, function()
        if not iRC.GuildAnnouncements or not iRC.GuildAnnouncements:SendTest("death") then
            iRC:Print(L.TEST_ADMIN_ANNOUNCEMENT_UNAVAILABLE)
        end
    end)
    _, y = CreateSettingsButton(adminContent, L.TEST_ADMIN_LEVEL60_MESSAGE, 190, y, function()
        if not iRC.GuildAnnouncements or not iRC.GuildAnnouncements:SendTest("level60") then
            iRC:Print(L.TEST_ADMIN_ANNOUNCEMENT_UNAVAILABLE)
        end
    end)
    adminContent:SetHeight(math.abs(y) + 20)
end

local function RefreshGeneralNotificationAndAdminOptions()
    if generalContent.identityMainDropdown then generalContent.identityMainDropdown:Refresh() end
    hideChatIconCheck:Refresh()
    hideAllChatIconsCheck:Refresh()
    if debugModeCheck then debugModeCheck:Refresh() end
    if testGuildMasterCheck then
        testGuildMasterCheck:Refresh()
        suppressWarningsCheck:Refresh()
        suppressRulesCheck:Refresh()
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
    minimapCheck:Refresh()
    layerPanelCheck:Refresh()
    newMemberWelcomeCheck:Refresh()
    local notificationsEnabled = iRC:HasGuildPermission("notifications") and iRC:IsGuildConnectionActive()
    newMemberWelcomeCheck:SetEnabled(notificationsEnabled)
    if newMemberWelcomeCheck.managementRow then newMemberWelcomeCheck.managementRow:SetAlpha(notificationsEnabled and 1 or 0.48) end
    for _, checkbox in pairs(automaticWarningChecks) do
        checkbox:Refresh()
        checkbox:SetEnabled(notificationsEnabled)
        if checkbox.managementRow then checkbox.managementRow:SetAlpha(notificationsEnabled and 1 or 0.48) end
    end
    showAttentionRemindersCheck:Refresh()
    local remindersEnabled = iRC:HasGuildPermission("verification") and iRC:IsGuildConnectionActive()
    showAttentionRemindersCheck:SetEnabled(remindersEnabled)
    if showAttentionRemindersCheck.managementRow then showAttentionRemindersCheck.managementRow:SetAlpha(remindersEnabled and 1 or 0.48) end
    local guildMaster = iRC:IsGuildMaster()
    local nativeGuildMaster = iRC:IsNativeGuildMaster()
    for permission, dropdown in pairs(rankPermissionDropdowns) do
        dropdown:Refresh()
        local canEdit = permission == "guildMasterRank" and nativeGuildMaster or (permission ~= "guildMasterRank" and guildMaster)
        dropdown:SetEnabled(canEdit and true or false)
        if dropdown.managementRow then dropdown.managementRow:SetAlpha(canEdit and 1 or 0.48) end
    end
    if refreshMemberPermissionControls then refreshMemberPermissionControls() end
    local welcomeConflict = iRC:GetPendingManagementConflict("WELCOME")
    welcomeConflictText:SetText(welcomeConflict and iRC:Text("MANAGEMENT_CONFLICT_INLINE", iRC:FormatPlayerName(welcomeConflict.source)) or "")
    welcomeConflictAccept:SetShown(welcomeConflict ~= nil)
    welcomeConflictKeep:SetShown(welcomeConflict ~= nil)
    LayoutGuildNotificationCards(welcomeConflict ~= nil)
    slider:SetValue(iRC:GetSettings().mainWindowScale or 1)
end

-- Refresh and embedded-panel lifecycle -------------------------------------

local function Refresh()
    if diagnosticsEnabledCheck then diagnosticsEnabledCheck:Refresh() end
    local managementAvailable = CanUseManagementTools()
    local canSwitchRulesView = managementAvailable or iRC:IsTestAdminGuildMaster()
    RefreshRulesView(canSwitchRulesView)
    LayoutSidebar(managementAvailable)
    if (selectedTab == 8 or selectedTab == 10 or selectedTab == 11) and not managementAvailable then ShowTab(2) end
    if guildFoundAuditText then
        local records = iRC.GetGuildFoundAuditRecords and iRC:GetGuildFoundAuditRecords() or {}
        local lines = {}
        for index = #records, math.max(1, #records - 14), -1 do
            local record = records[index]
            lines[#lines + 1] = iRC:Text("GUILDFOUND_AUDIT_ROW",
                date("%Y-%m-%d %H:%M", record.occurredAt or 0), record.player or "?",
                iRC:Text("GUILDFOUND_AUDIT_ACTION_" .. tostring(record.action)), record.target or "-")
        end
        guildFoundAuditText:SetText(#lines > 0 and table.concat(lines, "\n") or L.GUILDFOUND_AUDIT_EMPTY)
        local auditHeight = math.max(105, guildFoundAuditText:GetStringHeight() + 82)
        guildFoundAuditText.managementCard:SetHeight(auditHeight)
        guildFoundContent:SetHeight(math.max(math.abs(guildFoundAuditText.cardTop) + auditHeight + 20, 450))
    end
    RefreshGeneralNotificationAndAdminOptions()
    local connection = iRC:GetConnection()
    local guildActive = connection and iRC:IsGuildConnectionActive()
    local guildFoundRules = iRC:GetConnectionRules()
    local protectionActive = guildActive and iRC:IsGuildFoundRequired(connection)
    local exceptionsEnabled = protectionActive and guildFoundRules.guildFoundTradeExceptions == true
    local managementAvailableForGuildFound = guildActive and iRC:HasGuildPermission("tradeExceptions")
    local function guildFoundStatusText(labelKey, enabled, enabledKey, disabledKey)
        local color = enabled and iRC.Colors.Green or iRC.Colors.Gray
        return iRC:Text(labelKey, color .. iRC:Text(enabled and enabledKey or disabledKey) .. iRC.Colors.Reset)
    end
    guildFoundStatus.protection:SetText(guildFoundStatusText("GUILDFOUND_STATUS_PROTECTION",
        protectionActive, "GUILDFOUND_STATUS_ACTIVE", "GUILDFOUND_STATUS_INACTIVE"))
    guildFoundStatus.exceptions:SetText(guildFoundStatusText("GUILDFOUND_STATUS_EXCEPTIONS",
        exceptionsEnabled, "GUILDFOUND_STATUS_ENABLED", "GUILDFOUND_STATUS_DISABLED"))
    guildFoundStatus.access:SetText(guildFoundStatusText("GUILDFOUND_STATUS_ACCESS",
        managementAvailableForGuildFound, "GUILDFOUND_STATUS_AVAILABLE", "GUILDFOUND_STATUS_READ_ONLY"))
    if connection then
        if iRC:IsGuildConnectionActive() then
            connectionStatus:SetText(iRC.Colors.Green .. "Connected" .. iRC.Colors.Reset)
            connectionDetail:SetText("Guild: " .. iRC.Colors.Orange .. connection.guildName .. iRC.Colors.Reset
                .. "  |  Sharing and checks are active.\n" .. GetRulesetMetadataText(connection))
        else
            connectionStatus:SetText(iRC.Colors.Yellow .. L.CONNECTION_STATUS_INACTIVE .. iRC.Colors.Reset)
            connectionDetail:SetText(string.format(L.CONNECTION_DETAIL_INACTIVE,
                iRC.Colors.Orange .. connection.guildName .. iRC.Colors.Reset)
                .. "\n" .. GetRulesetMetadataText(connection))
        end
    else
        connectionStatus:SetText(iRC.Colors.Red .. "No active guild connection" .. iRC.Colors.Reset)
        connectionDetail:SetText("Join a guild to use shared progress and rules.")
    end
    RefreshAllManagementConnectionCards(connection)
    guildActivationCheck:Refresh()
    raceRuleUI.lock:Refresh()
    raceRuleUI.classLock:Refresh()
    raceRuleUI.race:Refresh()
    raceRuleUI.language:Refresh()
    progressionModeDropdown:Refresh()
    maxLevelProgressionDropdown:Refresh()
    guildFoundTradeExceptionsCheck:Refresh()
    if refreshGuildFoundTradeItemList then refreshGuildFoundTradeItemList() end
    guildMapRuleCheck:Refresh()
    raceRuleUI.level60Message:Refresh()
    levelAnnouncementDropdown:Refresh()
    raceRuleUI.professionMessage:Refresh()
    professionAnnouncementDropdown:Refresh()
    raceRuleUI.deathMessage:Refresh()
    raceRuleUI.groups:Refresh()
    refreshingSameRaceLevel = true
    sameRaceLevelSlider:SetValue(iRC:GetConnectionRules().sameRaceMinimumLevel or 1)
    refreshingSameRaceLevel = false
    raceRuleUI.level60Exception:Refresh()
    guildGroupsOnlyCheck:Refresh()
    refreshingGuildGroupsLevel = true
    guildGroupsLevelSlider:SetValue(iRC:GetConnectionRules().guildGroupsMinimumLevel or 1)
    refreshingGuildGroupsLevel = false
    local isGuildMaster = connection and iRC:IsGuildMaster()
    local canEditHomepage = guildActive and iRC:HasGuildPermission("homepage")
    homepageDescriptionUI:Refresh(connection, canEditHomepage)
    broadcastButton:SetEnabled(guildActive and true or false)
    guildActivationCheck:SetEnabled(isGuildMaster and true or false)
    local raceLockEnabled = guildActive and iRC:GetConnectionRules().raceLock == true
    raceRuleUI.lock:SetEnabled(isGuildMaster and guildActive and true or false)
    raceRuleUI.classLock:SetEnabled(isGuildMaster and guildActive and true or false)
    if isGuildMaster and raceLockEnabled then
        UIDropDownMenu_EnableDropDown(raceRuleUI.race)
    else
        UIDropDownMenu_DisableDropDown(raceRuleUI.race)
    end
    raceRuleUI.language:SetEnabled(isGuildMaster and raceLockEnabled and true or false)
    if isGuildMaster and guildActive then
        UIDropDownMenu_EnableDropDown(progressionModeDropdown)
    else
        UIDropDownMenu_DisableDropDown(progressionModeDropdown)
    end
    local maxLevelModeEnabled = isGuildMaster and guildActive and iRC:GetProgressionMode() == "SELF_FOUND"
    if maxLevelModeEnabled then UIDropDownMenu_EnableDropDown(maxLevelProgressionDropdown)
    else UIDropDownMenu_DisableDropDown(maxLevelProgressionDropdown) end
    local tradeExceptionsRuleEnabled = isGuildMaster and guildActive and iRC:IsGuildFoundRequired()
    guildFoundTradeExceptionsCheck:SetEnabled(tradeExceptionsRuleEnabled and true or false)
    guildMapRuleCheck:SetEnabled(isGuildMaster and guildActive and true or false)
    raceRuleUI.level60Message:SetEnabled(isGuildMaster and guildActive and true or false)
    if isGuildMaster and guildActive and iRC:GetConnectionRules().enableGuildLevel60Message then
        UIDropDownMenu_EnableDropDown(levelAnnouncementDropdown)
    else
        UIDropDownMenu_DisableDropDown(levelAnnouncementDropdown)
    end
    raceRuleUI.professionMessage:SetEnabled(isGuildMaster and guildActive and true or false)
    if isGuildMaster and guildActive and iRC:GetConnectionRules().enableGuildProfessionMessage then
        UIDropDownMenu_EnableDropDown(professionAnnouncementDropdown)
    else
        UIDropDownMenu_DisableDropDown(professionAnnouncementDropdown)
    end
    local deathMessageAvailable = iRC:IsOfficialHardcoreRealm()
    raceRuleUI.deathMessage:Show()
    connectionContent:SetHeight(math.abs(deathMessageBottomY) + 20)
    readOnlyRules:SetHeight(math.abs(deathMessageBottomY - rulesEditorTopY) + 24)
    raceRuleUI.deathMessage:SetEnabled(deathMessageAvailable and isGuildMaster and guildActive and true or false)
    raceRuleUI.groups:SetEnabled(isGuildMaster and raceLockEnabled and true or false)
    local sameRaceExceptionEnabled = isGuildMaster and raceLockEnabled and iRC:GetConnectionRules().sameRaceGroupsOnly
    sameRaceLevelSlider:SetEnabled(sameRaceExceptionEnabled and true or false)
    local sameRaceLevelColor = sameRaceExceptionEnabled and iRC.ColorValues.Green or iRC.ColorValues.Gray
    sameRaceLevelLabel:SetTextColor(sameRaceLevelColor[1], sameRaceLevelColor[2], sameRaceLevelColor[3])
    raceRuleUI.level60Exception:SetEnabled(sameRaceExceptionEnabled and true or false)
    guildGroupsOnlyCheck:SetEnabled(isGuildMaster and guildActive and true or false)
    local guildGroupsLevelEnabled = isGuildMaster and guildActive and iRC:GetConnectionRules().guildGroupsOnly
    guildGroupsLevelSlider:SetEnabled(guildGroupsLevelEnabled and true or false)
    local guildGroupsLevelColor = guildGroupsLevelEnabled and iRC.ColorValues.Green or iRC.ColorValues.Gray
    guildGroupsLevelLabel:SetTextColor(guildGroupsLevelColor[1], guildGroupsLevelColor[2], guildGroupsLevelColor[3])
    local rules = iRC:GetConnectionRules()
    SetRuleVisualState(guildActivationCheck, guildActive)
    SetRuleVisualState(raceRuleUI.lock, rules.raceLock)
    SetRuleVisualState(raceRuleUI.classLock, rules.classLock)
    SetRuleVisualState(raceRuleUI.language, rules.raceLock and rules.nativeTongueOnly)
    SetRuleVisualState(guildFoundTradeExceptionsCheck, rules.guildFoundTradeExceptions)
    SetRuleVisualState(guildMapRuleCheck, rules.guildMapEnabled)
    SetRuleVisualState(raceRuleUI.level60Message, rules.enableGuildLevel60Message)
    SetRuleVisualState(raceRuleUI.professionMessage, rules.enableGuildProfessionMessage)
    SetRuleVisualState(raceRuleUI.deathMessage, rules.enableGuildDeathMessage)
    SetRuleVisualState(raceRuleUI.groups, rules.raceLock and rules.sameRaceGroupsOnly)
    SetRuleVisualState(raceRuleUI.level60Exception, rules.raceLock and rules.sameRaceGroupsOnly and rules.allowLevel60MixedRaceGroups)
    SetRuleVisualState(guildGroupsOnlyCheck, rules.guildGroupsOnly)
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
    local isTauren = iRC.Roleplay and iRC.Roleplay:IsTauren()
    local isNightElf = iRC.Roleplay and iRC.Roleplay:IsNightElf()
    local isUndead = iRC.Roleplay and iRC.Roleplay:IsUndead()
    trollTalkCheck:SetEnabled(isTroll and true or false)
    taurenTalkCheck:Refresh()
    taurenTalkCheck:SetEnabled(isTauren and true or false)
    nightElfTalkCheck:Refresh()
    nightElfTalkCheck:SetEnabled(isNightElf and true or false)
    undeadSpeakCheck:Refresh()
    undeadSpeakCheck:SetEnabled(isUndead and true or false)
    if isTroll then
        trollTalkStatus:SetText(iRC.Colors.Green .. "Troll character detected." .. iRC.Colors.Reset .. " This setting only affects this character.")
    elseif isTauren then
        trollTalkStatus:SetText(iRC.Colors.Green .. L.TAUREN_TALK_DETECTED .. iRC.Colors.Reset .. " " .. L.RACE_TALK_CHARACTER_ONLY)
    elseif isNightElf then
        trollTalkStatus:SetText(iRC.Colors.Green .. L.NIGHT_ELF_TALK_DETECTED .. iRC.Colors.Reset .. " " .. L.RACE_TALK_CHARACTER_ONLY)
    elseif isUndead then
        trollTalkStatus:SetText(iRC.Colors.Green .. L.UNDEAD_SPEAK_DETECTED .. iRC.Colors.Reset .. " " .. L.RACE_TALK_CHARACTER_ONLY)
    else
        trollTalkStatus:SetText(iRC.Colors.Gray .. L.RACE_TALK_UNAVAILABLE .. iRC.Colors.Reset)
    end
    for _, addon in ipairs(companionAddons) do
        local loaded = IsAddonLoadedCompat(addon.addonName)
        addon.installedFrame:SetShown(loaded)
        addon.promoFrame:SetShown(not loaded)
    end
end

local managementPanels

local function GetPanelScrollFrame(panel)
    if not panel then return nil end
    if panel.scrollFrame then return panel.scrollFrame end
    local child = panel:GetChildren()
    return child and child.GetVerticalScroll and child or nil
end

local function RestorePanelScroll(panel, position)
    local scrollFrame = GetPanelScrollFrame(panel)
    if not scrollFrame then return end
    local scrollChild = scrollFrame:GetScrollChild()
    local maximum = math.max(0,
        (scrollChild and scrollChild:GetHeight() or 0) - (scrollFrame:GetHeight() or 0))
    scrollFrame:SetVerticalScroll(math.max(0, math.min(maximum, tonumber(position) or 0)))
end

local function RestorePanelScrollAfterLayout(panel, position)
    RestorePanelScroll(panel, position)
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if panel and panel:IsShown() then RestorePanelScroll(panel, position) end
        end)
    end
end

iRC.RefreshOptionsIfShown = function()
    -- Homepage Save invokes several existing setters. Refresh once after the
    -- batch rather than rebuilding every settings page between those setters.
    if homepageDescriptionUI.saving then return end
    if settingsFrame:IsShown() then
        local panel = tabContents[selectedTab]
        local scrollFrame = GetPanelScrollFrame(panel)
        local position = scrollFrame and scrollFrame:GetVerticalScroll() or 0
        Refresh()
        RestorePanelScrollAfterLayout(panel, position)
        return
    end
    for _, panel in pairs(managementPanels or {}) do
        if panel:IsShown() then
            local scrollFrame = GetPanelScrollFrame(panel)
            local position = scrollFrame and scrollFrame:GetVerticalScroll() or 0
            Refresh()
            RestorePanelScrollAfterLayout(panel, position)
            return
        end
    end
end

managementPanels = {
    permissions = guildPermissionsContainer,
    notifications = guildNotificationsContainer,
    homepage = guildHomepageContainer,
    guildFound = guildFoundContainer,
}

function iRC:HideManagementPanels()
    for _, panel in pairs(managementPanels) do panel:Hide() end
end

function iRC:ShowManagementPanel(panelKey, parent)
    local panel = managementPanels[panelKey]
    if not panel or not parent then return false end
    if not self:GetConnection() or not self:HasAnyManagementPermission() then
        self:HideManagementPanels()
        return false
    end
    local preservePosition = panel:IsShown() and panel:GetParent() == parent
    local priorScrollFrame = GetPanelScrollFrame(panel)
    local priorPosition = preservePosition and priorScrollFrame and priorScrollFrame:GetVerticalScroll() or 0
    self:HideManagementPanels()
    Refresh()
    panel:SetParent(parent)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -8)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -8, 8)
    panel:SetFrameLevel(parent:GetFrameLevel() + 2)
    local scrollFrame = GetPanelScrollFrame(panel)
    local scrollChild = scrollFrame and scrollFrame.GetScrollChild and scrollFrame:GetScrollChild()
    if scrollChild then
        local function FitManagementContent(_, width)
            scrollChild:SetWidth(math.max(550, (tonumber(width) or panel:GetWidth()) - 30))
        end
        panel:SetScript("OnSizeChanged", FitManagementContent)
        FitManagementContent(panel, panel:GetWidth())
    end
    panel:Show()
    RestorePanelScrollAfterLayout(panel, priorPosition)
    return true
end

settingsFrame:SetScript("OnShow", Refresh)
ShowTab(2)
iRC.SettingsFrame = settingsFrame

local stubPanel = CreateFrame("Frame", "iRCOptionsPanel", UIParent)
stubPanel.name = iRC.DisplayName
local stubTitle = stubPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
stubTitle:SetPoint("TOPLEFT", 16, -16)
stubTitle:SetText(iRC.Colors.iRC .. iRC.DisplayName .. iRC.Colors.Reset .. " " .. iRC.Colors.Green .. "v" .. iRC:GetDisplayVersion() .. iRC.Colors.Reset)
local stubDescription = stubPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
stubDescription:SetPoint("TOPLEFT", stubTitle, "BOTTOMLEFT", 0, -10)
stubDescription:SetText("Open the full iRC settings panel.")
local stubButton = CreateFrame("Button", nil, stubPanel, "UIPanelButtonTemplate")
stubButton:SetSize(180, 28)
stubButton:SetPoint("TOPLEFT", stubDescription, "BOTTOMLEFT", 0, -15)
stubButton:SetText("Open settings")
stubButton:SetScript("OnClick", function() iRC:OpenOptions() end)
if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(stubPanel, iRC.DisplayName)
    Settings.RegisterAddOnCategory(category)
end

function iRC:OpenOptions()
    if not self:CanOpenPanel() then return false end
    if self.CloseWindowsExcept then
        self:CloseWindowsExcept(settingsFrame)
    end
    settingsFrame:Show()
    return true
end

function iRC:ToggleOptions()
    if settingsFrame:IsShown() then
        settingsFrame:Hide()
    else
        self:OpenOptions()
    end
end
