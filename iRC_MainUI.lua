local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local UI = {}
iRC.MainUI = UI
local expandedGuildCards = {}
local guildStatsFilter = "ALL"
local collapsedFactionSections = {}
local MEMBER_SEARCH_PRIORITY = { name = 1, profession = 2, recipe = 3 }

-- A Self-Found journey that transitions at the level cap is ultimately a
-- Guild-Found ruleset, so present and filter it consistently as Guild-Found.
local function isGuildFoundRules(rules)
    if not rules then return false end
    local progression = iRC:GetProgressionMode(rules)
    return progression == "GUILD_FOUND"
        or progression == "SELF_FOUND_OR_GUILD_FOUND"
        or (progression == "SELF_FOUND" and iRC:GetMaxLevelProgressionMode(rules) == "GUILD_FOUND")
end

local function getGuildCardTag(group)
    local rules = group and group.rulesKnown and group.rules
    if not rules then return nil end
    if rules.raceLock == true then return "Race-Locked", { 0.25, 0.85, 1 } end
    local progression = iRC:GetProgressionMode(rules)
    if isGuildFoundRules(rules) then
        return "Guild-Found", { 0.30, 1, 0.35 }
    end
    if progression == "SELF_FOUND" and iRC:GetMaxLevelProgressionMode(rules) == "SELF_FOUND" then
        return "Self-Found", { 1.00, 0.55, 0.55 }
    end
    local homepageTag = tostring(group.guildHomepageTag or "NORMAL")
    if homepageTag == "PVE" then return "PvE", { 0.38, 0.85, 0.45 } end
    if homepageTag == "PVP" then return "PvP", { 1.00, 0.38, 0.32 } end
    if homepageTag == "RP" then return "RP", { 0.72, 0.55, 1.00 } end
    return "Normal", { 0.72, 0.72, 0.72 }
end

local function getCurrentGuildStatsFilter()
    if not iRC:IsGuildConnectionActive() then return "ALL" end
    local rules = iRC:GetConnectionRules()
    if rules.raceLock == true then return "RACE_LOCKED" end
    local progression = iRC:GetProgressionMode(rules)
    if isGuildFoundRules(rules) then return "GUILD_FOUND" end
    if progression == "SELF_FOUND" and iRC:GetMaxLevelProgressionMode(rules) == "SELF_FOUND" then return "SELF_FOUND" end
    return "ALL"
end

local COLORS = {
    gold = iRC.ColorValues.Orange,
    green = iRC.ColorValues.Green,
    red = { 1, 0.32, 0.28 },
    gray = iRC.ColorValues.Gray,
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
local NO_DATA_ICON = "Interface\\Icons\\Achievement_General"

local function getGuildCardIcon(group)
    local rules = group and group.rulesKnown and group.rules
    if rules and rules.raceLock == true then return RACE_ICONS[group.race] or NO_DATA_ICON end
    local index = math.floor(tonumber(group and group.guildHomepageIcon) or 0)
    return iRC.GuildHomepageIcons[index] or NO_DATA_ICON
end

local RACE_COLORS = {
    HUMAN = { 0.82, 0.62, 0.25 }, DWARF = { 0.74, 0.43, 0.18 }, NIGHTELF = { 0.56, 0.30, 0.78 }, GNOME = { 0.35, 0.68, 0.95 }, DRAENEI = { 0.45, 0.46, 0.90 },
    ORC = { 0.62, 0.18, 0.14 }, SCOURGE = { 0.43, 0.63, 0.50 }, TAUREN = { 0.56, 0.32, 0.18 }, TROLL = { 0.12, 0.62, 0.88 }, BLOODELF = { 0.84, 0.22, 0.24 },
    Unknown = { 0.45, 0.45, 0.45 },
}

local RACE_LABELS = {
    HUMAN = "Human", DWARF = "Dwarf", NIGHTELF = "Night Elf", GNOME = "Gnome", DRAENEI = "Draenei",
    ORC = "Orc", SCOURGE = "Undead", TAUREN = "Tauren", TROLL = "Troll", BLOODELF = "Blood Elf",
}

local FACTION_STYLES = {
    Horde = { border = { 0.72, 0.18, 0.15, 1 }, background = { 0.13, 0.035, 0.03, 0.92 } },
    Alliance = { border = { 0.18, 0.42, 0.80, 1 }, background = { 0.025, 0.07, 0.16, 0.92 } },
    MyGuild = { border = { 0.92, 0.62, 0.12, 1 }, background = { 0.12, 0.075, 0.02, 0.92 } },
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

local function makeIRCActionButton(parent, width, height, text, destructive)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, height)
    createBackdrop(button, destructive and { 0.16, 0.035, 0.025, 0.98 } or { 0.08, 0.06, 0.035, 0.98 },
        destructive and { 0.72, 0.20, 0.12, 1 } or { 0.52, 0.38, 0.17, 1 })
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    button.text:SetPoint("CENTER", 0, 0)
    button.text:SetText(text)
    button.text:SetTextColor(destructive and 1 or COLORS.gold[1],
        destructive and 0.55 or COLORS.gold[2], destructive and 0.40 or COLORS.gold[3])
    button:SetFontString(button.text)
    button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.highlight:SetPoint("TOPLEFT", 3, -3)
    button.highlight:SetPoint("BOTTOMRIGHT", -3, 3)
    button.highlight:SetColorTexture(destructive and 1 or COLORS.gold[1],
        destructive and 0.24 or COLORS.gold[2], destructive and 0.16 or COLORS.gold[3], 0.15)
    return button
end

local function makeMemberRow(parent, index)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetHeight(44)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * 48))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -((index - 1) * 48))
    createBackdrop(row, { 0.10, 0.085, 0.07, 0.96 }, { 0.28, 0.25, 0.20, 1 })
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", 14, -6)
    row.name:SetWidth(220)
    row.name:SetJustifyH("LEFT")
    row.onlineTag = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.onlineTag:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    row.onlineTag:SetText("[Online]")
    row.onlineTag:SetTextColor(0.30, 1, 0.35)
    row.tag = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.tag:SetPoint("LEFT", row.onlineTag, "RIGHT", 6, 0)
    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.detail:SetPoint("RIGHT", row, "RIGHT", -14, 0)
    row.detail:SetJustifyH("LEFT")
    return row
end

local function setMemberRowDensity(row, compact)
    row:SetHeight(compact and 40 or 44)
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", 14, -6)
    row.detail:ClearAllPoints()
    row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.detail:SetPoint("RIGHT", row, "RIGHT", -14, 0)
end

local function resetInactiveMemberView(frame)
    if not frame then return end
    frame.inactiveMemberDays = 30
    frame.inactiveExcludedRank = nil
    if frame.inactiveThreshold and frame.inactiveThreshold.input then
        frame.inactiveThreshold.input:SetText("30")
        frame.inactiveThreshold.input:ClearFocus()
    end
    if frame.RefreshInactiveRankExclude then frame:RefreshInactiveRankExclude() end
    for _, row in ipairs(frame.memberRows or {}) do row:SetAlpha(1) end
end

local function makeGuildRuleRow(parent, index)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(44)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * 48))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -((index - 1) * 48))
    createBackdrop(row, { 0.075, 0.065, 0.05, 0.96 }, { 0.30, 0.26, 0.19, 1 })
    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetWidth(3)
    row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -5)
    row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 5)
    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.title:SetPoint("TOPLEFT", 15, -5)
    row.title:SetPoint("RIGHT", row, "RIGHT", -127, 0)
    row.title:SetJustifyH("LEFT")
    row.description = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.description:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -1)
    row.description:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -127, 4)
    row.description:SetJustifyH("LEFT")
    row.description:SetJustifyV("TOP")
    row.description:SetWordWrap(true)
    row.stateBackground = row:CreateTexture(nil, "ARTWORK")
    row.stateBackground:SetSize(102, 24)
    row.stateBackground:SetPoint("RIGHT", row, "RIGHT", -9, 0)
    row.state = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.state:SetPoint("CENTER", row.stateBackground, "CENTER", 0, 0)
    row.state:SetWidth(96)
    row.state:SetJustifyH("CENTER")
    row.dependencyVertical = row:CreateTexture(nil, "ARTWORK")
    row.dependencyVertical:SetColorTexture(0.72, 0.48, 0.18, 0.85)
    row.dependencyVertical:SetWidth(2)
    row.dependencyHorizontal = row:CreateTexture(nil, "ARTWORK")
    row.dependencyHorizontal:SetColorTexture(0.72, 0.48, 0.18, 0.85)
    row.dependencyHorizontal:SetHeight(2)
    row.dependencyVertical:Hide()
    row.dependencyHorizontal:Hide()
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    return row
end

local function makeRaceCard(parent)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetHeight(138)
    createBackdrop(card, { 0.045, 0.055, 0.075, 0.98 }, { 0.30, 0.31, 0.34, 1 })

    card.accent = card:CreateTexture(nil, "ARTWORK")
    card.accent:SetWidth(4)
    card.accent:SetPoint("TOPLEFT", 4, -5)
    card.accent:SetPoint("BOTTOMLEFT", 4, 5)

    card.iconFrame = CreateFrame("Frame", nil, card, "BackdropTemplate")
    card.iconFrame:SetSize(40, 40)
    card.iconFrame:SetPoint("TOPLEFT", 13, -9)
    createBackdrop(card.iconFrame, { 0.03, 0.03, 0.03, 1 }, { 0.58, 0.49, 0.25, 1 })
    card.icon = card.iconFrame:CreateTexture(nil, "ARTWORK")
    card.icon:SetPoint("CENTER")
    card.icon:SetSize(32, 32)

    card.race = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    card.race:SetPoint("TOPLEFT", card.iconFrame, "TOPRIGHT", 9, -1)
    card.race:SetTextColor(unpack(COLORS.gold))
    card.tag = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.tag:SetPoint("LEFT", card.race, "RIGHT", 9, 0)
    card.rank = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.rank:SetPoint("TOPRIGHT", -14, -16)
    card.rank:SetTextColor(unpack(COLORS.gold))
    card.freshness = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.freshness:SetPoint("TOPLEFT", card.iconFrame, "TOPRIGHT", 9, -23)
    card.freshness:SetPoint("RIGHT", card, "RIGHT", -14, 0)
    card.freshness:SetJustifyH("LEFT")
    card.guildLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.guildLabel:SetPoint("TOP", card, "TOP", -35, -43)
    card.guildLabel:SetText(iRC:Text("GUILD_STATS_RACE"))
    card.guildLabel:SetTextColor(unpack(COLORS.gold))
    card.guild = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.guild:SetPoint("LEFT", card.guildLabel, "RIGHT", 7, 0)
    card.guild:SetWidth(180)
    card.guild:SetJustifyH("LEFT")
    card.guildLabel:Hide()
    card.guild:Hide()

    card.averageLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.averageLabel:SetPoint("TOP", card, "TOP", -240, -48)
    card.averageLabel:SetWidth(145)
    card.averageLabel:SetText(iRC:Text("GUILD_STATS_ACTIVE_LEVEL_30"))
    card.membersLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.membersLabel:SetPoint("TOP", card, "TOP", -80, -48)
    card.membersLabel:SetWidth(145)
    card.membersLabel:SetText(iRC:Text("GUILD_STATS_ONLINE_PEAK"))
    card.totalLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.totalLabel:SetPoint("TOP", card, "TOP", 80, -48)
    card.totalLabel:SetWidth(145)
    card.totalLabel:SetText(iRC:Text("GUILD_STATS_ACTIVE_MEMBERS"))
    card.totalMembersLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.totalMembersLabel:SetPoint("TOP", card, "TOP", 240, -48)
    card.totalMembersLabel:SetWidth(145)
    card.totalMembersLabel:SetText(iRC:Text("GUILD_STATS_TOTAL_MEMBERS"))
    card.average = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.average:SetPoint("TOP", card.averageLabel, "BOTTOM", 0, -3)
    card.members = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.members:SetPoint("TOP", card.membersLabel, "BOTTOM", 0, -3)
    card.total = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.total:SetPoint("TOP", card.totalLabel, "BOTTOM", 0, -3)
    card.totalMembers = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.totalMembers:SetPoint("TOP", card.totalMembersLabel, "BOTTOM", 0, -3)

    card.classesTitle = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.classesTitle:SetPoint("TOP", card, "TOP", 0, -81)
    card.classesTitle:SetText(iRC:Text("GUILD_STATS_CLASS_BREAKDOWN"))
    card.classText = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.classText:SetPoint("TOPLEFT", 15, -93)
    card.classText:SetPoint("TOPRIGHT", -15, -93)
    card.classText:SetJustifyH("CENTER")
    card.classText:SetWordWrap(false)
    card.classBar = CreateFrame("Frame", nil, card, "BackdropTemplate")
    card.classBar:SetPoint("TOPLEFT", 16, -108)
    card.classBar:SetPoint("TOPRIGHT", -16, -108)
    card.classBar:SetHeight(12)
    createBackdrop(card.classBar, { 0.015, 0.015, 0.015, 1 }, { 0.48, 0.42, 0.30, 1 })
    card.classSegments = {}
    card.classLabels = {}
    card.expandHint = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.expandHint:SetPoint("TOPRIGHT", -16, -123)
    card.expandHint:SetWidth(630)
    card.expandHint:SetJustifyH("RIGHT")
    card.rulesSeparator = card:CreateTexture(nil, "ARTWORK")
    card.rulesSeparator:SetColorTexture(0.35, 0.29, 0.16, 0.8)
    card.rulesSeparator:SetPoint("TOPLEFT", 16, -139)
    card.rulesSeparator:SetPoint("TOPRIGHT", -16, -139)
    card.rulesSeparator:SetHeight(1)
    card.rulesTitle = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.rulesTitle:SetPoint("TOPLEFT", 16, -149)
    card.rulesTitle:SetText(iRC:Text("GUILD_STATS_GUILD_PROFILE"))
    card.rulesTitle:SetTextColor(unpack(COLORS.gold))
    card.rulesText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.rulesText:SetPoint("TOPLEFT", 20, -168)
    card.rulesText:SetPoint("TOPRIGHT", -20, -168)
    card.rulesText:SetJustifyH("LEFT")
    card.rulesText:SetJustifyV("TOP")
    card.rulesText:SetWordWrap(true)
    card.contactsLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.contactsLabel:SetPoint("TOPLEFT", 20, -182)
    card.contactsLabel:SetText(iRC:Text("GUILD_CONTACTS_LABEL") .. ":")
    card.contactsLabel:SetTextColor(unpack(COLORS.gold))
    card.contactButtons = {}
    card:EnableMouse(true)
    card:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" or not self.guildKey then return end
        expandedGuildCards[self.guildKey] = not expandedGuildCards[self.guildKey]
        if GameTooltip then GameTooltip:Hide() end
        if UI.frame and UI.frame.scroll then UI.preservedRaceScroll = UI.frame.scroll:GetVerticalScroll() end
        UI:Refresh()
    end)
    return card
end

local function makeFactionSection(parent, sectionKey, title)
    local style = FACTION_STYLES[sectionKey]
    local section = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    createBackdrop(section, style.background, style.border)
    section.header = CreateFrame("Button", nil, section)
    section.header:SetPoint("TOPLEFT", 1, -1)
    section.header:SetPoint("TOPRIGHT", -1, -1)
    section.header:SetHeight(34)
    section.header:RegisterForClicks("LeftButtonUp")
    section.title = section.header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    section.title:SetPoint("LEFT", 13, 0)
    section.title:SetText(title or sectionKey)
    section.title:SetTextColor(unpack(style.border))
    section.header:SetScript("OnClick", function()
        collapsedFactionSections[sectionKey] = not collapsedFactionSections[sectionKey]
        if UI.frame and UI.frame.scroll then UI.preservedRaceScroll = UI.frame.scroll:GetVerticalScroll() end
        UI:Refresh()
    end)
    section.header:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(iRC:Text(collapsedFactionSections[sectionKey] and "GUILD_STATS_EXPAND_FACTION" or "GUILD_STATS_COLLAPSE_FACTION", title or sectionKey))
        GameTooltip:Show()
    end)
    section.header:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return section
end

local function makeRacePodium(parent)
    local podium = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    createBackdrop(podium, { 0.075, 0.06, 0.04, 0.98 }, { 0.55, 0.41, 0.17, 1 })
    podium.title = podium:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    podium.title:SetPoint("TOP", 0, -7)
    podium.title:SetText(iRC:Text("GUILD_STATS_TOP_THREE"))
    podium.title:SetTextColor(unpack(COLORS.gold))
    podium.entries = {}

    for rank = 1, 3 do
        local entry = CreateFrame("Frame", nil, podium, "BackdropTemplate")
        createBackdrop(entry, { 0.045, 0.055, 0.075, 0.98 }, PODIUM_COLORS[rank])
        entry.icon = entry:CreateTexture(nil, "ARTWORK")
        entry.icon:SetSize(30, 30)
        entry.icon:SetPoint("LEFT", 8, 0)
        entry.rank = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        entry.rank:SetPoint("LEFT", entry.icon, "RIGHT", 7, 0)
        entry.rank:SetTextColor(unpack(PODIUM_COLORS[rank]))
        entry.race = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        entry.race:SetPoint("LEFT", entry.rank, "RIGHT", 5, 0)
        entry.race:SetPoint("RIGHT", entry, "RIGHT", -8, 0)
        entry.race:SetJustifyH("LEFT")
        entry.tag = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        entry.tag:SetPoint("TOPLEFT", entry.race, "BOTTOMLEFT", 0, -1)
        entry.tag:SetPoint("RIGHT", entry, "RIGHT", -8, 0)
        entry.tag:SetJustifyH("LEFT")
        entry.tag:Hide()
        podium.entries[rank] = entry
    end
    return podium
end

local MAIN_NAVIGATION = {
    { id = "Current Server", header = true },
    { id = "Race Overview", label = iRC:Text("GUILD_STATS_TITLE") },
    { id = "Current Guild", header = true },
    { id = "Guild Overview", label = "Guild Overview", child = true },
    { id = "Guild Rules", label = "Guild Rules", child = true },
    { id = "Guild Members", label = "Guild Members", child = true },
    { id = "Personal", header = true },
    { id = "Personal Settings", label = "Personal Settings", child = true },
    { id = "Management", header = true, managementHeader = true },
    { id = "Permission Management", label = "Permissions", child = true, guildMasterOnly = true, panelKey = "permissions", requiresConnection = true },
    { id = "Guild Log", label = "Guild Log", child = true, permission = "rosterHistory" },
    { id = "Inactive Member Management", label = "Inactive Members", child = true, permission = "memberRemoval", requiresGuild = true },
    { id = "Rank Management", label = "Rank Management", child = true, permission = "rankManagement", requiresGuild = true },
    { id = "Verification Management", label = iRC:Text("DASHBOARD_VERIFICATION_TITLE"), child = true, permission = "verification", dashboardTab = "Verification", requiresConnection = true },
    { id = "Incident Management", label = iRC:Text("INCIDENT_TAB"), grandchild = true, permission = "incidents", dashboardTab = "Incidents" },
    { id = "Notification Management", label = iRC:Text("GUILD_NOTIFICATIONS_TAB"), child = true, permission = "notifications", panelKey = "notifications", requiresConnection = true },
    { id = "Homepage Management", label = iRC:Text("GUILD_HOMEPAGE_TAB"), child = true, permission = "homepage", panelKey = "homepage", requiresConnection = true },
    { id = "Guild-Found Management", label = iRC:Text("GUILDFOUND_TOOLS_TAB"), child = true, permission = "tradeExceptions", panelKey = "guildFound", requiresGuildFound = true },
}

local DEFAULT_OPEN_LAST = "__LAST__"

local function getNavigationLabel(category)
    if category == DEFAULT_OPEN_LAST then return "Last viewed page" end
    for _, item in ipairs(MAIN_NAVIGATION) do
        if not item.header and item.id == category then return item.label end
    end
    return nil
end

local MANAGEMENT_PANEL_KEYS = {
    ["Permission Management"] = "permissions",
    ["Notification Management"] = "notifications",
    ["Homepage Management"] = "homepage",
    ["Guild-Found Management"] = "guildFound",
}

local DASHBOARD_PANEL_TABS = {
    ["Verification Management"] = "Verification",
    ["Incident Management"] = "Incidents",
}

local function currentServerNavigationName()
    if iRC:IsForeverClient() then
        return iRC.GameVersionName or "Forever"
    end
    local name = GetRealmName and GetRealmName()
    if not name or name == "" then return "Current Server" end
    return #name > 24 and (name:sub(1, 21) .. "...") or name
end

local function currentGuildNavigationName()
    local name = GetGuildInfo and GetGuildInfo("player")
    if not name or name == "" then return "Current Guild" end
    return #name > 24 and (name:sub(1, 21) .. "...") or name
end

local function getProfile(frame)
    if not frame.subjectName or iRC:NormalizeName(frame.subjectName) == iRC:NormalizeName(iRC:GetPlayerName()) then
        return iRC:GetLocalProfile()
    end
    local connection = iRC:GetConnection()
    local profile = connection and connection.members[iRC:NormalizeName(frame.subjectName)]
    return profile
end

local function getNativeGuildRank()
    local ownRank
    if GetGuildInfo then
        local _, _, guildInfoRank = GetGuildInfo("player")
        ownRank = guildInfoRank
    end
    if type(ownRank) ~= "number" then
        ownRank = iRC:GetGuildMemberRankIndex(iRC:GetPlayerName())
    end
    return ownRank
end

local function cleanSystemMessage(message)
    return tostring(message or "")
        :gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|H.-|h(.-)|h", "%1"):match("^%s*(.-)%s*$")
end

local function isNativePermissionDeniedMessage(message)
    local plain = cleanSystemMessage(message):lower()
    local localized = tostring(_G.ERR_GUILD_PERMISSIONS or ""):lower():match("^%s*(.-)%s*$")
    if localized ~= "" and plain == localized then return true end
    return plain:find("you do not have permission", 1, true) ~= nil
        or plain:find("you don't have permission", 1, true) ~= nil
        or plain:find("you dont have permission", 1, true) ~= nil
end

local function getGuildRankCount()
    local count = GuildControlGetNumRanks and tonumber(GuildControlGetNumRanks()) or 0
    if count and count > 0 then return math.floor(count) end
    local highest = 0
    for _, member in ipairs(iRC:GetGuildRosterSnapshot()) do
        if type(member.rankIndex) == "number" then highest = math.max(highest, member.rankIndex) end
    end
    return highest + 1
end

local function isRankActionEligible(member, action, testAdminPreview)
    if not member or type(member.rankIndex) ~= "number"
        or iRC:NormalizeName(member.name) == iRC:NormalizeName(iRC:GetPlayerName()) then return false end
    if testAdminPreview == true and iRC:IsTestAdmin() then
        return action == "PROMOTE" and member.rankIndex > 0
            or action == "DEMOTE" and member.rankIndex < getGuildRankCount() - 1
    end
    local ownRank = getNativeGuildRank()
    if type(ownRank) ~= "number" or member.rankIndex <= ownRank then return false end
    if action == "PROMOTE" then return member.rankIndex > ownRank + 1 end
    if action == "DEMOTE" then return member.rankIndex < getGuildRankCount() - 1 end
    return false
end

local function getRankActionMembers(rankIndex, action, testAdminPreview)
    local members = {}
    for _, member in ipairs(iRC:GetGuildRosterSnapshot()) do
        if member.rankIndex == rankIndex and isRankActionEligible(member, action, testAdminPreview) then
            members[#members + 1] = member
        end
    end
    table.sort(members, function(a, b) return iRC:NormalizeName(a.name) < iRC:NormalizeName(b.name) end)
    return members
end

local function getEligibleInactiveMembers(threshold, testAdminPreview, excludedRank)
    threshold = math.max(0, math.min(9999, math.floor(tonumber(threshold) or 30)))
    excludedRank = type(excludedRank) == "number" and excludedRank or nil
    local members = {}
    local selfKey = iRC:NormalizeName(iRC:GetPlayerName())
    local ownRank = getNativeGuildRank()
    local preview = testAdminPreview == true and iRC:IsTestAdmin()
    if not preview and type(ownRank) ~= "number" then return members end
    for _, member in ipairs(iRC:GetGuildRosterSnapshot()) do
        if not member.online and tonumber(member.lastOnlineDays) and member.lastOnlineDays >= threshold
            and iRC:NormalizeName(member.name) ~= selfKey
            and not (excludedRank and type(member.rankIndex) == "number" and member.rankIndex <= excludedRank)
            and (preview or type(member.rankIndex) == "number" and member.rankIndex > ownRank) then
            members[#members + 1] = member
        end
    end
    table.sort(members, function(a, b)
        if a.lastOnlineDays ~= b.lastOnlineDays then return a.lastOnlineDays > b.lastOnlineDays end
        return iRC:NormalizeName(a.name) < iRC:NormalizeName(b.name)
    end)
    return members
end

local function setTabAppearance(button, active)
    if button.unavailable then
        button:SetBackdropColor(0.045, 0.045, 0.045, 0.78)
        button:SetBackdropBorderColor(0.18, 0.18, 0.18, 0.72)
        button.label:SetTextColor(0.42, 0.42, 0.42)
        return
    end
    button:SetBackdropColor(active and 0.24 or 0.08, active and 0.16 or 0.065, active and 0.04 or 0.05, 0.96)
    button:SetBackdropBorderColor(active and 1 or 0.34, active and 0.72 or 0.28, active and 0.18 or 0.20, 1)
    button.label:SetTextColor(unpack(active and COLORS.gold or COLORS.parchment))
end

local function getNavigationUnavailableReason(item)
    if item.requiresConnection and not iRC:IsGuildConnectionActive() then
        return iRC:Text("MANAGEMENT_REQUIRES_CONNECTION")
    end
    if item.requiresGuildFound then
        if not iRC:IsGuildConnectionActive() then return iRC:Text("MANAGEMENT_REQUIRES_CONNECTION") end
        local rules = iRC:GetConnectionRules()
        if not rules or (rules.guildFoundOnly ~= true and rules.level60GuildFound ~= true) then
            return iRC:Text("MANAGEMENT_REQUIRES_GUILD_FOUND")
        end
    end
end

local applyMemberSearch

local function updateMemberSuggestions(frame)
    local search = frame.memberProfessionSearch
    if not search then return end
    local query = search.edit:GetText():lower():gsub("^%s+", ""):gsub("%s+$", "")
    local matches = {}
    if query ~= "" then
        for _, entry in ipairs(frame.memberSearchIndex or {}) do
            local position = entry.lower:find(query, 1, true)
            if position then
                matches[#matches + 1] = { entry = entry, starts = position == 1 }
            end
        end
        table.sort(matches, function(a, b)
            if a.entry.kind ~= b.entry.kind then
                return (MEMBER_SEARCH_PRIORITY[a.entry.kind] or 9) < (MEMBER_SEARCH_PRIORITY[b.entry.kind] or 9)
            end
            if a.starts ~= b.starts then return a.starts end
            return a.entry.lower < b.entry.lower
        end)
    end
    for index, button in ipairs(search.buttons) do
        local match = matches[index]
        button.entry = match and match.entry or nil
        button:SetShown(match ~= nil)
        if match then button.text:SetText(match.entry.label) end
    end
    search.suggestions:SetShown(query ~= "" and matches[1] ~= nil and search.edit:HasFocus())
end

local function createMemberProfessionSearch(main, frame)
    local search = CreateFrame("Frame", nil, main)
    search:SetSize(355, 28)
    search:SetPoint("TOPRIGHT", main, "TOPRIGHT", -18, -11)
    search.edit = CreateFrame("EditBox", nil, search, "InputBoxTemplate")
    search.edit:SetSize(342, 22)
    search.edit:SetPoint("RIGHT", search, "RIGHT", 0, 0)
    search.edit:SetAutoFocus(false)
    search.edit:SetMaxLetters(80)
    search.edit:SetTextInsets(5, 5, 0, 0)
    search.edit:SetText("")
    search.hint = search:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    search.hint:SetPoint("LEFT", search.edit, "LEFT", 6, 0)
    search.hint:SetText("Search names, linked alts, professions & recipes...")
    search.hint:SetTextColor(0.76, 0.72, 0.64)
    search.suggestions = CreateFrame("Frame", nil, search, "BackdropTemplate")
    search.suggestions:SetSize(355, 128)
    search.suggestions:SetPoint("TOPLEFT", search.edit, "BOTTOMLEFT", 0, -2)
    search.suggestions:SetFrameStrata("DIALOG")
    search.suggestions:SetFrameLevel(main:GetFrameLevel() + 20)
    search.suggestions:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    search.suggestions:SetBackdropColor(0.03, 0.03, 0.03, 0.98)
    search.suggestions:SetBackdropBorderColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 0.85)
    search.buttons = {}
    for index = 1, 5 do
        local button = CreateFrame("Button", nil, search.suggestions)
        button:SetSize(337, 23)
        button:SetPoint("TOPLEFT", search.suggestions, "TOPLEFT", 7, -6 - (index - 1) * 23)
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        button.text:SetPoint("LEFT", button, "LEFT", 7, 0)
        button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
        button.highlight:SetAllPoints()
        button.highlight:SetColorTexture(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 0.18)
        button:SetScript("OnClick", function(self)
            if not self.entry then return end
            frame.memberSearchSelection = self.entry
            search.edit.settingSelection = true
            search.edit:SetText(self.entry.label)
            search.edit.settingSelection = nil
            search.edit:ClearFocus()
            search.suggestions:Hide()
            applyMemberSearch(frame)
        end)
        search.buttons[index] = button
    end
    search.edit:SetScript("OnTextChanged", function(self)
        search.hint:SetShown(self:GetText() == "")
        if self.settingSelection then return end
        frame.memberSearchSelection = nil
        updateMemberSuggestions(frame)
        if frame.allMemberData then applyMemberSearch(frame) end
    end)
    search.edit:SetScript("OnEditFocusGained", function() updateMemberSuggestions(frame) end)
    search.edit:SetScript("OnEditFocusLost", function(self)
        C_Timer.After(0, function()
            if not self:HasFocus() and not iRC:IsMouseOverFrame(search.suggestions) then
                search.suggestions:Hide()
            end
        end)
    end)
    search.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); search.suggestions:Hide() end)
    search.edit:SetScript("OnEnterPressed", function(self)
        local first = search.buttons[1]
        if first.entry and search.suggestions:IsShown() then first:Click() else self:ClearFocus() end
    end)
    search:Hide()
    search.suggestions:Hide()
    return search
end

function UI:Create()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "iRCMainFrame", UIParent, "BackdropTemplate")
    local settings = iRC:GetSettings()
    frame:SetSize(980, 650)
    frame:SetScale(settings.mainWindowScale or 1)
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

    local resize = CreateFrame("Button", nil, frame)
    resize:SetSize(20, 20); resize:SetPoint("BOTTOMRIGHT", -3, 3)
    resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resize:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resize:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local x, y = GetCursorPosition()
        self.dragging, self.startX, self.startY, self.startScale = true, x, y, frame:GetScale()
    end)
    resize:SetScript("OnUpdate", function(self)
        if not self.dragging then return end
        local x, y = GetCursorPosition()
        local delta = ((x - self.startX) - (y - self.startY)) / (2 * (UIParent:GetEffectiveScale() or 1))
        frame:SetScale(math.max(0.6, math.min(2.0, self.startScale + delta / 815)))
    end)
    resize:SetScript("OnMouseUp", function(self)
        self.dragging = false
        settings.mainWindowScale = math.floor(frame:GetScale() * 20 + 0.5) / 20
        frame:SetScale(settings.mainWindowScale)
    end)
    frame.resizeHandle = resize
    iRC:EnableIdleWindowFade(frame)

    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 4, 4)
    -- UIPanelCloseButton's default handler routes through Blizzard's panel
    -- manager, which can refuse a close while in combat. This is a normal
    -- addon frame, so hiding it directly is safe in and out of combat.
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    local disableConfirm = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    disableConfirm:SetSize(510, 190)
    disableConfirm:SetPoint("CENTER", frame, "CENTER", 0, 20)
    disableConfirm:SetFrameStrata("FULLSCREEN_DIALOG")
    disableConfirm:SetToplevel(true)
    disableConfirm:EnableMouse(true)
    createBackdrop(disableConfirm, { 0.025, 0.022, 0.018, 1 }, { 0.72, 0.30, 0.16, 1 })
    disableConfirm.title = disableConfirm:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    disableConfirm.title:SetPoint("TOPLEFT", 22, -20)
    disableConfirm.title:SetText(iRC:Text("GUILD_CONNECTION_DISABLE_CONFIRM_TITLE"))
    disableConfirm.title:SetTextColor(unpack(COLORS.gold))
    disableConfirm.body = disableConfirm:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    disableConfirm.body:SetPoint("TOPLEFT", disableConfirm.title, "BOTTOMLEFT", 0, -14)
    disableConfirm.body:SetPoint("TOPRIGHT", disableConfirm, "TOPRIGHT", -22, -52)
    disableConfirm.body:SetJustifyH("LEFT")
    disableConfirm.body:SetJustifyV("TOP")
    disableConfirm.body:SetWordWrap(true)
    disableConfirm.body:SetText(iRC:Text("GUILD_CONNECTION_DISABLE_CONFIRM"))
    local function makeConfirmButton(text, width)
        local button = CreateFrame("Button", nil, disableConfirm, "BackdropTemplate")
        button:SetSize(width, 28)
        createBackdrop(button, { 0.08, 0.06, 0.04, 1 }, { 0.48, 0.35, 0.16, 1 })
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        button.text:SetPoint("CENTER")
        button.text:SetText(text)
        button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
        button.highlight:SetAllPoints()
        button.highlight:SetColorTexture(1, 0.72, 0.22, 0.12)
        return button
    end
    disableConfirm.cancel = makeConfirmButton(iRC:Text("GUILD_CONNECTION_KEEP_ENABLED"), 130)
    disableConfirm.cancel:SetPoint("BOTTOMRIGHT", disableConfirm, "BOTTOMRIGHT", -22, 18)
    disableConfirm.cancel:SetScript("OnClick", function() disableConfirm:Hide() end)
    disableConfirm.accept = makeConfirmButton(iRC:Text("GUILD_CONNECTION_DISABLE"), 130)
    disableConfirm.accept:SetPoint("RIGHT", disableConfirm.cancel, "LEFT", -10, 0)
    disableConfirm.accept:SetBackdropColor(0.20, 0.035, 0.025, 1)
    disableConfirm.accept:SetBackdropBorderColor(0.85, 0.20, 0.12, 1)
    disableConfirm.accept:SetScript("OnClick", function()
        disableConfirm:Hide()
        if iRC:SetGuildConnectionActive(false) ~= false then UI:Refresh() end
    end)
    disableConfirm:Hide()
    frame.disableConfirm = disableConfirm

    local removeMemberConfirm = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    removeMemberConfirm:SetSize(510, 205)
    removeMemberConfirm:SetPoint("CENTER", frame, "CENTER", 0, 20)
    removeMemberConfirm:SetFrameStrata("FULLSCREEN_DIALOG")
    removeMemberConfirm:SetToplevel(true)
    removeMemberConfirm:EnableMouse(true)
    createBackdrop(removeMemberConfirm, { 0.025, 0.022, 0.018, 1 }, { 0.72, 0.30, 0.16, 1 })
    removeMemberConfirm.title = removeMemberConfirm:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    removeMemberConfirm.title:SetPoint("TOPLEFT", 22, -20)
    removeMemberConfirm.title:SetText("Remove inactive guild member?")
    removeMemberConfirm.title:SetTextColor(unpack(COLORS.gold))
    removeMemberConfirm.body = removeMemberConfirm:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    removeMemberConfirm.body:SetPoint("TOPLEFT", removeMemberConfirm.title, "BOTTOMLEFT", 0, -14)
    removeMemberConfirm.body:SetPoint("TOPRIGHT", removeMemberConfirm, "TOPRIGHT", -22, -52)
    removeMemberConfirm.body:SetJustifyH("LEFT")
    removeMemberConfirm.body:SetJustifyV("TOP")
    removeMemberConfirm.body:SetWordWrap(true)
    local function makeRemoveConfirmButton(text, width)
        local button = CreateFrame("Button", nil, removeMemberConfirm, "BackdropTemplate")
        button:SetSize(width, 28)
        createBackdrop(button, { 0.08, 0.06, 0.04, 1 }, { 0.48, 0.35, 0.16, 1 })
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        button.text:SetPoint("CENTER")
        button.text:SetText(text)
        button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
        button.highlight:SetAllPoints()
        button.highlight:SetColorTexture(1, 0.72, 0.22, 0.12)
        return button
    end
    removeMemberConfirm.cancel = makeRemoveConfirmButton("Cancel", 120)
    removeMemberConfirm.cancel:SetPoint("BOTTOMRIGHT", removeMemberConfirm, "BOTTOMRIGHT", -22, 18)
    removeMemberConfirm.cancel:SetScript("OnClick", function()
        removeMemberConfirm.rankAction = nil
        removeMemberConfirm.sourceRank = nil
        removeMemberConfirm.targetRank = nil
        removeMemberConfirm.removeAll = nil
        removeMemberConfirm.testPreview = nil
        removeMemberConfirm:Hide()
    end)
    removeMemberConfirm.accept = makeRemoveConfirmButton("Remove member", 190)
    removeMemberConfirm.accept:SetPoint("RIGHT", removeMemberConfirm.cancel, "LEFT", -10, 0)
    removeMemberConfirm.accept:SetBackdropColor(0.20, 0.035, 0.025, 1)
    removeMemberConfirm.accept:SetBackdropBorderColor(0.85, 0.20, 0.12, 1)

    removeMemberConfirm.rankTargetLabel = removeMemberConfirm:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    removeMemberConfirm.rankTargetLabel:SetPoint("TOPLEFT", removeMemberConfirm, "TOPLEFT", 22, -142)
    removeMemberConfirm.rankTargetLabel:SetText("Change to")
    removeMemberConfirm.rankTargetDropdown = CreateFrame("Button", nil, removeMemberConfirm, "BackdropTemplate")
    local rankTargetDropdown = removeMemberConfirm.rankTargetDropdown
    rankTargetDropdown:SetSize(300, 26)
    rankTargetDropdown:SetPoint("LEFT", removeMemberConfirm.rankTargetLabel, "RIGHT", 14, 0)
    createBackdrop(rankTargetDropdown, { 0.055, 0.045, 0.032, 0.99 }, { 0.46, 0.35, 0.18, 1 })
    rankTargetDropdown.text = rankTargetDropdown:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    rankTargetDropdown.text:SetPoint("LEFT", 10, 0)
    rankTargetDropdown.text:SetPoint("RIGHT", -30, 0)
    rankTargetDropdown.text:SetJustifyH("LEFT")
    rankTargetDropdown.arrow = rankTargetDropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rankTargetDropdown.arrow:SetPoint("RIGHT", -10, 0)
    rankTargetDropdown.arrow:SetText("v")
    rankTargetDropdown:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    rankTargetDropdown.menu = CreateFrame("Frame", nil, rankTargetDropdown, "BackdropTemplate")
    rankTargetDropdown.menu:SetPoint("TOPLEFT", rankTargetDropdown, "BOTTOMLEFT", 0, -2)
    rankTargetDropdown.menu:SetPoint("TOPRIGHT", rankTargetDropdown, "BOTTOMRIGHT", 0, -2)
    rankTargetDropdown.menu:SetHeight(12)
    rankTargetDropdown.menu:SetFrameStrata("FULLSCREEN_DIALOG")
    rankTargetDropdown.menu:SetFrameLevel(removeMemberConfirm:GetFrameLevel() + 30)
    rankTargetDropdown.menu:SetClampedToScreen(true)
    rankTargetDropdown.menu:SetToplevel(true)
    rankTargetDropdown.menu:EnableMouse(true)
    rankTargetDropdown.menu:SetScript("OnMouseDown", function() end)
    createBackdrop(rankTargetDropdown.menu, { 0.025, 0.022, 0.018, 0.995 }, { 0.72, 0.45, 0.16, 1 })
    rankTargetDropdown.menu.buttons = {}
    rankTargetDropdown.menu:Hide()

    function rankTargetDropdown:Refresh(options)
        options = options or {}
        self.menu:SetHeight(math.max(12, #options * 28 + 8))
        for index, option in ipairs(options) do
            local button = self.menu.buttons[index]
            if not button then
                button = CreateFrame("Button", nil, self.menu, "BackdropTemplate")
                button:SetHeight(25)
                button:SetPoint("TOPLEFT", self.menu, "TOPLEFT", 5, -5 - (index - 1) * 28)
                button:SetPoint("TOPRIGHT", self.menu, "TOPRIGHT", -5, -5 - (index - 1) * 28)
                createBackdrop(button, { 0.06, 0.05, 0.038, 0.98 }, { 0.28, 0.23, 0.16, 0.9 })
                button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                button.text:SetPoint("LEFT", 9, 0)
                button.text:SetPoint("RIGHT", -9, 0)
                button.text:SetJustifyH("LEFT")
                button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                self.menu.buttons[index] = button
            end
            button.rankIndex, button.rankLabel = option.index, option.label
            button.text:SetText(option.label)
            local selected = removeMemberConfirm.targetRank == option.index
            button:SetBackdropColor(selected and 0.19 or 0.06, selected and 0.11 or 0.05,
                selected and 0.035 or 0.038, 0.98)
            button:SetBackdropBorderColor(selected and COLORS.gold[1] or 0.28,
                selected and COLORS.gold[2] or 0.23, selected and COLORS.gold[3] or 0.16, 1)
            button:SetScript("OnClick", function(self)
                removeMemberConfirm.targetRank = self.rankIndex
                rankTargetDropdown.text:SetText(self.rankLabel)
                rankTargetDropdown.menu:Hide()
                rankTargetDropdown:Refresh(removeMemberConfirm.rankTargetOptions)
            end)
            button:Show()
            if selected then self.text:SetText(option.label) end
        end
        for index = #options + 1, #self.menu.buttons do self.menu.buttons[index]:Hide() end
    end
    rankTargetDropdown:SetScript("OnClick", function(self)
        self.menu:SetShown(not self.menu:IsShown())
        if self.menu:IsShown() then self.menu:Raise() end
    end)
    function removeMemberConfirm:SetRankTargets(sourceRank, action, testPreview)
        local minimumRank, maximumRank = 0, getGuildRankCount() - 1
        if action == "PROMOTE" and not testPreview then
            local ownRank = getNativeGuildRank()
            minimumRank = type(ownRank) == "number" and ownRank + 1 or sourceRank - 1
        end
        local options = {}
        for _, rank in ipairs(iRC:GetGuildRankOptions()) do
            local validTarget = type(rank.index) == "number" and (action == "PROMOTE"
                and rank.index < sourceRank and rank.index >= minimumRank
                or action == "DEMOTE" and rank.index > sourceRank and rank.index <= maximumRank)
            if validTarget then
                options[#options + 1] = {
                    index = rank.index,
                    label = tostring(rank.name or ("Rank " .. rank.index)) .. " (Rank " .. rank.index .. ")",
                }
            end
        end
        self.rankTargetOptions = options
        self.targetRank = action == "PROMOTE" and sourceRank - 1 or sourceRank + 1
        self.rankTargetLabel:SetText(action == "PROMOTE" and "Promote to" or "Demote to")
        rankTargetDropdown:Refresh(options)
    end
    removeMemberConfirm.rankTargetLabel:Hide()
    rankTargetDropdown:Hide()

    removeMemberConfirm.bulkList = CreateFrame("Frame", nil, removeMemberConfirm, "BackdropTemplate")
    removeMemberConfirm.bulkList:SetPoint("TOPLEFT", removeMemberConfirm, "TOPLEFT", 22, -157)
    removeMemberConfirm.bulkList:SetPoint("BOTTOMRIGHT", removeMemberConfirm, "BOTTOMRIGHT", -22, 58)
    createBackdrop(removeMemberConfirm.bulkList, { 0.04, 0.032, 0.025, 0.98 }, { 0.42, 0.31, 0.15, 0.95 })
    local bulkScroll = CreateFrame("ScrollFrame", nil, removeMemberConfirm.bulkList, "UIPanelScrollFrameTemplate")
    iRC:StyleScrollFrame(bulkScroll)
    bulkScroll:SetPoint("TOPLEFT", removeMemberConfirm.bulkList, "TOPLEFT", 7, -7)
    bulkScroll:SetPoint("BOTTOMRIGHT", removeMemberConfirm.bulkList, "BOTTOMRIGHT", -28, 7)
    local bulkChild = CreateFrame("Frame", nil, bulkScroll)
    bulkChild:SetSize(492, 1)
    bulkScroll:SetScrollChild(bulkChild)
    removeMemberConfirm.bulkRows = {}
    local function refreshBulkSelection()
        local selected = 0
        for _, candidate in ipairs(removeMemberConfirm.bulkCandidates or {}) do
            if candidate.selected then selected = selected + 1 end
        end
        if removeMemberConfirm.rankAction then
            removeMemberConfirm.accept.text:SetText((removeMemberConfirm.rankAction == "PROMOTE" and "Promote" or "Demote")
                .. " selected (" .. selected .. ")")
        else
            removeMemberConfirm.accept.text:SetText(iRC:Text("INACTIVE_MEMBERS_REMOVE_SELECTED", selected))
        end
        removeMemberConfirm.accept:SetEnabled(selected > 0)
        removeMemberConfirm.accept:SetAlpha(selected > 0 and 1 or 0.42)
    end
    local function setBulkCandidates(candidates)
        removeMemberConfirm.bulkCandidates = {}
        for index, member in ipairs(candidates or {}) do
            local candidate = {
                name = member.name,
                lastOnlineDays = tonumber(member.lastOnlineDays) or 0,
                rankName = member.rankName,
                rankIndex = member.rankIndex,
                detail = member.detail,
                selected = true,
            }
            removeMemberConfirm.bulkCandidates[index] = candidate
            local row = removeMemberConfirm.bulkRows[index]
            if not row then
                row = CreateFrame("Button", nil, bulkChild, "BackdropTemplate")
                row:SetHeight(34)
                createBackdrop(row, { 0.075, 0.06, 0.04, 0.96 }, { 0.27, 0.22, 0.13, 0.9 })
                row.check = CreateFrame("Frame", nil, row, "BackdropTemplate")
                row.check:SetSize(20, 20)
                row.check:SetPoint("LEFT", row, "LEFT", 8, 0)
                createBackdrop(row.check, { 0.035, 0.03, 0.02, 1 }, { 0.68, 0.46, 0.16, 1 })
                row.mark = row.check:CreateTexture(nil, "OVERLAY")
                row.mark:SetSize(24, 24)
                row.mark:SetPoint("CENTER", 0, 0)
                row.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
                row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                row.name:SetPoint("LEFT", row.check, "RIGHT", 10, 0)
                row.name:SetWidth(220)
                row.name:SetJustifyH("LEFT")
                row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                row.detail:SetPoint("RIGHT", row, "RIGHT", -10, 0)
                row.detail:SetWidth(210)
                row.detail:SetJustifyH("RIGHT")
                row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
                row.highlight:SetPoint("TOPLEFT", 3, -3)
                row.highlight:SetPoint("BOTTOMRIGHT", -3, 3)
                row.highlight:SetColorTexture(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 0.12)
                row:SetScript("OnClick", function(self)
                    if not self.candidate then return end
                    self.candidate.selected = not self.candidate.selected
                    self.mark:SetShown(self.candidate.selected)
                    self:SetAlpha(self.candidate.selected and 1 or 0.52)
                    refreshBulkSelection()
                end)
                removeMemberConfirm.bulkRows[index] = row
            end
            row.candidate = candidate
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", bulkChild, "TOPLEFT", 0, -((index - 1) * 36))
            row:SetPoint("TOPRIGHT", bulkChild, "TOPRIGHT", 0, -((index - 1) * 36))
            row.name:SetText(iRC:FormatPlayerName(candidate.name))
            row.detail:SetText(candidate.detail or (math.floor(candidate.lastOnlineDays + 0.5) .. " days · "
                .. tostring(candidate.rankName or "Unknown rank")))
            row.mark:Show()
            row:SetAlpha(1)
            row:Show()
        end
        for index = #(candidates or {}) + 1, #removeMemberConfirm.bulkRows do
            removeMemberConfirm.bulkRows[index]:Hide()
        end
        bulkChild:SetHeight(math.max(1, #(candidates or {}) * 36))
        bulkScroll:SetVerticalScroll(0)
        refreshBulkSelection()
    end
    removeMemberConfirm.setBulkCandidates = setBulkCandidates
    function removeMemberConfirm:SetBulkLayout(showPromotionTarget)
        self:SetSize(570, showPromotionTarget and 530 or 490)
        self.bulkList:ClearAllPoints()
        self.bulkList:SetPoint("TOPLEFT", self, "TOPLEFT", 22, showPromotionTarget and -185 or -157)
        self.bulkList:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -22, 58)
        self.rankTargetLabel:SetShown(showPromotionTarget == true)
        self.rankTargetDropdown:SetShown(showPromotionTarget == true)
        if not showPromotionTarget then
            self.rankTargetDropdown.menu:Hide()
            self.targetRank, self.rankTargetOptions = nil, nil
        end
    end
    removeMemberConfirm.bulkList:Hide()

    local function addQueueMemberList(queue)
        queue:SetSize(590, 420)
        queue.batchList = CreateFrame("Frame", nil, queue, "BackdropTemplate")
        queue.batchList:SetPoint("TOPLEFT", queue, "TOPLEFT", 22, -122)
        queue.batchList:SetPoint("BOTTOMRIGHT", queue, "BOTTOMRIGHT", -22, 62)
        queue.batchList:EnableMouse(true)
        createBackdrop(queue.batchList, { 0.04, 0.032, 0.025, 0.99 }, { 0.42, 0.31, 0.15, 0.95 })
        queue.batchList.title = queue.batchList:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        queue.batchList.title:SetPoint("TOPLEFT", queue.batchList, "TOPLEFT", 11, -9)
        queue.batchList.title:SetTextColor(unpack(COLORS.gold))

        local scroll = CreateFrame("ScrollFrame", nil, queue.batchList, "UIPanelScrollFrameTemplate")
        iRC:StyleScrollFrame(scroll)
        scroll:SetPoint("TOPLEFT", queue.batchList, "TOPLEFT", 8, -29)
        scroll:SetPoint("BOTTOMRIGHT", queue.batchList, "BOTTOMRIGHT", -28, 7)
        local child = CreateFrame("Frame", nil, scroll)
        child:SetSize(500, 1)
        scroll:SetScrollChild(child)
        queue.batchList.rows = {}

        function queue:SetBatchMembers(names)
            names = names or {}
            self.batchList.title:SetText("Members in this batch (" .. #names .. ")")
            for index, name in ipairs(names) do
                local row = self.batchList.rows[index]
                if not row then
                    row = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    row:SetPoint("TOPLEFT", child, "TOPLEFT", 7, -((index - 1) * 22))
                    row:SetPoint("RIGHT", child, "RIGHT", -7, 0)
                    row:SetJustifyH("LEFT")
                    self.batchList.rows[index] = row
                end
                row:SetText(tostring(index) .. ".  " .. iRC:FormatPlayerName(name))
                row:Show()
            end
            for index = #names + 1, #self.batchList.rows do self.batchList.rows[index]:Hide() end
            child:SetHeight(math.max(1, #names * 22))
            scroll:SetVerticalScroll(0)
        end
    end

    local removalQueue = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    removalQueue:SetSize(590, 420)
    removalQueue:SetPoint("CENTER", frame, "CENTER", 0, 20)
    removalQueue:SetFrameStrata("FULLSCREEN_DIALOG")
    removalQueue:SetToplevel(true)
    removalQueue:EnableMouse(true)
    createBackdrop(removalQueue, { 0.025, 0.022, 0.018, 1 }, { 0.72, 0.30, 0.16, 1 })
    removalQueue.title = removalQueue:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    removalQueue.title:SetPoint("TOPLEFT", 22, -20)
    removalQueue.title:SetText(iRC:Text("INACTIVE_MEMBERS_QUEUE_TITLE"))
    removalQueue.title:SetTextColor(unpack(COLORS.gold))
    removalQueue.progress = removalQueue:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    removalQueue.progress:SetPoint("TOPRIGHT", -22, -23)
    removalQueue.body = removalQueue:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    removalQueue.body:SetPoint("TOPLEFT", removalQueue.title, "BOTTOMLEFT", 0, -20)
    removalQueue.body:SetPoint("TOPRIGHT", removalQueue, "TOPRIGHT", -22, -58)
    removalQueue.body:SetJustifyH("LEFT")
    removalQueue.body:SetJustifyV("TOP")
    removalQueue.body:SetWordWrap(true)

    local function makeQueueButton(text, width, secure)
        local template = secure and "SecureActionButtonTemplate,BackdropTemplate" or "BackdropTemplate"
        local button = CreateFrame("Button", nil, removalQueue, template)
        button:SetSize(width, 30)
        createBackdrop(button, { 0.08, 0.06, 0.04, 1 }, { 0.48, 0.35, 0.16, 1 })
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        button.text:SetPoint("CENTER")
        button.text:SetText(text)
        button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
        button.highlight:SetAllPoints()
        button.highlight:SetColorTexture(1, 0.72, 0.22, 0.12)
        return button
    end

    removalQueue.cancel = makeQueueButton(iRC:Text("INACTIVE_MEMBERS_QUEUE_CANCEL"), 140, false)
    removalQueue.cancel:SetPoint("BOTTOMRIGHT", removalQueue, "BOTTOMRIGHT", -22, 18)
    removalQueue.skip = makeQueueButton(iRC:Text("INACTIVE_MEMBERS_QUEUE_SKIP"), 90, false)
    removalQueue.skip:SetPoint("RIGHT", removalQueue.cancel, "LEFT", -10, 0)
    removalQueue.remove = makeQueueButton("Remove member", 245, true)
    removalQueue.remove:SetPoint("RIGHT", removalQueue.skip, "LEFT", -10, 0)
    removalQueue.remove:SetBackdropColor(0.20, 0.035, 0.025, 1)
    removalQueue.remove:SetBackdropBorderColor(0.85, 0.20, 0.12, 1)
    removalQueue.remove:RegisterForClicks("AnyUp")
    removalQueue.remove:SetAttribute("useOnKeyDown", false)
    removalQueue.combatBlocker = makeQueueButton(iRC:Text("INACTIVE_MEMBERS_QUEUE_COMBAT_BUTTON"), 245, false)
    removalQueue.combatBlocker:SetPoint("CENTER", removalQueue.remove, "CENTER", 0, 0)
    removalQueue.combatBlocker:SetFrameLevel(removalQueue.remove:GetFrameLevel() + 10)
    removalQueue.combatBlocker:Hide()
    removalQueue.testRemove = makeQueueButton("Simulate removal", 245, false)
    removalQueue.testRemove:SetPoint("CENTER", removalQueue.remove, "CENTER", 0, 0)
    removalQueue.testRemove:SetFrameLevel(removalQueue.remove:GetFrameLevel() + 20)
    removalQueue.testRemove:SetBackdropColor(0.12, 0.075, 0.025, 1)
    removalQueue.testRemove:SetBackdropBorderColor(0.85, 0.58, 0.16, 1)
    removalQueue.testRemove:Hide()
    addQueueMemberList(removalQueue)

    local advanceRemovalQueue
    local removalMacroName = "iRC_KickQueue"
    local function removalDebug(message, level)
        iRC:DebugMsg("Inactive removal: " .. tostring(message), level or 3)
        if iRC.Diagnostics then iRC.Diagnostics:Trace("INACTIVE_REMOVE", tostring(message)) end
    end

    local function prepareRemovalMacro(memberNames)
        if InCombatLockdown and InCombatLockdown() then
            removalDebug("macro preparation blocked by combat", 2)
            return false
        end
        if not GetMacroIndexByName or not CreateMacro or not EditMacro then
            removalDebug("macro API unavailable", 1)
            return false
        end

        local commands = {}
        for _, memberName in ipairs(memberNames or {}) do
            commands[#commands + 1] = "/gremove " .. tostring(memberName):gsub("[\r\n]", "")
        end
        local command = table.concat(commands, "\n")
        if command == "" or #command > 255 then
            removalDebug("invalid batch macro length=" .. tostring(#command), 1)
            return false
        end
        local index = GetMacroIndexByName(removalMacroName)
        removalDebug("preparing " .. removalMacroName .. " as '" .. command .. "'; existing index="
            .. tostring(index))
        local ok, result
        if index and index > 0 then
            ok, result = pcall(EditMacro, index, removalMacroName, "INV_MISC_QUESTIONMARK", command)
            removalDebug("EditMacro returned ok=" .. tostring(ok) .. ", result=" .. tostring(result), ok and 3 or 1)
        else
            ok, result = pcall(CreateMacro, removalMacroName, "INV_MISC_QUESTIONMARK", command)
            removalDebug("CreateMacro returned ok=" .. tostring(ok) .. ", result=" .. tostring(result), ok and 3 or 1)
        end
        if not ok then return false end

        index = GetMacroIndexByName(removalMacroName)
        if not index or index <= 0 then
            removalDebug("macro lookup failed after write", 1)
            return false
        end
        local actualBody = GetMacroBody and GetMacroBody(index) or nil
        removalDebug("macro ready at index=" .. tostring(index) .. ", body='" .. tostring(actualBody) .. "'"
            .. ", exact=" .. tostring(actualBody == command))
        if actualBody and actualBody ~= command then
            removalDebug("macro body was truncated or changed by WoW", 1)
            return false
        end
        removalQueue.remove:SetAttribute("type1", "macro")
        removalQueue.remove:SetAttribute("macro1", index)
        removalQueue.remove:SetAttribute("macrotext1", nil)
        removalQueue.removeCommand = command
        removalDebug("secure button bound: type1=macro, macro1=" .. tostring(index)
            .. ", useOnKeyDown=" .. tostring(removalQueue.remove:GetAttribute("useOnKeyDown")))
        return true
    end

    local function findQueueCandidate(name, threshold, testPreview, excludedRank)
        if iRC.InvalidateGuildRosterSnapshot then iRC:InvalidateGuildRosterSnapshot() end
        for _, member in ipairs(getEligibleInactiveMembers(threshold, testPreview, excludedRank)) do
            if iRC:NormalizeName(member.name) == iRC:NormalizeName(name) then return member end
        end
        return nil
    end

    local function finishRemovalQueue()
        if not removalQueue.active then return end
        local removed = removalQueue.removed or 0
        local skipped = removalQueue.skipped or 0
        local failed = removalQueue.failed or 0
        removalQueue.active = nil
        removalQueue.waitingNames = nil
        removalQueue.timerTicket = nil
        removalQueue:Hide()
        if removalQueue.testPreview then
            iRC:Print(iRC:Text("INACTIVE_MEMBERS_QUEUE_TEST_COMPLETE", removed, skipped))
        else
            iRC:Print(iRC:Text("INACTIVE_MEMBERS_QUEUE_COMPLETE", removed, skipped, failed))
            iRC:RefreshGuildRoster()
        end
        removalQueue.testPreview = nil
        UI:RefreshIfShown()
    end

    local function abortRemovalQueueForNativePermission()
        if not removalQueue.active or not removalQueue.waitingNames then return false end
        local remaining = math.max(1, (removalQueue.total or 1) - (removalQueue.index or 1) + 1)
        removalQueue.failed = (removalQueue.failed or 0) + remaining
        removalDebug("WoW denied native guild permission; cancelling " .. tostring(remaining)
            .. " queued action(s)", 1)
        removalQueue.active, removalQueue.currentNames, removalQueue.waitingNames = nil, nil, nil
        removalQueue.timerTicket, removalQueue.macroReady, removalQueue.testPreview = nil, nil, nil
        removalQueue:Hide()
        iRC:Print(iRC.Colors.Red .. "Removal queue stopped: WoW says this character does not have native "
            .. "guild permission. " .. tostring(remaining) .. " queued action(s) were cancelled."
            .. iRC.Colors.Reset)
        iRC:RefreshGuildRoster()
        UI:RefreshIfShown()
        return true
    end

    local function resolvePendingRemoval(finalCheck)
        local names = removalQueue.waitingNames
        if not removalQueue.active or not names then return end
        if iRC.InvalidateGuildRosterSnapshot then iRC:InvalidateGuildRosterSnapshot() end
        local present = {}
        for _, member in ipairs(iRC:GetGuildRosterSnapshot()) do
            present[iRC:NormalizeName(member.name)] = true
        end
        local remaining = 0
        for _, name in ipairs(names) do
            if present[iRC:NormalizeName(name)] then remaining = remaining + 1 end
        end
        removalDebug("batch roster check: remaining=" .. tostring(remaining) .. "/" .. tostring(#names)
            .. ", final=" .. tostring(finalCheck == true))
        if remaining > 0 and not finalCheck then return end

        removalQueue.waitingNames = nil
        removalQueue.timerTicket = nil
        for _, name in ipairs(names) do
            if present[iRC:NormalizeName(name)] then
                removalQueue.failed = (removalQueue.failed or 0) + 1
                iRC:Print(iRC.Colors.Red .. iRC:Text("INACTIVE_MEMBERS_QUEUE_FAILED", iRC:FormatPlayerName(name))
                    .. iRC.Colors.Reset)
            else
                removalQueue.removed = (removalQueue.removed or 0) + 1
                iRC:Print(iRC:Text("INACTIVE_MEMBERS_QUEUE_CONFIRMED", iRC:FormatPlayerName(name)))
            end
        end
        removalQueue.index = removalQueue.batchNextIndex or ((removalQueue.index or 1) + #names)
        removalQueue.currentNames, removalQueue.batchNextIndex = nil, nil
        advanceRemovalQueue()
        UI:RefreshIfShown()
    end

    advanceRemovalQueue = function()
        if not removalQueue.active or removalQueue.waitingNames then return end
        if not iRC:HasGuildPermission("memberRemoval") then
            iRC:Print(iRC.Colors.Red .. "The removal queue stopped because your delegated permission is no longer active."
                .. iRC.Colors.Reset)
            removalQueue.active = nil
            removalQueue:Hide()
            return
        end

        while removalQueue.index <= removalQueue.total do
            local batchNames, commands = {}, {}
            local cursor = removalQueue.index
            while cursor <= removalQueue.total do
                local requestedName = removalQueue.items[cursor]
                local candidate = findQueueCandidate(requestedName, removalQueue.threshold,
                    removalQueue.testPreview, removalQueue.excludedRank)
                if candidate then
                    local line = "/gremove " .. tostring(candidate.name):gsub("[\r\n]", "")
                    local body = table.concat(commands, "\n")
                    local nextLength = #body + (#commands > 0 and 1 or 0) + #line
                    if nextLength > 255 then break end
                    commands[#commands + 1] = line
                    batchNames[#batchNames + 1] = candidate.name
                else
                    removalQueue.skipped = (removalQueue.skipped or 0) + 1
                    iRC:Print(iRC.Colors.Yellow .. iRC:Text("INACTIVE_MEMBERS_QUEUE_SKIPPED",
                        iRC:FormatPlayerName(requestedName)) .. iRC.Colors.Reset)
                end
                cursor = cursor + 1
            end
            if #batchNames == 0 then
                if cursor <= removalQueue.total then
                    removalQueue.failed = (removalQueue.failed or 0) + 1
                    iRC:Print(iRC.Colors.Red .. "A removal command exceeds WoW's 255-byte macro limit."
                        .. iRC.Colors.Reset)
                    cursor = cursor + 1
                end
                removalQueue.index = cursor
            else
                removalQueue.currentNames = batchNames
                removalQueue.batchNextIndex = cursor
                removalQueue:SetBatchMembers(batchNames)
                local batchEnd = cursor - 1
                removalQueue.progress:SetText(tostring(removalQueue.index) .. "-" .. tostring(batchEnd)
                    .. " / " .. tostring(removalQueue.total))
                if removalQueue.testPreview then
                    removalQueue.macroReady = nil
                    removalQueue.testRemove.text:SetText("Simulate removal batch (" .. #batchNames .. ")")
                    removalQueue.testRemove:Show()
                    removalQueue.combatBlocker:Hide()
                    removalQueue.body:SetText("Test-admin preview: one click simulates removing " .. #batchNames
                        .. " selected members. No guild roster changes will be made.")
                elseif InCombatLockdown and InCombatLockdown() then
                    removalQueue.macroReady = nil
                    removalQueue.testRemove:Hide()
                    removalQueue.body:SetText(iRC:Text("INACTIVE_MEMBERS_QUEUE_COMBAT"))
                    removalQueue.combatBlocker:Show()
                else
                    removalQueue.testRemove:Hide()
                    removalQueue.remove.text:SetText("Remove batch (" .. #batchNames .. ")")
                    removalQueue.macroReady = prepareRemovalMacro(batchNames)
                    removalDebug("popup batch=" .. tostring(#batchNames) .. ", macroReady="
                        .. tostring(removalQueue.macroReady == true))
                    removalQueue.remove:SetEnabled(removalQueue.macroReady == true)
                    removalQueue.remove:SetAlpha(removalQueue.macroReady and 1 or 0.42)
                    removalQueue.combatBlocker:Hide()
                    removalQueue.body:SetText(removalQueue.macroReady
                        and ("Click once to remove this batch of " .. #batchNames
                            .. " members. iRC will verify every removal before continuing.")
                        or "iRC could not create or update its iRC_KickQueue macro. Free a general macro slot, leave combat, and reopen this removal queue.")
                end
                removalQueue.skip:SetEnabled(true)
                removalQueue.skip:SetAlpha(1)
                removalQueue:Show()
                removalQueue:Raise()
                return
            end
        end
        finishRemovalQueue()
    end

    local function startRemovalQueue(names, threshold, testPreview, excludedRank)
        if type(names) ~= "table" or #names == 0 then return false end
        removalQueue.items = names
        removalQueue.total = #names
        removalQueue.index = 1
        removalQueue.threshold = threshold
        removalQueue.excludedRank = type(excludedRank) == "number" and excludedRank or nil
        removalQueue.removed = 0
        removalQueue.skipped = 0
        removalQueue.failed = 0
        removalQueue.currentNames = nil
        removalQueue.waitingNames = nil
        removalQueue.batchNextIndex = nil
        removalQueue.timerTicket = nil
        removalQueue.macroReady = nil
        removalQueue.testPreview = testPreview == true
        removalQueue.active = true
        advanceRemovalQueue()
        return true
    end

    function removalQueue:Cancel()
        self.active = nil
        self.currentNames = nil
        self.waitingNames = nil
        self.batchNextIndex = nil
        self.timerTicket = nil
        self.testPreview = nil
        self.excludedRank = nil
        self:Hide()
    end

    removalQueue.cancel:SetScript("OnClick", function() removalQueue:Cancel() end)
    removalQueue.skip:SetScript("OnClick", function()
        if not removalQueue.active or removalQueue.waitingNames then return end
        local count = #(removalQueue.currentNames or {})
        removalQueue.skipped = (removalQueue.skipped or 0) + count
        removalQueue.index = removalQueue.batchNextIndex or ((removalQueue.index or 1) + math.max(1, count))
        removalQueue.currentNames, removalQueue.batchNextIndex = nil, nil
        advanceRemovalQueue()
    end)
    removalQueue.testRemove:SetScript("OnClick", function()
        if not removalQueue.active or not removalQueue.testPreview or removalQueue.waitingNames
            or not removalQueue.currentNames then return end
        for _, name in ipairs(removalQueue.currentNames) do
            iRC:Print(iRC:Text("INACTIVE_MEMBERS_TEST_REMOVE", iRC:FormatPlayerName(name)))
            removalQueue.removed = (removalQueue.removed or 0) + 1
        end
        removalQueue.index = removalQueue.batchNextIndex or removalQueue.index
        removalQueue.currentNames, removalQueue.batchNextIndex = nil, nil
        advanceRemovalQueue()
    end)
    removalQueue.remove:SetScript("PostClick", function(_, mouseButton)
        removalDebug("secure button PostClick: button=" .. tostring(mouseButton) .. ", active="
            .. tostring(removalQueue.active == true) .. ", macroReady="
            .. tostring(removalQueue.macroReady == true) .. ", command='"
            .. tostring(removalQueue.removeCommand) .. "'")
        if mouseButton ~= "LeftButton" then return end
        if not removalQueue.active or removalQueue.waitingNames or not removalQueue.currentNames then return end
        if InCombatLockdown and InCombatLockdown() then
            removalQueue.body:SetText(iRC:Text("INACTIVE_MEMBERS_QUEUE_COMBAT"))
            removalQueue.combatBlocker:Show()
            return
        end
        if not removalQueue.macroReady then return end
        removalQueue.waitingNames = removalQueue.currentNames
        removalDebug("waiting for roster confirmation of batch size " .. tostring(#removalQueue.waitingNames))
        removalQueue.body:SetText("Waiting for the guild roster to confirm " .. #removalQueue.waitingNames
            .. " removals...")
        removalQueue.remove:SetEnabled(false)
        removalQueue.remove:SetAlpha(0.42)
        removalQueue.skip:SetEnabled(false)
        removalQueue.skip:SetAlpha(0.42)
        iRC:RefreshGuildRoster()
        if C_Timer and C_Timer.After then
            local ticket = {}
            removalQueue.timerTicket = ticket
            C_Timer.After(8, function()
                if removalQueue.timerTicket == ticket then
                    removalDebug("confirmation timeout reached for removal batch", 2)
                    resolvePendingRemoval(true)
                end
            end)
        else
            resolvePendingRemoval(true)
        end
    end)
    removalQueue:RegisterEvent("GUILD_ROSTER_UPDATE")
    removalQueue:RegisterEvent("CHAT_MSG_SYSTEM")
    removalQueue:RegisterEvent("PLAYER_REGEN_DISABLED")
    removalQueue:RegisterEvent("PLAYER_REGEN_ENABLED")
    removalQueue:SetScript("OnEvent", function(_, event, message)
        if not removalQueue.active then return end
        removalDebug("event=" .. tostring(event) .. ", waiting=" .. tostring(removalQueue.waitingNames ~= nil))
        if event == "CHAT_MSG_SYSTEM" and removalQueue.waitingNames
            and isNativePermissionDeniedMessage(message) then
            abortRemovalQueueForNativePermission()
        elseif event == "GUILD_ROSTER_UPDATE" and removalQueue.waitingNames then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function() resolvePendingRemoval(false) end)
            else
                resolvePendingRemoval(false)
            end
        elseif event == "PLAYER_REGEN_DISABLED" and not removalQueue.waitingNames then
            advanceRemovalQueue()
        elseif event == "PLAYER_REGEN_ENABLED" and not removalQueue.waitingNames then
            advanceRemovalQueue()
        end
    end)
    removalQueue:Hide()
    frame.removalQueue = removalQueue

    local rankQueue = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    rankQueue:SetSize(590, 420)
    rankQueue:SetPoint("CENTER", frame, "CENTER", 0, 20)
    rankQueue:SetFrameStrata("FULLSCREEN_DIALOG")
    rankQueue:SetToplevel(true)
    rankQueue:EnableMouse(true)
    createBackdrop(rankQueue, { 0.025, 0.022, 0.018, 1 }, { 0.72, 0.45, 0.16, 1 })
    rankQueue.title = rankQueue:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    rankQueue.title:SetPoint("TOPLEFT", 22, -20)
    rankQueue.title:SetTextColor(unpack(COLORS.gold))
    rankQueue.progress = rankQueue:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    rankQueue.progress:SetPoint("TOPRIGHT", -22, -23)
    rankQueue.body = rankQueue:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    rankQueue.body:SetPoint("TOPLEFT", rankQueue.title, "BOTTOMLEFT", 0, -20)
    rankQueue.body:SetPoint("TOPRIGHT", rankQueue, "TOPRIGHT", -22, -58)
    rankQueue.body:SetJustifyH("LEFT")
    rankQueue.body:SetJustifyV("TOP")
    rankQueue.body:SetWordWrap(true)

    local function makeRankQueueButton(text, width, secure)
        local template = secure and "SecureActionButtonTemplate,BackdropTemplate" or "BackdropTemplate"
        local button = CreateFrame("Button", nil, rankQueue, template)
        button:SetSize(width, 30)
        createBackdrop(button, { 0.08, 0.06, 0.04, 1 }, { 0.48, 0.35, 0.16, 1 })
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        button.text:SetPoint("CENTER")
        button.text:SetText(text)
        button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
        button.highlight:SetAllPoints()
        button.highlight:SetColorTexture(1, 0.72, 0.22, 0.12)
        return button
    end

    rankQueue.cancel = makeRankQueueButton("Cancel remaining", 140, false)
    rankQueue.cancel:SetPoint("BOTTOMRIGHT", rankQueue, "BOTTOMRIGHT", -22, 18)
    rankQueue.skip = makeRankQueueButton("Skip", 90, false)
    rankQueue.skip:SetPoint("RIGHT", rankQueue.cancel, "LEFT", -10, 0)
    rankQueue.apply = makeRankQueueButton("Change rank", 245, true)
    rankQueue.apply:SetPoint("RIGHT", rankQueue.skip, "LEFT", -10, 0)
    rankQueue.apply:RegisterForClicks("AnyUp")
    rankQueue.apply:SetAttribute("useOnKeyDown", false)
    rankQueue.simulate = makeRankQueueButton("Simulate rank change", 245, false)
    rankQueue.simulate:SetPoint("CENTER", rankQueue.apply, "CENTER", 0, 0)
    rankQueue.simulate:SetFrameLevel(rankQueue.apply:GetFrameLevel() + 20)
    rankQueue.simulate:Hide()
    rankQueue.combatBlocker = makeRankQueueButton("Leave combat to continue", 245, false)
    rankQueue.combatBlocker:SetPoint("CENTER", rankQueue.apply, "CENTER", 0, 0)
    rankQueue.combatBlocker:SetFrameLevel(rankQueue.apply:GetFrameLevel() + 10)
    rankQueue.combatBlocker:Hide()
    addQueueMemberList(rankQueue)

    local advanceRankQueue
    local scheduleRankConfirmationPoll
    local rankMacroName = "iRC_RankQueue"
    local function rankQueueDebug(message, level)
        iRC:DebugMsg("Rank management: " .. tostring(message), level or 3)
        if iRC.Diagnostics then iRC.Diagnostics:Trace("RANK_MANAGEMENT", tostring(message)) end
    end

    local function prepareRankMacro(names, action)
        if InCombatLockdown and InCombatLockdown() then return false end
        if not GetMacroIndexByName or not CreateMacro or not EditMacro then return false end
        local prefix = action == "PROMOTE" and "/gpromote " or "/gdemote "
        local commands = {}
        for _, name in ipairs(names or {}) do
            commands[#commands + 1] = prefix .. tostring(name):gsub("[\r\n]", "")
        end
        local command = table.concat(commands, "\n")
        if command == "" or #command > 255 then return false end
        local index = GetMacroIndexByName(rankMacroName)
        local ok
        if index and index > 0 then
            ok = pcall(EditMacro, index, rankMacroName, "INV_MISC_QUESTIONMARK", command)
        else
            ok = pcall(CreateMacro, rankMacroName, "INV_MISC_QUESTIONMARK", command)
        end
        if not ok then return false end
        index = GetMacroIndexByName(rankMacroName)
        if not index or index <= 0 then return false end
        local actualBody = GetMacroBody and GetMacroBody(index) or nil
        if actualBody and actualBody ~= command then
            rankQueueDebug("macro body was truncated or changed by WoW", 1)
            return false
        end
        rankQueue.apply:SetAttribute("type1", "macro")
        rankQueue.apply:SetAttribute("macro1", index)
        rankQueue.apply:SetAttribute("macrotext1", nil)
        rankQueue.command = command
        rankQueueDebug("prepared '" .. command .. "' at macro index " .. tostring(index))
        return true
    end

    local function getCurrentRank(name)
        if iRC.InvalidateGuildRosterSnapshot then iRC:InvalidateGuildRosterSnapshot() end
        for _, member in ipairs(iRC:GetGuildRosterSnapshot()) do
            if iRC:NormalizeName(member.name) == iRC:NormalizeName(name) then
                return member.rankIndex, member
            end
        end
        return nil, nil
    end

    local function finishRankQueue()
        if not rankQueue.active then return end
        local changed, skipped, failed = rankQueue.changed or 0, rankQueue.skipped or 0, rankQueue.failed or 0
        local simulated = rankQueue.testPreview == true
        rankQueue.active, rankQueue.waitingNames, rankQueue.waitingByKey, rankQueue.timerTicket = nil, nil, nil, nil
        rankQueue:Hide()
        if simulated then
            iRC:Print("Rank-management simulation complete: " .. changed .. " change(s), " .. skipped .. " skipped.")
        else
            iRC:Print("Rank-management queue complete: " .. changed .. " rank change(s), " .. skipped
                .. " skipped, " .. failed .. " failed.")
            iRC:RefreshGuildRoster()
        end
        rankQueue.testPreview, rankQueue.targetRank, rankQueue.stageChangedNames = nil, nil, nil
        rankQueue.simulatedRanks = nil
        UI:RefreshIfShown()
    end

    local function abortRankQueueForNativePermission()
        if not rankQueue.active or not rankQueue.waitingNames then return false end
        local remaining = math.max(1, (rankQueue.total or 1) - (rankQueue.index or 1) + 1)
        rankQueue.failed = (rankQueue.failed or 0) + remaining
        rankQueueDebug("WoW denied native guild permission; cancelling " .. tostring(remaining)
            .. " queued action(s)", 1)
        rankQueue.active, rankQueue.currentNames, rankQueue.waitingNames, rankQueue.waitingByKey = nil, nil, nil, nil
        rankQueue.timerTicket, rankQueue.macroReady, rankQueue.testPreview = nil, nil, nil
        rankQueue.targetRank, rankQueue.stageChangedNames, rankQueue.simulatedRanks = nil, nil, nil
        rankQueue:Hide()
        iRC:Print(iRC.Colors.Red .. "Rank-management queue stopped: WoW says this character does not have native "
            .. "guild permission. " .. tostring(remaining) .. " queued action(s) were cancelled."
            .. iRC.Colors.Reset)
        iRC:RefreshGuildRoster()
        UI:RefreshIfShown()
        return true
    end

    local function completeRankBatch()
        if not rankQueue.active or not rankQueue.waitingNames then return false end
        for _ in pairs(rankQueue.waitingByKey or {}) do return false end
        rankQueue.waitingNames, rankQueue.waitingByKey, rankQueue.timerTicket = nil, nil, nil
        rankQueue.index = rankQueue.batchNextIndex or rankQueue.index
        rankQueue.currentNames, rankQueue.batchNextIndex = nil, nil
        iRC:RefreshGuildRoster()
        advanceRankQueue()
        if frame:IsShown() and frame.category == "Rank Management" then UI:Refresh()
        else UI:RefreshIfShown() end
        return true
    end

    local function confirmPendingRankMember(name, source)
        if not rankQueue.active or not rankQueue.waitingByKey then return false end
        local key = iRC:NormalizeName(name)
        local confirmedName = rankQueue.waitingByKey[key]
        if not confirmedName then return false end
        local confirmedRank = rankQueue.action == "PROMOTE" and rankQueue.expectedRank - 1
            or rankQueue.expectedRank + 1
        rankQueueDebug((source or "WoW") .. " confirmed " .. tostring(rankQueue.action)
            .. " for " .. tostring(confirmedName))
        if iRC.RecordConfirmedGuildRankChange then
            iRC:RecordConfirmedGuildRankChange(confirmedName, confirmedRank)
        end
        rankQueue.waitingByKey[key] = nil
        rankQueue.changed = (rankQueue.changed or 0) + 1
        rankQueue.stageChangedNames[#rankQueue.stageChangedNames + 1] = confirmedName
        iRC:Print((rankQueue.action == "PROMOTE" and "Promoted " or "Demoted ")
            .. iRC:FormatPlayerName(confirmedName) .. ".")
        completeRankBatch()
        return true
    end

    local function rankNameFromConfirmationMessage(message)
        if not rankQueue.active or not rankQueue.waitingByKey then return nil end
        local plain = cleanSystemMessage(message)
        local action = rankQueue.action == "PROMOTE" and "promoted" or "demoted"
        local reportedName = plain:lower():match(" has " .. action .. " (.-) to ")
            or plain:lower():match(" have " .. action .. " (.-) to ")
        if not reportedName then return nil end
        reportedName = reportedName:gsub("^%[", ""):gsub("%]$", "")
        return rankQueue.waitingByKey[iRC:NormalizeName(reportedName)]
    end

    local function resolvePendingRankChange(finalCheck)
        if not rankQueue.active or not rankQueue.waitingNames then return end
        local wantedRank = rankQueue.action == "PROMOTE" and rankQueue.expectedRank - 1
            or rankQueue.expectedRank + 1
        local pending = {}
        for _, name in ipairs(rankQueue.waitingNames) do
            if rankQueue.waitingByKey[iRC:NormalizeName(name)] then pending[#pending + 1] = name end
        end
        for _, name in ipairs(pending) do
            local currentRank = getCurrentRank(name)
            rankQueueDebug("batch roster check for " .. tostring(name) .. ": expected=" .. tostring(wantedRank)
                .. ", current=" .. tostring(currentRank) .. ", final=" .. tostring(finalCheck == true))
            if currentRank == wantedRank then confirmPendingRankMember(name, "guild roster") end
            if not rankQueue.waitingNames then return end
        end
        if not finalCheck then return end
        for _, name in ipairs(rankQueue.waitingNames) do
            local key = iRC:NormalizeName(name)
            if rankQueue.waitingByKey[key] then
                rankQueue.waitingByKey[key] = nil
                rankQueue.failed = (rankQueue.failed or 0) + 1
                iRC:Print(iRC.Colors.Red .. "WoW did not confirm the rank change for "
                    .. iRC:FormatPlayerName(name) .. "." .. iRC.Colors.Reset)
            end
        end
        completeRankBatch()
    end

    scheduleRankConfirmationPoll = function(ticket, attempt)
        if not C_Timer or not C_Timer.After then
            resolvePendingRankChange(true)
            return
        end
        C_Timer.After(1.5, function()
            if rankQueue.timerTicket ~= ticket or not rankQueue.waitingNames then return end
            resolvePendingRankChange(attempt >= 8)
            if rankQueue.timerTicket ~= ticket or not rankQueue.waitingNames then return end
            rankQueueDebug("requesting a fresh roster for confirmation attempt " .. tostring(attempt + 1))
            iRC:RefreshGuildRoster()
            scheduleRankConfirmationPoll(ticket, attempt + 1)
        end)
    end

    advanceRankQueue = function()
        if not rankQueue.active or rankQueue.waitingNames then return end
        if not iRC:HasGuildPermission("rankManagement") and not rankQueue.testPreview then
            iRC:Print(iRC.Colors.Red .. "The rank queue stopped because your delegated permission is no longer active."
                .. iRC.Colors.Reset)
            rankQueue.active = nil
            rankQueue:Hide()
            return
        end
        while rankQueue.index <= rankQueue.total do
            local batchNames, commands = {}, {}
            local cursor = rankQueue.index
            local prefix = rankQueue.action == "PROMOTE" and "/gpromote " or "/gdemote "
            while cursor <= rankQueue.total do
                local name = rankQueue.items[cursor]
                local currentRank, member = getCurrentRank(name)
                if rankQueue.testPreview then
                    currentRank = rankQueue.simulatedRanks[iRC:NormalizeName(name)] or currentRank
                end
                local valid = currentRank == rankQueue.expectedRank
                    and (rankQueue.testPreview or isRankActionEligible(member, rankQueue.action, false))
                if valid then
                    local line = prefix .. tostring(member.name):gsub("[\r\n]", "")
                    local body = table.concat(commands, "\n")
                    local nextLength = #body + (#commands > 0 and 1 or 0) + #line
                    if nextLength > 255 then break end
                    commands[#commands + 1] = line
                    batchNames[#batchNames + 1] = member.name
                else
                    rankQueue.skipped = rankQueue.skipped + 1
                    iRC:Print(iRC.Colors.Yellow .. "Skipped " .. iRC:FormatPlayerName(name)
                        .. " because their current rank or eligibility changed." .. iRC.Colors.Reset)
                end
                cursor = cursor + 1
            end
            if #batchNames == 0 then
                if cursor <= rankQueue.total then
                    rankQueue.failed = rankQueue.failed + 1
                    iRC:Print(iRC.Colors.Red .. "A rank command exceeds WoW's 255-byte macro limit."
                        .. iRC.Colors.Reset)
                    cursor = cursor + 1
                end
                rankQueue.index = cursor
            else
                rankQueue.currentNames = batchNames
                rankQueue.batchNextIndex = cursor
                rankQueue:SetBatchMembers(batchNames)
                rankQueue.progress:SetText(rankQueue.index .. "-" .. (cursor - 1) .. " / " .. rankQueue.total)
                local verb = rankQueue.action == "PROMOTE" and "Promote" or "Demote"
                local nextRank = rankQueue.action == "PROMOTE" and rankQueue.expectedRank - 1
                    or rankQueue.expectedRank + 1
                local stageDetail = " Rank " .. rankQueue.expectedRank .. " to Rank " .. nextRank
                    .. " (target Rank " .. rankQueue.targetRank .. ")."
                rankQueue.title:SetText(verb .. " guild members")
                if rankQueue.testPreview then
                    rankQueue.macroReady = nil
                    rankQueue.simulate.text:SetText("Simulate " .. verb:lower() .. " batch (" .. #batchNames .. ")")
                    rankQueue.simulate:Show()
                    rankQueue.combatBlocker:Hide()
                    rankQueue.body:SetText("Test-admin preview: one click simulates " .. verb:lower() .. "ing "
                        .. #batchNames .. " members." .. stageDetail .. " No guild rank will be changed.")
                elseif InCombatLockdown and InCombatLockdown() then
                    rankQueue.macroReady = nil
                    rankQueue.simulate:Hide()
                    rankQueue.body:SetText("Rank commands cannot be prepared during combat.")
                    rankQueue.combatBlocker:Show()
                else
                    rankQueue.simulate:Hide()
                    rankQueue.apply.text:SetText(verb .. " batch (" .. #batchNames .. ")")
                    rankQueue.macroReady = prepareRankMacro(batchNames, rankQueue.action)
                    rankQueue.apply:SetEnabled(rankQueue.macroReady == true)
                    rankQueue.apply:SetAlpha(rankQueue.macroReady and 1 or 0.42)
                    rankQueue.combatBlocker:Hide()
                    rankQueue.body:SetText(rankQueue.macroReady
                        and ("Click once to " .. verb:lower() .. " this batch of " .. #batchNames
                            .. " members." .. stageDetail .. " iRC will verify every rank change before continuing.")
                        or "iRC could not create or update its iRC_RankQueue macro. Free a general macro slot and reopen the queue.")
                end
                rankQueue.skip:SetEnabled(true)
                rankQueue.skip:SetAlpha(1)
                rankQueue:Show()
                rankQueue:Raise()
                return
            end
        end
        local hasAnotherLevel = false
        if type(rankQueue.targetRank) == "number" then
            hasAnotherLevel = rankQueue.action == "PROMOTE" and rankQueue.expectedRank - 1 > rankQueue.targetRank
                or rankQueue.action == "DEMOTE" and rankQueue.expectedRank + 1 < rankQueue.targetRank
        end
        if hasAnotherLevel and rankQueue.stageChangedNames[1] then
            rankQueue.items = rankQueue.stageChangedNames
            rankQueue.total, rankQueue.index = #rankQueue.items, 1
            rankQueue.expectedRank = rankQueue.action == "PROMOTE" and rankQueue.expectedRank - 1
                or rankQueue.expectedRank + 1
            rankQueue.stageChangedNames = {}
            rankQueueDebug("continuing multi-level rank change at rank " .. tostring(rankQueue.expectedRank)
                .. " toward target rank " .. tostring(rankQueue.targetRank))
            iRC:RefreshGuildRoster()
            advanceRankQueue()
            return
        end
        finishRankQueue()
    end

    local function startRankQueue(names, action, expectedRank, testPreview, targetRank)
        if type(names) ~= "table" or #names == 0 or (action ~= "PROMOTE" and action ~= "DEMOTE") then return false end
        targetRank = math.floor(tonumber(targetRank)
            or (action == "PROMOTE" and expectedRank - 1 or expectedRank + 1))
        if action == "PROMOTE" then
            if targetRank < 0 or targetRank >= expectedRank then return false end
            if not testPreview then
                local ownRank = getNativeGuildRank()
                if type(ownRank) ~= "number" or targetRank <= ownRank then return false end
            end
        elseif targetRank <= expectedRank or targetRank >= getGuildRankCount() then
            return false
        end
        rankQueue.items, rankQueue.total, rankQueue.index = names, #names, 1
        rankQueue.action, rankQueue.expectedRank = action, expectedRank
        rankQueue.targetRank = targetRank
        rankQueue.changed, rankQueue.skipped, rankQueue.failed = 0, 0, 0
        rankQueue.stageChangedNames = {}
        rankQueue.simulatedRanks = {}
        for _, name in ipairs(names) do
            rankQueue.simulatedRanks[iRC:NormalizeName(name)] = expectedRank
        end
        rankQueue.currentNames, rankQueue.waitingNames, rankQueue.waitingByKey = nil, nil, nil
        rankQueue.batchNextIndex, rankQueue.timerTicket = nil, nil
        rankQueue.macroReady = nil
        rankQueue.testPreview = testPreview == true
        rankQueue.active = true
        advanceRankQueue()
        return true
    end

    function rankQueue:Cancel()
        self.active, self.currentNames, self.waitingNames, self.waitingByKey = nil, nil, nil, nil
        self.batchNextIndex, self.timerTicket = nil, nil
        self.testPreview, self.targetRank, self.stageChangedNames, self.simulatedRanks = nil, nil, nil, nil
        self:Hide()
    end
    rankQueue.cancel:SetScript("OnClick", function() rankQueue:Cancel() end)
    rankQueue.skip:SetScript("OnClick", function()
        if not rankQueue.active or rankQueue.waitingNames then return end
        local count = #(rankQueue.currentNames or {})
        rankQueue.skipped = rankQueue.skipped + count
        rankQueue.index = rankQueue.batchNextIndex or (rankQueue.index + math.max(1, count))
        rankQueue.currentNames, rankQueue.batchNextIndex = nil, nil
        advanceRankQueue()
    end)
    rankQueue.simulate:SetScript("OnClick", function()
        if not rankQueue.active or not rankQueue.testPreview or not rankQueue.currentNames then return end
        for _, name in ipairs(rankQueue.currentNames) do
            iRC:Print("Test: would " .. rankQueue.action:lower() .. " " .. iRC:FormatPlayerName(name) .. ".")
            rankQueue.changed = rankQueue.changed + 1
            rankQueue.stageChangedNames[#rankQueue.stageChangedNames + 1] = name
            rankQueue.simulatedRanks[iRC:NormalizeName(name)] = rankQueue.action == "PROMOTE"
                and rankQueue.expectedRank - 1 or rankQueue.expectedRank + 1
        end
        rankQueue.index = rankQueue.batchNextIndex or rankQueue.index
        rankQueue.currentNames, rankQueue.batchNextIndex = nil, nil
        advanceRankQueue()
    end)
    rankQueue.apply:SetScript("PostClick", function(_, mouseButton)
        if mouseButton ~= "LeftButton" or not rankQueue.active or rankQueue.waitingNames
            or not rankQueue.currentNames or not rankQueue.macroReady then return end
        if InCombatLockdown and InCombatLockdown() then return end
        rankQueue.waitingNames = rankQueue.currentNames
        rankQueue.waitingByKey = {}
        for _, name in ipairs(rankQueue.waitingNames) do
            rankQueue.waitingByKey[iRC:NormalizeName(name)] = name
        end
        rankQueue.body:SetText("Waiting for WoW to confirm " .. #rankQueue.waitingNames .. " rank changes...")
        rankQueue.apply:SetEnabled(false)
        rankQueue.apply:SetAlpha(0.42)
        rankQueue.skip:SetEnabled(false)
        rankQueue.skip:SetAlpha(0.42)
        iRC:RefreshGuildRoster()
        if C_Timer and C_Timer.After then
            local ticket = {}
            rankQueue.timerTicket = ticket
            scheduleRankConfirmationPoll(ticket, 1)
        else
            resolvePendingRankChange(true)
        end
    end)
    rankQueue:RegisterEvent("GUILD_ROSTER_UPDATE")
    rankQueue:RegisterEvent("CHAT_MSG_SYSTEM")
    rankQueue:RegisterEvent("PLAYER_REGEN_DISABLED")
    rankQueue:RegisterEvent("PLAYER_REGEN_ENABLED")
    rankQueue:SetScript("OnEvent", function(_, event, message)
        if not rankQueue.active then return end
        if event == "CHAT_MSG_SYSTEM" and rankQueue.waitingNames
            and isNativePermissionDeniedMessage(message) then
            abortRankQueueForNativePermission()
        elseif event == "CHAT_MSG_SYSTEM" then
            local confirmedName = rankNameFromConfirmationMessage(message)
            if confirmedName then confirmPendingRankMember(confirmedName, "system message") end
        elseif event == "GUILD_ROSTER_UPDATE" and rankQueue.waitingNames then
            if C_Timer and C_Timer.After then C_Timer.After(0, function() resolvePendingRankChange(false) end)
            else resolvePendingRankChange(false) end
        elseif event == "PLAYER_REGEN_ENABLED" and not rankQueue.waitingNames then
            advanceRankQueue()
        end
    end)
    rankQueue:Hide()
    frame.rankQueue = rankQueue

    removeMemberConfirm.accept:SetScript("OnClick", function()
        local rankAction = removeMemberConfirm.rankAction
        local sourceRank = removeMemberConfirm.sourceRank
        local targetRank = removeMemberConfirm.targetRank
        local removeAll = removeMemberConfirm.removeAll == true
        local testPreview = removeMemberConfirm.testPreview == true
        local excludedRank = removeMemberConfirm.excludedRank
        local selectedNames, selectedOrder = {}, {}
        if removeAll then
            for _, candidate in ipairs(removeMemberConfirm.bulkCandidates or {}) do
                if candidate.selected then
                    selectedNames[iRC:NormalizeName(candidate.name)] = candidate.name
                    selectedOrder[#selectedOrder + 1] = candidate.name
                end
            end
        end
        local targetName = removeMemberConfirm.targetName
        local threshold = math.max(0, math.min(9999,
            math.floor(tonumber(removeMemberConfirm.threshold) or 30)))
        removeMemberConfirm:Hide()
        removeMemberConfirm.removeAll = nil
        removeMemberConfirm.testPreview = nil
        removeMemberConfirm.targetName = nil
        removeMemberConfirm.rankAction = nil
        removeMemberConfirm.sourceRank = nil
        removeMemberConfirm.targetRank = nil
        removeMemberConfirm.excludedRank = nil
        if rankAction then
            if not iRC:HasGuildPermission("rankManagement") and not testPreview then return end
            startRankQueue(selectedOrder, rankAction, sourceRank, testPreview, targetRank)
            return
        end
        if removeAll then
            if not iRC:HasGuildPermission("memberRemoval") then return end
            if testPreview then
                startRemovalQueue(selectedOrder, threshold, true, excludedRank)
                return
            end
            local eligible = getEligibleInactiveMembers(threshold, false, excludedRank)
            if #eligible == 0 then
                if testPreview then return end
                iRC:Print(iRC.Colors.Yellow .. iRC:Text("INACTIVE_MEMBERS_REMOVE_ALL_NONE") .. iRC.Colors.Reset)
                return
            end
            local removals = {}
            for _, member in ipairs(eligible) do
                if selectedNames[iRC:NormalizeName(member.name)] then removals[#removals + 1] = member.name end
            end
            if #removals == 0 then
                iRC:Print(iRC.Colors.Yellow .. iRC:Text("INACTIVE_MEMBERS_REMOVE_ALL_NONE") .. iRC.Colors.Reset)
                return
            end
            startRemovalQueue(removals, threshold, false, excludedRank)
            return
        end
        if not targetName or not iRC:HasGuildPermission("memberRemoval") then return end
        local candidate
        for _, member in ipairs(iRC:GetGuildRosterSnapshot()) do
            if iRC:NormalizeName(member.name) == iRC:NormalizeName(targetName) then candidate = member break end
        end
        if not candidate or candidate.online or not candidate.lastOnlineDays
            or candidate.lastOnlineDays < threshold or iRC:NormalizeName(candidate.name) == iRC:NormalizeName(iRC:GetPlayerName()) then
            iRC:Print(iRC.Colors.Yellow .. "That member is no longer eligible for inactive-member removal." .. iRC.Colors.Reset)
            return
        end
        local ownRank = getNativeGuildRank()
        if type(ownRank) ~= "number" or type(candidate.rankIndex) ~= "number" or candidate.rankIndex <= ownRank then
            iRC:Print(iRC.Colors.Red .. "Your WoW guild rank cannot remove that member." .. iRC.Colors.Reset)
            return
        end
        startRemovalQueue({ candidate.name }, threshold)
    end)
    removeMemberConfirm:Hide()
    frame.removeMemberConfirm = removeMemberConfirm

    local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 15, -10)
    header:SetPoint("TOPRIGHT", -15, -10)
    header:SetHeight(52)
    createBackdrop(header, { 0.10, 0.07, 0.035, 0.98 }, { 0.55, 0.41, 0.17, 1 })

    frame.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", header, "TOPLEFT", 16, -7)
    frame.title:SetText(iRC.Title or iRC.DisplayName)
    frame.title:SetTextColor(unpack(COLORS.gold))
    frame.player = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.player:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 16, 8)
    frame.player:SetWidth(500)
    frame.player:SetJustifyH("LEFT")
    frame.connectionStatus = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.connectionStatus:SetPoint("TOPRIGHT", header, "TOPRIGHT", -34, -8)
    frame.connectionStatus:SetJustifyH("RIGHT")
    frame.connectionGuild = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.connectionGuild:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -34, 8)
    frame.connectionGuild:SetWidth(330)
    frame.connectionGuild:SetJustifyH("RIGHT")
    local sidebar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -73)
    sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 17)
    sidebar:SetWidth(210)
    createBackdrop(sidebar, { 0.18, 0.11, 0.045, 0.98 }, { 0.58, 0.43, 0.18, 1 })
    frame.sidebar = sidebar
    local sidebarScroll = CreateFrame("ScrollFrame", nil, sidebar, "UIPanelScrollFrameTemplate")
    iRC:StyleScrollFrame(sidebarScroll)
    sidebarScroll:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 3, -5)
    sidebarScroll:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -23, 5)
    local navigationContent = CreateFrame("Frame", nil, sidebarScroll)
    navigationContent:SetSize(178, 1)
    sidebarScroll:SetScrollChild(navigationContent)
    sidebar:EnableMouseWheel(true)
    sidebar:SetScript("OnMouseWheel", function(_, delta)
        local maximum = math.max(0, navigationContent:GetHeight() - sidebarScroll:GetHeight())
        sidebarScroll:SetVerticalScroll(math.max(0,
            math.min(maximum, sidebarScroll:GetVerticalScroll() - delta * 36)))
    end)
    frame.sidebarScroll = sidebarScroll

    frame.tabs = {}
    for itemIndex, item in ipairs(MAIN_NAVIGATION) do
        if not item.hidden then
            local y = -((itemIndex - 1) * 28 + 10)
            if item.header then
                local heading = navigationContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                heading:SetPoint("TOPLEFT", navigationContent, "TOPLEFT", 12, y - 4)
                heading:SetWidth(160)
                heading:SetJustifyH("LEFT")
                heading:SetWordWrap(false)
                heading:SetTextColor(unpack(COLORS.gold))
                if item.id == "Current Server" then
                    heading:SetText(currentServerNavigationName())
                    frame.serverNameHeader = heading
                elseif item.managementHeader then
                    heading:SetText("Management")
                elseif item.id == "Personal" then
                    heading:SetText("Personal")
                else
                    heading:SetText(currentGuildNavigationName())
                    frame.guildNameHeader = heading
                end
                item.widget = heading
            else
                local tab = CreateFrame("Button", nil, navigationContent, "BackdropTemplate")
                tab:SetSize(item.grandchild and 142 or (item.child and 152 or 166), 25)
                tab:SetPoint("TOPLEFT", item.grandchild and 30 or (item.child and 20 or 10), y)
                createBackdrop(tab, { 0.08, 0.065, 0.05, 0.96 }, { 0.34, 0.28, 0.20, 1 })
                tab:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                tab.label:SetPoint("LEFT", 10, 0)
                tab.label:SetText((item.child or item.grandchild) and "- " .. item.label or item.label)
                tab.category = item.id
                tab:SetScript("OnClick", function(self)
                    if self.unavailable then return end
                    local previousCategory = frame.category
                    if previousCategory ~= self.category
                        and (previousCategory == "Inactive Member Management"
                            or self.category == "Inactive Member Management") then
                        resetInactiveMemberView(frame)
                    end
                    frame.category = self.category
                    if (self.category == "Guild Overview" or self.category == "Guild Rules") and frame.scroll then
                        frame.scroll:SetVerticalScroll(0)
                    end
                    if self.category == "Race Overview" then
                        guildStatsFilter = getCurrentGuildStatsFilter()
                        UI.preservedRaceScroll = 0
                        if previousCategory ~= self.category and iRC.RaceGrid then
                            iRC.RaceGrid:RequestGuildCacheFromOpen()
                        end
                    end
                    if self.category == "Guild Overview" or self.category == "Guild Members"
                        or self.category == "Inactive Member Management" or self.category == "Rank Management" then
                        iRC:RefreshGuildRoster()
                    end
                    if self.category ~= "Guild Members" and self.category ~= "Race Overview" then frame.subjectName = iRC:GetPlayerName() end
                    UI:Refresh()
                end)
                tab:SetScript("OnEnter", function(self)
                    if not self.unavailable or not self.unavailableReason or not GameTooltip then return end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(self.unavailableReason, 0.75, 0.75, 0.75, 1, true)
                    GameTooltip:Show()
                end)
                tab:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
                frame.tabs[item.id] = tab
                item.widget = tab
            end
        end
    end
    frame.LayoutNavigation = function()
        local testAdmin = iRC:IsTestAdmin()
        local function hasNavigationPermission(item)
            if item.requiresGuild and not iRC:IsInGuildConnection() then return false end
            if item.guildMasterOnly then return iRC:IsGuildMaster() end
            if not item.permission then return true end
            if (item.id == "Inactive Member Management" or item.id == "Rank Management") and testAdmin then return true end
            return iRC:HasGuildPermission(item.permission)
        end
        local showManagement = iRC:HasAnyManagementPermission()
        for _, navigationItem in ipairs(MAIN_NAVIGATION) do
            if navigationItem.permission and hasNavigationPermission(navigationItem) then
                showManagement = true
                break
            end
        end
        local visibleIndex = 0
        for _, item in ipairs(MAIN_NAVIGATION) do
            local visible = not item.hidden
                and (not item.managementHeader or showManagement)
                and hasNavigationPermission(item)
                and (not item.anyPermission or showManagement)
            local widget = item.widget
            if widget then
                widget:SetShown(visible)
                if visible then
                    if not item.header then
                        widget.unavailableReason = getNavigationUnavailableReason(item)
                        widget.unavailable = widget.unavailableReason ~= nil
                        local highlight = widget.GetHighlightTexture and widget:GetHighlightTexture()
                        if highlight then highlight:SetAlpha(widget.unavailable and 0 or 1) end
                    end
                    visibleIndex = visibleIndex + 1
                    local y = -((visibleIndex - 1) * 28 + 10)
                    widget:ClearAllPoints()
                    widget:SetPoint("TOPLEFT", navigationContent, "TOPLEFT",
                        item.header and 12 or (item.grandchild and 30 or (item.child and 20 or 10)), item.header and y - 4 or y)
                end
            end
        end
        navigationContent:SetHeight(math.max(sidebarScroll:GetHeight(), visibleIndex * 28 + 12))
        for _, item in ipairs(MAIN_NAVIGATION) do
            if item.id == frame.category and ((item.permission and not hasNavigationPermission(item))
                or (item.anyPermission and not showManagement) or getNavigationUnavailableReason(item)) then
                if frame.category == "Inactive Member Management" then resetInactiveMemberView(frame) end
                frame.category = "Guild Members"
                break
            end
        end
    end
    frame.LayoutNavigation()

    local main = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    main:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 13, 0)
    main:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 17)
    createBackdrop(main, { 0.055, 0.047, 0.038, 0.98 }, { 0.46, 0.37, 0.21, 1 })
    frame.main = main
    frame.contentTitle = main:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.contentTitle:SetPoint("TOPLEFT", 15, -14)
    frame.contentTitle:SetTextColor(unpack(COLORS.gold))
    frame.raceRefresh = makeIRCActionButton(main, 125, 25, iRC:Text("RL_GRID_REFRESH"), false)
    frame.raceRefresh:SetPoint("TOPRIGHT", -14, -9)
    frame.raceRefresh:SetScript("OnClick", function()
        if frame.category == "Race Overview" and frame.scroll then
            UI.preservedRaceScroll = frame.scroll:GetVerticalScroll()
        end
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
    frame.raceRefresh:SetScript("OnUpdate", function(self, elapsed)
        self.cooldownElapsed = (self.cooldownElapsed or 0) + elapsed
        if frame.cacheUpdating then
            local updating = iRC.RaceGrid and iRC.RaceGrid:IsCacheUpdating()
            frame.cacheUpdating:SetShown(updating and true or false)
            if updating then
                frame.cacheUpdating.rotation = ((frame.cacheUpdating.rotation or 0) + elapsed * 5) % (math.pi * 2)
                if frame.cacheUpdating.spinner.SetRotation then
                    frame.cacheUpdating.spinner:SetRotation(frame.cacheUpdating.rotation)
                end
            end
        end
        if self.cooldownElapsed < 0.25 then return end
        self.cooldownElapsed = 0
        local remaining = iRC.RaceGrid and iRC.RaceGrid:GetRefreshCooldownRemaining() or 0
        self:SetEnabled(remaining <= 0)
        self:SetAlpha(remaining <= 0 and 1 or 0.42)
        self:SetText(remaining > 0 and iRC:Text("RL_GRID_REFRESH_COOLDOWN", math.ceil(remaining)) or iRC:Text("RL_GRID_REFRESH"))
    end)
    frame.raceRefresh:Hide()
    frame.guildOverviewRefresh = makeIRCActionButton(main, 105, 25, "Refresh", false)
    frame.guildOverviewRefresh:SetPoint("TOPRIGHT", -14, -9)
    frame.guildOverviewRefresh:SetScript("OnClick", function()
        if iRC.InvalidateGuildRosterSnapshot then iRC:InvalidateGuildRosterSnapshot() end
        iRC:RefreshGuildRoster()
        UI:Refresh()
    end)
    frame.guildOverviewRefresh:Hide()
    frame.guildOverviewAltToggle = makeIRCActionButton(main, 170, 25, "Main characters only: ON", false)
    frame.guildOverviewAltToggle:SetPoint("RIGHT", frame.guildOverviewRefresh, "LEFT", -8, 0)
    frame.guildOverviewAltToggle:SetScript("OnClick", function()
        local settings = iRC:GetSettings()
        settings.excludeAltsFromGuildSnapshot = settings.excludeAltsFromGuildSnapshot == false
        UI:Refresh()
    end)
    frame.guildOverviewAltToggle:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Guild Overview roster scope")
        GameTooltip:AddLine("Count only main and unlinked characters in every Guild Overview total and calculation.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame.guildOverviewAltToggle:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    frame.guildOverviewAltToggle:Hide()
    frame.rulesViewToggle = CreateFrame("Button", nil, main, "BackdropTemplate")
    frame.rulesViewToggle:SetSize(150, 27)
    frame.rulesViewToggle:SetPoint("TOPRIGHT", main, "TOPRIGHT", -14, -9)
    createBackdrop(frame.rulesViewToggle, { 0.055, 0.045, 0.035, 0.98 }, { 0.28, 0.23, 0.16, 0.9 })
    frame.rulesViewToggle.activeGlow = frame.rulesViewToggle:CreateTexture(nil, "BACKGROUND")
    frame.rulesViewToggle.activeGlow:SetPoint("TOPLEFT", 3, -3)
    frame.rulesViewToggle.activeGlow:SetPoint("BOTTOMRIGHT", -3, 3)
    frame.rulesViewToggle.activeGlow:SetColorTexture(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 0.18)
    frame.rulesViewToggle.text = frame.rulesViewToggle:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.rulesViewToggle.text:SetPoint("CENTER")
    frame.rulesViewToggle.highlight = frame.rulesViewToggle:CreateTexture(nil, "HIGHLIGHT")
    frame.rulesViewToggle.highlight:SetAllPoints()
    frame.rulesViewToggle.highlight:SetColorTexture(1, 0.72, 0.22, 0.10)
    frame.rulesViewToggle:SetScript("OnClick", function()
        frame.rulesViewAsMember = not frame.rulesViewAsMember
        UI:Refresh()
    end)
    frame.rulesViewToggle:Hide()
    frame.cacheUpdating = CreateFrame("Frame", nil, main)
    frame.cacheUpdating:SetSize(130, 20)
    frame.cacheUpdating:SetPoint("RIGHT", frame.raceRefresh, "LEFT", -10, 0)
    frame.cacheUpdating.spinner = frame.cacheUpdating:CreateTexture(nil, "ARTWORK")
    frame.cacheUpdating.spinner:SetSize(16, 16)
    frame.cacheUpdating.spinner:SetPoint("LEFT", 0, 0)
    frame.cacheUpdating.spinner:SetTexture("Interface\\COMMON\\Indicator-Yellow")
    frame.cacheUpdating.text = frame.cacheUpdating:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.cacheUpdating.text:SetPoint("LEFT", frame.cacheUpdating.spinner, "RIGHT", 5, 0)
    frame.cacheUpdating.text:SetText(iRC:Text("RACEGRID_CACHE_UPDATING"))
    frame.cacheUpdating:Hide()
    frame.contentSubtitle = main:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.contentSubtitle:SetPoint("TOPLEFT", frame.contentTitle, "BOTTOMLEFT", 0, -5)
    frame.contentSubtitle:SetPoint("RIGHT", main, "RIGHT", -22, 0)
    frame.contentSubtitle:SetJustifyH("LEFT")
    frame.contentSubtitle:SetWordWrap(true)
    frame.memberProfessionSearch = createMemberProfessionSearch(main, frame)

    frame.guildStatsFilters = {}
    for index, filter in ipairs({
        { key = "ALL", label = "All" },
        { key = "RACE_LOCKED", label = "Race-Locked" },
        { key = "GUILD_FOUND", label = "Guild-Found" },
        { key = "SELF_FOUND", label = "Self-Found" },
    }) do
        local filterKey, filterLabel = filter.key, filter.label
        local button = CreateFrame("Button", nil, main, "BackdropTemplate")
        button:SetSize(160, 27)
        button:SetPoint("TOPLEFT", main, "TOPLEFT", 15 + (index - 1) * 166, -50)
        createBackdrop(button, { 0.055, 0.045, 0.035, 0.96 }, { 0.28, 0.23, 0.16, 0.9 })
        button.activeGlow = button:CreateTexture(nil, "BACKGROUND")
        button.activeGlow:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
        button.activeGlow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
        button.activeGlow:SetColorTexture(0, 0, 0, 0)
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        button.text:SetPoint("CENTER")
        button.text:SetText(filterLabel)
        button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
        button.highlight:SetAllPoints(button)
        button.highlight:SetColorTexture(1, 0.72, 0.22, 0.10)
        button:SetScript("OnClick", function()
            guildStatsFilter = filterKey
            UI.preservedRaceScroll = 0
            UI:Refresh()
        end)
        button.filterKey = filterKey
        frame.guildStatsFilters[index] = button
    end

    frame.guildStatsSearch = CreateFrame("EditBox", nil, main, "InputBoxTemplate")
    frame.guildStatsSearch:SetSize(300, 22)
    frame.guildStatsSearch:SetPoint("TOPLEFT", main, "TOPLEFT", 20, -84)
    frame.guildStatsSearch:SetAutoFocus(false)
    frame.guildStatsSearch:SetMaxLetters(80)
    frame.guildStatsSearch:SetTextInsets(5, 5, 0, 0)
    frame.guildStatsSearch:SetFontObject(GameFontHighlight)
    frame.guildStatsSearch:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame.guildStatsSearch:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    frame.guildStatsSearch:SetScript("OnTextChanged", function(self)
        self.hint:SetShown(self:GetText() == "")
        if self.suppressRefresh then return end
        UI.preservedRaceScroll = 0
        UI:Refresh()
    end)
    frame.guildStatsSearch.hint = frame.guildStatsSearch:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.guildStatsSearch.hint:SetPoint("LEFT", 7, 0)
    frame.guildStatsSearch.hint:SetText(iRC:Text("GUILD_STATS_SEARCH_HINT"))
    frame.guildStatsSearch.hint:SetTextColor(0.55, 0.55, 0.55)
    frame.guildStatsSearch:Hide()

    frame.guildLogSearch = CreateFrame("EditBox", nil, main, "InputBoxTemplate")
    frame.guildLogSearch:SetSize(300, 22)
    frame.guildLogSearch:SetPoint("TOPLEFT", main, "TOPLEFT", 20, -50)
    frame.guildLogSearch:SetAutoFocus(false)
    frame.guildLogSearch:SetMaxLetters(80)
    frame.guildLogSearch:SetTextInsets(5, 5, 0, 0)
    frame.guildLogSearch:SetFontObject(GameFontHighlight)
    frame.guildLogSearch:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame.guildLogSearch:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    frame.guildLogSearch:SetScript("OnTextChanged", function(self)
        self.hint:SetShown(self:GetText() == "")
        if self.updateSuggestions then self.updateSuggestions() end
        if frame.scroll then frame.scroll:SetVerticalScroll(0) end
        UI:Refresh()
    end)
    frame.guildLogSearch.hint = frame.guildLogSearch:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.guildLogSearch.hint:SetPoint("LEFT", 7, 0)
    frame.guildLogSearch.hint:SetText(iRC:Text("GUILD_LOG_SEARCH_HINT"))
    frame.guildLogSearch.hint:SetTextColor(0.55, 0.55, 0.55)
    frame.guildLogSearch.suggestions = CreateFrame("Frame", nil, frame.guildLogSearch, "BackdropTemplate")
    frame.guildLogSearch.suggestions:SetSize(300, 128)
    frame.guildLogSearch.suggestions:SetPoint("TOPLEFT", frame.guildLogSearch, "BOTTOMLEFT", 0, -2)
    frame.guildLogSearch.suggestions:SetFrameStrata("DIALOG")
    frame.guildLogSearch.suggestions:SetFrameLevel(main:GetFrameLevel() + 20)
    frame.guildLogSearch.suggestions:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame.guildLogSearch.suggestions:SetBackdropColor(0.03, 0.03, 0.03, 0.98)
    frame.guildLogSearch.suggestions:SetBackdropBorderColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 0.85)
    frame.guildLogSearch.buttons = {}
    local function updateGuildLogSuggestions()
        local search = frame.guildLogSearch
        local query = search:GetText():match("^%s*(.-)%s*$"):lower()
        local entries, seen = {}, {}
        local function add(label, priority, formatEvent)
            label = tostring(label or "")
            if formatEvent then
                label = label:gsub("_", " "):gsub("(%a)([%w']*)", function(first, rest)
                    return first:upper() .. rest:lower()
                end)
            end
            local key = label:lower()
            if label ~= "" and not seen[key] and key:find(query, 1, true) then
                seen[key] = true
                entries[#entries + 1] = { label = label, lower = key, priority = priority }
            end
        end
        if query ~= "" then
            for _, record in ipairs(iRC.Identity and iRC.Identity:GetGuildLog() or {}) do
                add(record.name, 1)
                add(record.eventType, 2, true)
            end
            table.sort(entries, function(a, b)
                local aStarts, bStarts = a.lower:find(query, 1, true) == 1, b.lower:find(query, 1, true) == 1
                if aStarts ~= bStarts then return aStarts end
                if a.priority ~= b.priority then return a.priority < b.priority end
                return a.lower < b.lower
            end)
        end
        for index, button in ipairs(search.buttons) do
            button.value = entries[index] and entries[index].label or nil
            button:SetShown(button.value ~= nil)
            if button.value then button.text:SetText(button.value) end
        end
        search.suggestions:SetShown(query ~= "" and entries[1] ~= nil and search:HasFocus())
    end
    frame.guildLogSearch.updateSuggestions = updateGuildLogSuggestions
    for index = 1, 5 do
        local button = CreateFrame("Button", nil, frame.guildLogSearch.suggestions)
        button:SetSize(282, 23)
        button:SetPoint("TOPLEFT", frame.guildLogSearch.suggestions, "TOPLEFT", 7, -6 - (index - 1) * 23)
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        button.text:SetPoint("LEFT", button, "LEFT", 7, 0)
        button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
        button.highlight:SetAllPoints()
        button.highlight:SetColorTexture(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 0.18)
        button:SetScript("OnClick", function(self)
            if not self.value then return end
            frame.guildLogSearch:SetText(self.value)
            frame.guildLogSearch:ClearFocus()
            frame.guildLogSearch.suggestions:Hide()
        end)
        frame.guildLogSearch.buttons[index] = button
    end
    frame.guildLogSearch:SetScript("OnEditFocusGained", updateGuildLogSuggestions)
    frame.guildLogSearch:SetScript("OnEditFocusLost", function(self)
        C_Timer.After(0, function()
            if not self:HasFocus() and not iRC:IsMouseOverFrame(self.suggestions) then self.suggestions:Hide() end
        end)
    end)
    frame.guildLogSearch:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self.suggestions:Hide()
    end)
    frame.guildLogSearch:SetScript("OnEnterPressed", function(self)
        local first = self.buttons[1]
        if first.value and self.suggestions:IsShown() then first:Click() else self:ClearFocus() end
    end)
    frame.guildLogSearch:Hide()
    frame.guildLogSearch.suggestions:Hide()

    frame.inactiveThreshold = CreateFrame("Frame", nil, main)
    frame.inactiveThreshold:SetSize(620, 62)
    frame.inactiveThreshold:SetPoint("TOPLEFT", main, "TOPLEFT", 20, -49)
    frame.inactiveThreshold.label = frame.inactiveThreshold:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.inactiveThreshold.label:SetPoint("TOPLEFT", frame.inactiveThreshold, "TOPLEFT", 0, -3)
    frame.inactiveThreshold.label:SetText(iRC:Text("INACTIVE_MEMBERS_THRESHOLD"))
    frame.inactiveThreshold.input = CreateFrame("EditBox", nil, frame.inactiveThreshold, "InputBoxTemplate")
    frame.inactiveThreshold.input:SetSize(58, 22)
    frame.inactiveThreshold.input:SetPoint("LEFT", frame.inactiveThreshold.label, "RIGHT", 10, 0)
    frame.inactiveThreshold.input:SetAutoFocus(false)
    frame.inactiveThreshold.input:SetNumeric(true)
    frame.inactiveThreshold.input:SetMaxLetters(4)
    frame.inactiveThreshold.input:SetTextInsets(5, 5, 0, 0)
    frame.inactiveThreshold.days = frame.inactiveThreshold:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.inactiveThreshold.days:SetPoint("LEFT", frame.inactiveThreshold.input, "RIGHT", 8, 0)
    frame.inactiveThreshold.days:SetText(iRC:Text("INACTIVE_MEMBERS_DAYS"))
    frame.inactiveThreshold.apply = makeIRCActionButton(frame.inactiveThreshold, 82, 25,
        iRC:Text("INACTIVE_MEMBERS_APPLY"), false)
    frame.inactiveThreshold.apply:SetPoint("LEFT", frame.inactiveThreshold.days, "RIGHT", 12, 0)
    local function applyInactiveThreshold()
        local days = math.max(0, math.min(9999,
            math.floor(tonumber(frame.inactiveThreshold.input:GetText()) or frame.inactiveMemberDays or 30)))
        frame.inactiveMemberDays = days
        frame.inactiveThreshold.input:SetText(tostring(days))
        frame.inactiveThreshold.input:ClearFocus()
        if frame.scroll then frame.scroll:SetVerticalScroll(0) end
        iRC:RefreshGuildRoster()
        UI:Refresh()
    end
    frame.inactiveThreshold.apply:SetScript("OnClick", applyInactiveThreshold)
    frame.inactiveThreshold.input:SetScript("OnEnterPressed", applyInactiveThreshold)
    frame.inactiveThreshold.input:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(frame.inactiveMemberDays or 30))
        self:ClearFocus()
    end)
    frame.inactiveThreshold.excludeLabel = frame.inactiveThreshold:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.inactiveThreshold.excludeLabel:SetPoint("TOPLEFT", frame.inactiveThreshold, "TOPLEFT", 0, -38)
    frame.inactiveThreshold.excludeLabel:SetText("Exclude ranks above this")
    frame.inactiveThreshold.excludeRank = CreateFrame("Button", nil,
        frame.inactiveThreshold, "BackdropTemplate")
    local excludeRankDropdown = frame.inactiveThreshold.excludeRank
    excludeRankDropdown:SetSize(300, 25)
    excludeRankDropdown:SetPoint("LEFT", frame.inactiveThreshold.excludeLabel, "RIGHT", 14, -1)
    createBackdrop(excludeRankDropdown, { 0.055, 0.045, 0.032, 0.98 }, { 0.46, 0.35, 0.18, 1 })
    excludeRankDropdown.text = excludeRankDropdown:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    excludeRankDropdown.text:SetPoint("LEFT", 10, 0)
    excludeRankDropdown.text:SetPoint("RIGHT", -30, 0)
    excludeRankDropdown.text:SetJustifyH("LEFT")
    excludeRankDropdown.arrow = excludeRankDropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    excludeRankDropdown.arrow:SetPoint("RIGHT", -10, 0)
    excludeRankDropdown.arrow:SetText("v")
    excludeRankDropdown:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    excludeRankDropdown.menu = CreateFrame("Frame", nil, excludeRankDropdown, "BackdropTemplate")
    excludeRankDropdown.menu:SetPoint("TOPLEFT", excludeRankDropdown, "BOTTOMLEFT", 0, -2)
    excludeRankDropdown.menu:SetPoint("TOPRIGHT", excludeRankDropdown, "BOTTOMRIGHT", 0, -2)
    excludeRankDropdown.menu:SetHeight(12)
    excludeRankDropdown.menu:SetFrameStrata("FULLSCREEN_DIALOG")
    excludeRankDropdown.menu:SetFrameLevel(frame:GetFrameLevel() + 45)
    excludeRankDropdown.menu:SetClampedToScreen(true)
    excludeRankDropdown.menu:SetToplevel(true)
    excludeRankDropdown.menu:EnableMouse(true)
    excludeRankDropdown.menu:EnableMouseWheel(true)
    excludeRankDropdown.menu:SetScript("OnMouseDown", function() end)
    excludeRankDropdown.menu:SetScript("OnMouseWheel", function() end)
    createBackdrop(excludeRankDropdown.menu, { 0.025, 0.022, 0.018, 0.995 }, { 0.72, 0.45, 0.16, 1 })
    excludeRankDropdown.menu.buttons = {}
    excludeRankDropdown.menu:Hide()

    function excludeRankDropdown:Refresh()
        local options = { { value = -1, label = "Do not exclude ranks" } }
        for _, rank in ipairs(iRC:GetGuildRankOptions()) do
            options[#options + 1] = {
                value = rank.index,
                label = tostring(rank.name or ("Rank " .. rank.index)) .. " (Rank " .. rank.index .. ") and above",
            }
        end
        local selected = type(frame.inactiveExcludedRank) == "number" and frame.inactiveExcludedRank or -1
        self.menu:SetHeight(math.max(12, #options * 28 + 8))
        for index, option in ipairs(options) do
            local button = self.menu.buttons[index]
            if not button then
                button = CreateFrame("Button", nil, self.menu, "BackdropTemplate")
                button:SetHeight(25)
                button:SetPoint("TOPLEFT", self.menu, "TOPLEFT", 5, -5 - (index - 1) * 28)
                button:SetPoint("TOPRIGHT", self.menu, "TOPRIGHT", -5, -5 - (index - 1) * 28)
                createBackdrop(button, { 0.06, 0.05, 0.038, 0.98 }, { 0.28, 0.23, 0.16, 0.9 })
                button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                button.text:SetPoint("LEFT", 9, 0)
                button.text:SetPoint("RIGHT", -9, 0)
                button.text:SetJustifyH("LEFT")
                button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                self.menu.buttons[index] = button
            end
            button.value = option.value
            button.label = option.label
            button.text:SetText(option.label)
            local isSelected = selected == option.value
            button:SetBackdropColor(isSelected and 0.19 or 0.06, isSelected and 0.11 or 0.05,
                isSelected and 0.035 or 0.038, 0.98)
            button:SetBackdropBorderColor(isSelected and COLORS.gold[1] or 0.28,
                isSelected and COLORS.gold[2] or 0.23, isSelected and COLORS.gold[3] or 0.16, 1)
            button:SetScript("OnClick", function(self)
                frame.inactiveExcludedRank = self.value >= 0 and self.value or nil
                excludeRankDropdown.menu:Hide()
                frame:RefreshInactiveRankExclude()
                if frame.scroll then frame.scroll:SetVerticalScroll(0) end
                UI:Refresh()
            end)
            button:Show()
            if isSelected then excludeRankDropdown.text:SetText(option.label) end
        end
        for index = #options + 1, #self.menu.buttons do self.menu.buttons[index]:Hide() end
    end
    function frame:RefreshInactiveRankExclude()
        excludeRankDropdown:Refresh()
    end
    excludeRankDropdown:SetScript("OnClick", function(self)
        self.menu:SetShown(not self.menu:IsShown())
        if self.menu:IsShown() then self.menu:Raise() end
    end)
    frame:RefreshInactiveRankExclude()
    frame.inactiveThreshold:Hide()
    frame.inactiveRemoveAll = makeIRCActionButton(main, 190, 25,
        iRC:Text("INACTIVE_MEMBERS_REMOVE_ALL", 0), true)
    frame.inactiveRemoveAll:SetPoint("TOPRIGHT", main, "TOPRIGHT", -18, -50)
    frame.inactiveRemoveAll:SetScript("OnClick", function()
        local threshold = math.max(0, math.min(9999,
            math.floor(tonumber(frame.inactiveMemberDays) or 30)))
        local excludedRank = frame.inactiveExcludedRank
        local eligible = getEligibleInactiveMembers(threshold, false, excludedRank)
        local testPreview = false
        if #eligible == 0 and iRC:IsTestAdmin() then
            eligible = getEligibleInactiveMembers(threshold, true, excludedRank)
            testPreview = true
        end
        if #eligible == 0 and not testPreview then
            iRC:Print(iRC.Colors.Yellow .. iRC:Text("INACTIVE_MEMBERS_REMOVE_ALL_NONE") .. iRC.Colors.Reset)
            return
        end
        local confirm = frame.removeMemberConfirm
        confirm.removeAll = true
        confirm.rankAction = nil
        confirm.sourceRank = nil
        confirm.targetName = nil
        confirm.threshold = threshold
        confirm.excludedRank = excludedRank
        confirm.testPreview = testPreview
        confirm:SetBulkLayout(false)
        confirm.bulkList:Show()
        confirm.title:SetText(iRC:Text("INACTIVE_MEMBERS_REMOVE_ALL_TITLE"))
        local body = iRC:Text("INACTIVE_MEMBERS_REMOVE_ALL_BODY", #eligible, threshold)
        if testPreview then body = body .. "\n\n" .. iRC:Text("INACTIVE_MEMBERS_REMOVE_ALL_TEST_PREVIEW") end
        confirm.body:SetText(body)
        confirm.setBulkCandidates(eligible)
        confirm:Show()
        confirm:Raise()
    end)
    frame.inactiveRemoveAll:Hide()

    frame.rankManagementControls = CreateFrame("Frame", nil, main)
    frame.rankManagementControls:SetPoint("TOPLEFT", main, "TOPLEFT", 18, -45)
    frame.rankManagementControls:SetPoint("TOPRIGHT", main, "TOPRIGHT", -18, -45)
    frame.rankManagementControls:SetHeight(32)
    frame.rankManagementControls.label = frame.rankManagementControls:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.rankManagementControls.label:SetPoint("LEFT", 0, 0)
    frame.rankManagementControls.label:SetText("Current rank")
    frame.rankManagementControls.dropdown = CreateFrame("Button", nil,
        frame.rankManagementControls, "BackdropTemplate")
    local rankDropdown = frame.rankManagementControls.dropdown
    rankDropdown:SetHeight(27)
    rankDropdown:SetPoint("LEFT", frame.rankManagementControls.label, "RIGHT", 10, 0)
    createBackdrop(rankDropdown, { 0.055, 0.045, 0.032, 0.98 }, { 0.46, 0.35, 0.18, 1 })
    rankDropdown.text = rankDropdown:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    rankDropdown.text:SetPoint("LEFT", 10, 0)
    rankDropdown.text:SetPoint("RIGHT", -30, 0)
    rankDropdown.text:SetJustifyH("LEFT")
    rankDropdown.arrow = rankDropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rankDropdown.arrow:SetPoint("RIGHT", -10, 0)
    rankDropdown.arrow:SetText("v")
    rankDropdown:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    rankDropdown.menu = CreateFrame("Frame", nil, rankDropdown, "BackdropTemplate")
    rankDropdown.menu:SetPoint("TOPLEFT", rankDropdown, "BOTTOMLEFT", 0, -2)
    rankDropdown.menu:SetPoint("TOPRIGHT", rankDropdown, "BOTTOMRIGHT", 0, -2)
    rankDropdown.menu:SetHeight(12)
    rankDropdown.menu:SetFrameStrata("FULLSCREEN_DIALOG")
    rankDropdown.menu:SetFrameLevel(frame:GetFrameLevel() + 45)
    rankDropdown.menu:SetClampedToScreen(true)
    rankDropdown.menu:SetToplevel(true)
    rankDropdown.menu:EnableMouse(true)
    rankDropdown.menu:EnableMouseWheel(true)
    rankDropdown.menu:SetScript("OnMouseDown", function() end)
    rankDropdown.menu:SetScript("OnMouseWheel", function() end)
    createBackdrop(rankDropdown.menu, { 0.025, 0.022, 0.018, 0.995 }, { 0.72, 0.45, 0.16, 1 })
    rankDropdown.menu.buttons = {}
    rankDropdown.menu:Hide()

    function rankDropdown:SetDisplay(text)
        self.text:SetText(text or "Choose a current rank")
    end

    function rankDropdown:Refresh(rankOptions, rankCounts)
        rankOptions, rankCounts = rankOptions or {}, rankCounts or {}
        self.menu:SetHeight(math.max(12, #rankOptions * 28 + 8))
        for index, rank in ipairs(rankOptions) do
            local button = self.menu.buttons[index]
            if not button then
                button = CreateFrame("Button", nil, self.menu, "BackdropTemplate")
                button:SetHeight(25)
                button:SetPoint("TOPLEFT", self.menu, "TOPLEFT", 5, -5 - (index - 1) * 28)
                button:SetPoint("TOPRIGHT", self.menu, "TOPRIGHT", -5, -5 - (index - 1) * 28)
                createBackdrop(button, { 0.06, 0.05, 0.038, 0.98 }, { 0.28, 0.23, 0.16, 0.9 })
                button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                button.text:SetPoint("LEFT", 9, 0)
                button.text:SetPoint("RIGHT", -9, 0)
                button.text:SetJustifyH("LEFT")
                button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                self.menu.buttons[index] = button
            end
            local rankIndex, rankName = rank.index, rank.name
            local count = tonumber(rankCounts[rankIndex]) or 0
            local rankLabel = rankName .. " (Rank " .. rankIndex .. ") - " .. count
                .. (count == 1 and " member" or " members")
            button.rankIndex = rankIndex
            button.rankLabel = rankLabel
            button.text:SetText(rankLabel)
            local selected = frame.rankManagementRank == rankIndex
            button:SetBackdropColor(selected and 0.19 or 0.06, selected and 0.11 or 0.05,
                selected and 0.035 or 0.038, 0.98)
            button:SetBackdropBorderColor(selected and COLORS.gold[1] or 0.28,
                selected and COLORS.gold[2] or 0.23, selected and COLORS.gold[3] or 0.16, 1)
            button:SetScript("OnClick", function(self)
                frame.rankManagementRank = self.rankIndex
                rankDropdown:SetDisplay(self.rankLabel)
                rankDropdown.menu:Hide()
                if frame.scroll then frame.scroll:SetVerticalScroll(0) end
                UI:Refresh()
            end)
            button:Show()
        end
        for index = #rankOptions + 1, #self.menu.buttons do self.menu.buttons[index]:Hide() end
    end

    rankDropdown:SetDisplay()
    rankDropdown:SetScript("OnClick", function(self)
        self.menu:SetShown(not self.menu:IsShown())
        if self.menu:IsShown() then self.menu:Raise() end
    end)
    frame.rankManagementControls.demote = makeIRCActionButton(frame.rankManagementControls, 145, 27,
        "Demote selected...", true)
    frame.rankManagementControls.demote:SetPoint("RIGHT", frame.rankManagementControls, "RIGHT", 0, 0)
    frame.rankManagementControls.promote = makeIRCActionButton(frame.rankManagementControls, 145, 27,
        "Promote selected...", false)
    frame.rankManagementControls.promote:SetPoint("RIGHT", frame.rankManagementControls.demote, "LEFT", -8, 0)
    rankDropdown:SetPoint("RIGHT", frame.rankManagementControls.promote, "LEFT", -12, 0)

    local function openRankManagementConfirm(action, onlyName)
        local rankIndex = frame.rankManagementRank
        if type(rankIndex) ~= "number" then
            iRC:Print(iRC.Colors.Yellow .. "Choose the current guild rank to manage first." .. iRC.Colors.Reset)
            return
        end
        local onlyKey = onlyName and iRC:NormalizeName(onlyName)
        local function findCandidates(testPreview)
            local result = getRankActionMembers(rankIndex, action, testPreview)
            if not onlyKey then return result end
            local filtered = {}
            for _, member in ipairs(result) do
                if iRC:NormalizeName(member.name) == onlyKey then filtered[1] = member break end
            end
            return filtered
        end
        local testPreview = iRC:IsTestAdmin() and not iRC:HasGuildPermission("rankManagement")
        local candidates = findCandidates(testPreview)
        if #candidates == 0 and iRC:IsTestAdmin() and not testPreview then
            testPreview = true
            candidates = findCandidates(true)
        end
        if #candidates == 0 then
            iRC:Print(iRC.Colors.Yellow .. (onlyName and "That member is no longer eligible for this action."
                or "No members at that rank are eligible for this action.") .. iRC.Colors.Reset)
            return
        end
        local verb = action == "PROMOTE" and "Promote" or "Demote"
        local decorated = {}
        for index, member in ipairs(candidates) do
            decorated[index] = {
                name = member.name, rankName = member.rankName, rankIndex = member.rankIndex,
                detail = tostring(member.rankName or ("Rank " .. rankIndex)) .. " · Level "
                    .. tostring(member.level or "?") .. " " .. tostring(member.className or ""),
            }
        end
        local confirm = frame.removeMemberConfirm
        confirm.removeAll = true
        confirm.rankAction = action
        confirm.sourceRank = rankIndex
        confirm.targetName = nil
        confirm.testPreview = testPreview
        confirm:SetBulkLayout(true)
        confirm:SetRankTargets(rankIndex, action, testPreview)
        confirm.bulkList:Show()
        confirm.title:SetText(onlyName and (verb .. " " .. iRC:FormatPlayerName(candidates[1].name) .. "?")
            or (verb .. " selected guild members?"))
        local body
        local actionWord = action == "PROMOTE" and "promotes" or "demotes"
        body = onlyName and ("Choose a target rank. Each secure click " .. actionWord
                .. " this member by one rank until the target is reached.")
            or ("Choose a target rank. Each secure click " .. actionWord
                .. " the confirmed members by one rank until the target is reached.")
        if testPreview then body = body .. "\n\nTest-admin preview: no guild ranks will be changed." end
        confirm.body:SetText(body)
        confirm.setBulkCandidates(decorated)
        confirm:Show()
        confirm:Raise()
    end
    frame.rankManagementControls.promote:SetScript("OnClick", function() openRankManagementConfirm("PROMOTE") end)
    frame.rankManagementControls.demote:SetScript("OnClick", function() openRankManagementConfirm("DEMOTE") end)
    frame.rankManagementControls:Hide()

    local rankMemberMenu = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    rankMemberMenu:SetSize(260, 120)
    rankMemberMenu:SetFrameStrata("DIALOG")
    rankMemberMenu:SetFrameLevel(frame:GetFrameLevel() + 35)
    rankMemberMenu:SetClampedToScreen(true)
    createBackdrop(rankMemberMenu, { 0.035, 0.028, 0.02, 0.99 },
        { COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 1 })
    rankMemberMenu.title = rankMemberMenu:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    rankMemberMenu.title:SetPoint("TOPLEFT", 14, -12)
    rankMemberMenu.title:SetPoint("TOPRIGHT", -34, -12)
    rankMemberMenu.title:SetJustifyH("LEFT")
    local rankMenuClose = CreateFrame("Button", nil, rankMemberMenu, "UIPanelCloseButton")
    rankMenuClose:SetPoint("TOPRIGHT", 4, 4)
    rankMemberMenu.promote = makeIRCActionButton(rankMemberMenu, 112, 29, "Promote", false)
    rankMemberMenu.promote:SetPoint("BOTTOMLEFT", rankMemberMenu, "BOTTOMLEFT", 14, 14)
    rankMemberMenu.demote = makeIRCActionButton(rankMemberMenu, 112, 29, "Demote", true)
    rankMemberMenu.demote:SetPoint("BOTTOMRIGHT", rankMemberMenu, "BOTTOMRIGHT", -14, 14)
    rankMemberMenu.promote:SetScript("OnClick", function()
        local name = rankMemberMenu.memberName
        rankMemberMenu:Hide()
        if name then openRankManagementConfirm("PROMOTE", name) end
    end)
    rankMemberMenu.demote:SetScript("OnClick", function()
        local name = rankMemberMenu.memberName
        rankMemberMenu:Hide()
        if name then openRankManagementConfirm("DEMOTE", name) end
    end)
    function rankMemberMenu:Open(member, owner, canPromote, canDemote, promotePreview, demotePreview)
        self.memberName = member and member.name
        self.title:SetText("Manage: " .. iRC:FormatPlayerName(self.memberName or ""))
        self.promote:SetText(promotePreview and "Preview promote" or "Promote")
        self.demote:SetText(demotePreview and "Preview demote" or "Demote")
        self.promote:SetEnabled(canPromote == true)
        self.promote:SetAlpha(canPromote and 1 or 0.42)
        self.demote:SetEnabled(canDemote == true)
        self.demote:SetAlpha(canDemote and 1 or 0.42)
        self:ClearAllPoints()
        self:SetPoint("TOP", frame.main, "TOP", 0, -72)
        self:Show()
        self:Raise()
    end
    rankMemberMenu:Hide()
    frame.rankMemberMenu = rankMemberMenu

    local scroll = CreateFrame("ScrollFrame", nil, main, "UIPanelScrollFrameTemplate")
    iRC:StyleScrollFrame(scroll)
    scroll:HookScript("OnVerticalScroll", function()
        if rankMemberMenu:IsShown() then rankMemberMenu:Hide() end
    end)
    scroll:SetPoint("TOPLEFT", main, "TOPLEFT", 15, -78)
    scroll:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -31, 14)
    frame.scroll = scroll
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(675)
    content:SetHeight(1)
    scroll:SetScrollChild(content)
    scroll:HookScript("OnVerticalScroll", function()
        if frame.category == "Guild Members" then UI:RenderMemberRows() end
    end)
    frame.scrollContent = content
    local professionReport = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    professionReport:SetSize(500, 520)
    professionReport:SetPoint("CENTER", frame, "CENTER", 0, 0)
    professionReport:SetFrameLevel(frame:GetFrameLevel() + 20)
    createBackdrop(professionReport, { 0.025, 0.022, 0.018, 1 }, { 0.75, 0.48, 0.13, 1 })
    professionReport.title = professionReport:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    professionReport.title:SetPoint("TOPLEFT", 16, -15)
    local reportClose = CreateFrame("Button", nil, professionReport, "UIPanelCloseButton")
    reportClose:SetPoint("TOPRIGHT", 2, 2)
    reportClose:SetScript("OnClick", function() professionReport:Hide() end)
    local reportScroll = CreateFrame("ScrollFrame", nil, professionReport, "UIPanelScrollFrameTemplate")
    iRC:StyleScrollFrame(reportScroll)
    reportScroll:SetPoint("TOPLEFT", 17, -48)
    reportScroll:SetPoint("BOTTOMRIGHT", -31, 17)
    local reportContent = CreateFrame("Frame", nil, reportScroll)
    reportContent:SetWidth(430)
    reportContent:SetHeight(1)
    reportScroll:SetScrollChild(reportContent)
    professionReport.text = reportContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    professionReport.text:SetPoint("TOPLEFT", 0, 0)
    professionReport.text:SetWidth(430)
    professionReport.text:SetJustifyH("LEFT")
    professionReport.text:SetJustifyV("TOP")
    professionReport.content = reportContent
    professionReport.scroll = reportScroll
    professionReport:Hide()
    frame.professionReport = professionReport
    local function showMemberProfile(profile)
        if not profile then return end
        local normalizedName = iRC:NormalizeName(profile.name)
        local rosterMember
        for _, member in ipairs(iRC:GetGuildRosterSnapshot()) do
            if iRC:NormalizeName(member.name) == normalizedName then rosterMember = member; break end
        end
        local history = iRC.Identity and iRC.Identity:GetMemberHistory(profile.name)
        local identityLabel = iRC.Identity and iRC.Identity:GetIdentityLabel(profile.name)
        local classFile = rosterMember and rosterMember.classFile or profile.class
        local classColor = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        professionReport.title:SetText(iRC:FormatPlayerName(profile.name))
        if classColor then
            professionReport.title:SetTextColor(classColor.r, classColor.g, classColor.b)
        else
            professionReport.title:SetTextColor(unpack(COLORS.gold))
        end
        local lines = {
            iRC.Colors.Orange .. "Character" .. iRC.Colors.Reset,
            "Level " .. tostring(profile.level or "?") .. " " .. tostring(profile.race or "Unknown")
                .. " " .. tostring(rosterMember and rosterMember.className or profile.class or "Unknown"),
            "Guild rank: " .. tostring(rosterMember and rosterMember.rankName or "Unknown"),
            profile.online and (iRC.Colors.Green .. "Online" .. iRC.Colors.Reset)
                or "Last online: " .. (profile.lastOnlineDays and string.format("%.1f days ago", profile.lastOnlineDays) or "Unknown"),
        }
        if identityLabel then lines[#lines + 1] = "Identity: " .. identityLabel end
        if iRC.Identity then
            local linked = iRC.Identity:GetLinkedCharacters(profile.name)
            if #linked > 0 then lines[#lines + 1] = "Linked characters: " .. table.concat(linked, ", ") end
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = iRC.Colors.Orange .. "Membership" .. iRC.Colors.Reset
        lines[#lines + 1] = "First observed: " .. (history and history.firstSeenAt and date("%Y-%m-%d %H:%M", history.firstSeenAt) or "Not recorded")
        if history and history.joinedAt then lines[#lines + 1] = "Joined: " .. date("%Y-%m-%d %H:%M", history.joinedAt) end
        if history and history.rejoinedAt then lines[#lines + 1] = "Last rejoined: " .. date("%Y-%m-%d %H:%M", history.rejoinedAt) end
        lines[#lines + 1] = "Public note: " .. ((rosterMember and rosterMember.publicNote ~= "" and rosterMember.publicNote) or "None")
        lines[#lines + 1] = "Officer note: " .. ((rosterMember and rosterMember.officerNote ~= "" and rosterMember.officerNote) or "None or unavailable")
        local rankHistory = history and history.rankHistory or {}
        if #rankHistory > 0 then
            lines[#lines + 1] = ""
            lines[#lines + 1] = iRC.Colors.Orange .. "Rank history" .. iRC.Colors.Reset
            for index = #rankHistory, math.max(1, #rankHistory - 7), -1 do
                local change = rankHistory[index]
                lines[#lines + 1] = date("%Y-%m-%d %H:%M", change.changedAt) .. " - "
                    .. tostring(change.fromRank) .. " to " .. tostring(change.toRank)
            end
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = iRC.Colors.Orange .. "Professions" .. iRC.Colors.Reset
        local professionLines = {}
        for _, option in ipairs(iRC.Professions:GetOptions()) do
            local rank = profile.professionData and profile.professionData.skills
                and profile.professionData.skills[option[1]]
            if rank then professionLines[#professionLines + 1] = option[2] .. " (" .. tostring(rank) .. ")" end
        end
        if #professionLines > 0 then
            lines[#lines + 1] = table.concat(professionLines, ", ")
        else
            lines[#lines + 1] = "No profession data received from this member."
        end
        local activity = iRC.Identity and iRC.Identity:GetMemberActivity(profile.name, 8) or {}
        lines[#lines + 1] = ""
        lines[#lines + 1] = iRC.Colors.Orange .. "Recent guild activity" .. iRC.Colors.Reset
        if #activity > 0 then
            for _, record in ipairs(activity) do
                lines[#lines + 1] = date("%Y-%m-%d %H:%M", record.occurredAt) .. " ["
                    .. tostring(record.eventType):gsub("_", " ") .. "] " .. tostring(record.text or "")
            end
        else
            lines[#lines + 1] = "No recorded guild activity."
        end
        professionReport.text:SetText(table.concat(lines, "\n"))
        professionReport.content:SetHeight(math.max(1, professionReport.text:GetStringHeight() + 12))
        professionReport.scroll:SetVerticalScroll(0)
        professionReport:Show()
        professionReport:Raise()
    end
    frame.showMemberProfile = showMemberProfile
    local MEMBER_MENU_TONES = {
        detail = COLORS.gold,
        contact = { 0.35, 0.72, 1.00 },
        character = COLORS.green,
        bank = { 0.40, 0.80, 1.00 },
        danger = { 1.00, 0.50, 0.50 },
        disabled = { 0.45, 0.45, 0.45 },
    }
    local function styleMemberMenuButton(button, tone, enabled)
        enabled = enabled ~= false
        local color = enabled and (MEMBER_MENU_TONES[tone] or COLORS.gold) or MEMBER_MENU_TONES.disabled
        button:SetEnabled(enabled)
        button:SetAlpha(enabled and 1 or 0.48)
        button:SetBackdropColor(enabled and 0.07 or 0.035, enabled and 0.055 or 0.035, enabled and 0.04 or 0.035, 0.98)
        button:SetBackdropBorderColor(color[1], color[2], color[3], enabled and 0.90 or 0.55)
        button.text:SetTextColor(color[1], color[2], color[3])
        if button.arrow then button.arrow:SetTextColor(color[1], color[2], color[3]) end
    end
    frame.styleMemberMenuButton = styleMemberMenuButton

    local assignAltPopup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    assignAltPopup:SetSize(440, 330)
    assignAltPopup:SetPoint("CENTER", frame, "CENTER", 0, 20)
    assignAltPopup:SetFrameStrata("FULLSCREEN_DIALOG")
    assignAltPopup:SetToplevel(true)
    assignAltPopup:EnableMouse(true)
    createBackdrop(assignAltPopup, { 0.025, 0.022, 0.018, 1 }, { COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 1 })

    assignAltPopup.title = assignAltPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    assignAltPopup.title:SetPoint("TOPLEFT", 22, -20)
    assignAltPopup.title:SetText("Assign Alt to Main")
    assignAltPopup.title:SetTextColor(unpack(COLORS.gold))
    assignAltPopup.body = assignAltPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    assignAltPopup.body:SetPoint("TOPLEFT", assignAltPopup.title, "BOTTOMLEFT", 0, -13)
    assignAltPopup.body:SetPoint("TOPRIGHT", assignAltPopup, "TOPRIGHT", -22, -52)
    assignAltPopup.body:SetJustifyH("LEFT")
    assignAltPopup.body:SetWordWrap(true)

    assignAltPopup.searchLabel = assignAltPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    assignAltPopup.searchLabel:SetPoint("TOPLEFT", assignAltPopup, "TOPLEFT", 22, -91)
    assignAltPopup.searchLabel:SetText("Search guild roster")
    assignAltPopup.searchLabel:SetTextColor(unpack(COLORS.gold))
    assignAltPopup.search = CreateFrame("EditBox", nil, assignAltPopup, "BackdropTemplate")
    assignAltPopup.search:SetPoint("TOPLEFT", assignAltPopup, "TOPLEFT", 22, -107)
    assignAltPopup.search:SetPoint("TOPRIGHT", assignAltPopup, "TOPRIGHT", -22, -107)
    assignAltPopup.search:SetHeight(30)
    assignAltPopup.search:SetAutoFocus(false)
    assignAltPopup.search:SetMaxLetters(80)
    assignAltPopup.search:SetFontObject(GameFontHighlight)
    assignAltPopup.search:SetTextInsets(9, 9, 0, 0)
    createBackdrop(assignAltPopup.search, { 0.025, 0.025, 0.025, 1 }, { 0.48, 0.35, 0.16, 1 })
    assignAltPopup.searchHint = assignAltPopup.search:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    assignAltPopup.searchHint:SetPoint("LEFT", assignAltPopup.search, "LEFT", 9, 0)
    assignAltPopup.searchHint:SetText("Type a character name...")

    assignAltPopup.suggestions = CreateFrame("Frame", nil, assignAltPopup, "BackdropTemplate")
    assignAltPopup.suggestions:SetPoint("TOPLEFT", assignAltPopup.search, "BOTTOMLEFT", 0, -3)
    assignAltPopup.suggestions:SetPoint("TOPRIGHT", assignAltPopup.search, "BOTTOMRIGHT", 0, -3)
    assignAltPopup.suggestions:SetHeight(128)
    assignAltPopup.suggestions:SetFrameStrata("FULLSCREEN_DIALOG")
    assignAltPopup.suggestions:SetFrameLevel(assignAltPopup:GetFrameLevel() + 10)
    createBackdrop(assignAltPopup.suggestions, { 0.025, 0.022, 0.018, 1 }, { COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 0.9 })
    assignAltPopup.suggestionButtons = {}

    local function selectAssignCandidate(member)
        if not member then return end
        assignAltPopup.selectedMain = member.name
        assignAltPopup.search.settingSelection = true
        assignAltPopup.search:SetText(iRC:FormatPlayerName(member.name))
        assignAltPopup.search.settingSelection = nil
        assignAltPopup.searchHint:Hide()
        assignAltPopup.suggestions:Hide()
        assignAltPopup.accept:SetEnabled(true)
        assignAltPopup.accept:SetAlpha(1)
    end

    local function updateAssignSuggestions()
        local query = assignAltPopup.search:GetText():lower():gsub("^%s+", ""):gsub("%s+$", "")
        local matches = {}
        if query ~= "" then
            for _, member in ipairs(assignAltPopup.candidates or {}) do
                local displayName = iRC:FormatPlayerName(member.name)
                local position = displayName:lower():find(query, 1, true)
                if position then matches[#matches + 1] = { member = member, starts = position == 1 } end
            end
            table.sort(matches, function(a, b)
                if a.starts ~= b.starts then return a.starts end
                return iRC:NormalizeName(a.member.name) < iRC:NormalizeName(b.member.name)
            end)
        end
        for index, button in ipairs(assignAltPopup.suggestionButtons) do
            local match = matches[index]
            button.member = match and match.member or nil
            button:SetShown(match ~= nil)
            if match then
                local member = match.member
                local detail = tostring(member.rankName or "Guild member")
                    .. " - Level " .. tostring(member.level or "?") .. " " .. tostring(member.className or member.class or "")
                button.text:SetText(iRC:FormatPlayerName(member.name) .. "  |cFF888888" .. detail .. "|r")
            end
        end
        assignAltPopup.suggestions:SetShown(query ~= "" and matches[1] ~= nil and assignAltPopup.search:HasFocus())
    end

    for index = 1, 5 do
        local button = CreateFrame("Button", nil, assignAltPopup.suggestions)
        button:SetPoint("TOPLEFT", assignAltPopup.suggestions, "TOPLEFT", 7, -6 - (index - 1) * 23)
        button:SetPoint("TOPRIGHT", assignAltPopup.suggestions, "TOPRIGHT", -7, -6 - (index - 1) * 23)
        button:SetHeight(23)
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        button.text:SetPoint("LEFT", button, "LEFT", 7, 0)
        button.text:SetPoint("RIGHT", button, "RIGHT", -7, 0)
        button.text:SetJustifyH("LEFT")
        button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
        button.highlight:SetAllPoints()
        button.highlight:SetColorTexture(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 0.18)
        button:SetScript("OnClick", function(self) selectAssignCandidate(self.member) end)
        assignAltPopup.suggestionButtons[index] = button
    end

    local function makeAssignPopupButton(text, width)
        local button = CreateFrame("Button", nil, assignAltPopup, "BackdropTemplate")
        button:SetSize(width, 28)
        createBackdrop(button, { 0.08, 0.06, 0.04, 1 }, { 0.48, 0.35, 0.16, 1 })
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        button.text:SetPoint("CENTER")
        button.text:SetText(text)
        button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
        button.highlight:SetAllPoints()
        button.highlight:SetColorTexture(1, 0.72, 0.22, 0.12)
        return button
    end

    assignAltPopup.cancel = makeAssignPopupButton("Cancel", 110)
    assignAltPopup.cancel:SetPoint("BOTTOMRIGHT", assignAltPopup, "BOTTOMRIGHT", -22, 18)
    assignAltPopup.cancel:SetScript("OnClick", function() assignAltPopup:Hide() end)
    assignAltPopup.accept = makeAssignPopupButton("Assign Alt", 130)
    assignAltPopup.accept:SetPoint("RIGHT", assignAltPopup.cancel, "LEFT", -10, 0)
    assignAltPopup.accept:SetScript("OnClick", function()
        local targetName, mainName = assignAltPopup.targetName, assignAltPopup.selectedMain
        if not targetName or not mainName or not iRC.Identity
            or not iRC.Identity:AssignGuildCharacter(targetName, mainName, "ALT") then
            iRC:Print("Could not assign the Alt. Both characters must be current guild members.")
            return
        end
        assignAltPopup:Hide()
        iRC:Print(iRC:FormatPlayerName(targetName) .. " assigned as an Alt of " .. iRC:FormatPlayerName(mainName) .. ".")
        UI:RefreshIfShown()
    end)

    assignAltPopup.search:SetScript("OnTextChanged", function(self)
        assignAltPopup.searchHint:SetShown(self:GetText() == "")
        if self.settingSelection then return end
        assignAltPopup.selectedMain = nil
        local queryKey = iRC:NormalizeName(self:GetText())
        if queryKey ~= "" then
            for _, member in ipairs(assignAltPopup.candidates or {}) do
                if iRC:NormalizeName(member.name) == queryKey then
                    assignAltPopup.selectedMain = member.name
                    break
                end
            end
        end
        assignAltPopup.accept:SetEnabled(assignAltPopup.selectedMain ~= nil)
        assignAltPopup.accept:SetAlpha(assignAltPopup.selectedMain and 1 or 0.42)
        updateAssignSuggestions()
    end)
    assignAltPopup.search:SetScript("OnEditFocusGained", updateAssignSuggestions)
    assignAltPopup.search:SetScript("OnEditFocusLost", function(self)
        C_Timer.After(0, function()
            if not self:HasFocus() and not iRC:IsMouseOverFrame(assignAltPopup.suggestions) then
                assignAltPopup.suggestions:Hide()
            end
        end)
    end)
    assignAltPopup.search:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        assignAltPopup.suggestions:Hide()
    end)
    assignAltPopup.search:SetScript("OnEnterPressed", function(self)
        local first = assignAltPopup.suggestionButtons[1]
        if first.member and assignAltPopup.suggestions:IsShown() then
            first:Click()
        elseif assignAltPopup.selectedMain then
            self:ClearFocus()
        end
    end)

    function assignAltPopup:Open(targetName)
        self.targetName = targetName
        self.selectedMain = nil
        self.candidates = {}
        local targetKey = iRC:NormalizeName(targetName)
        for _, member in ipairs(iRC:GetGuildRosterSnapshot()) do
            if iRC:NormalizeName(member.name) ~= targetKey then
                self.candidates[#self.candidates + 1] = member
            end
        end
        table.sort(self.candidates, function(a, b)
            return iRC:NormalizeName(a.name) < iRC:NormalizeName(b.name)
        end)
        local existing = iRC.Identity and iRC.Identity:GetManagedAssignment(targetName)
        if existing and existing.mainName and iRC:IsGuildMemberName(existing.mainName) then
            self.selectedMain = existing.mainName
        end
        self.body:SetText("Choose the Main character for " .. iRC:FormatPlayerName(targetName) .. ".")
        self.search.settingSelection = true
        self.search:SetText(self.selectedMain and iRC:FormatPlayerName(self.selectedMain) or "")
        self.search.settingSelection = nil
        self.searchHint:SetShown(self.selectedMain == nil)
        self.suggestions:Hide()
        self.accept:SetEnabled(self.selectedMain ~= nil)
        self.accept:SetAlpha(self.selectedMain and 1 or 0.42)
        self:Show()
        self:Raise()
        self.search:SetFocus()
    end

    assignAltPopup:SetScript("OnHide", function(self)
        self.search:ClearFocus()
        self.suggestions:Hide()
    end)
    assignAltPopup:Hide()
    frame.assignAltPopup = assignAltPopup
    local memberMenu = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    memberMenu:SetSize(270, 214)
    memberMenu:SetFrameStrata("DIALOG")
    memberMenu:SetFrameLevel(frame:GetFrameLevel() + 30)
    memberMenu:SetClampedToScreen(true)
    createBackdrop(memberMenu, { 0.035, 0.028, 0.02, 0.99 }, { COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 1 })
    memberMenu.title = memberMenu:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    memberMenu.title:SetPoint("TOPLEFT", 14, -10)
    memberMenu.title:SetPoint("TOPRIGHT", -34, -10)
    memberMenu.title:SetJustifyH("LEFT")
    local menuClose = CreateFrame("Button", nil, memberMenu, "UIPanelCloseButton")
    menuClose:SetPoint("TOPRIGHT", 4, 4)
    memberMenu.detailLabel = memberMenu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    memberMenu.detailLabel:SetPoint("TOPLEFT", 18, -43)
    memberMenu.detailLabel:SetText("Details")
    memberMenu.detailLabel:SetTextColor(unpack(COLORS.gold))
    memberMenu.view = CreateFrame("Button", nil, memberMenu, "BackdropTemplate")
    memberMenu.view:SetSize(238, 29)
    memberMenu.view:SetPoint("TOPLEFT", 16, -59)
    createBackdrop(memberMenu.view, { 0.07, 0.055, 0.04, 0.98 }, { 0.30, 0.24, 0.16, 1 })
    memberMenu.view.text = memberMenu.view:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    memberMenu.view.text:SetPoint("LEFT", 12, 0)
    memberMenu.view.text:SetText("View member profile")
    memberMenu.view:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    styleMemberMenuButton(memberMenu.view, "detail", true)
    memberMenu.view:SetScript("OnClick", function()
        local profile = memberMenu.profile
        memberMenu:Hide()
        if not profile then return end
        showMemberProfile(profile)
    end)
    memberMenu.whisper = CreateFrame("Button", nil, memberMenu, "BackdropTemplate")
    memberMenu.contactLabel = memberMenu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    memberMenu.contactLabel:SetPoint("TOPLEFT", 18, -96)
    memberMenu.contactLabel:SetText("Contact")
    memberMenu.contactLabel:SetTextColor(unpack(COLORS.gold))
    memberMenu.whisper:SetSize(238, 29)
    memberMenu.whisper:SetPoint("TOPLEFT", 16, -112)
    createBackdrop(memberMenu.whisper, { 0.07, 0.055, 0.04, 0.98 }, { 0.30, 0.24, 0.16, 1 })
    memberMenu.whisper.text = memberMenu.whisper:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    memberMenu.whisper.text:SetPoint("LEFT", 12, 0)
    memberMenu.whisper.text:SetText("Whisper")
    memberMenu.whisper:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    styleMemberMenuButton(memberMenu.whisper, "contact", true)
    memberMenu.whisper:SetScript("OnClick", function()
        local profile = memberMenu.profile
        memberMenu:Hide()
        if profile then iRC:OpenWhisper(profile.name) end
    end)
    memberMenu.alts = CreateFrame("Button", nil, memberMenu, "BackdropTemplate")
    memberMenu.characterLabel = memberMenu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    memberMenu.characterLabel:SetPoint("TOPLEFT", 18, -149)
    memberMenu.characterLabel:SetText("My characters")
    memberMenu.characterLabel:SetTextColor(unpack(COLORS.gold))
    memberMenu.alts:SetSize(238, 29)
    memberMenu.alts:SetPoint("TOPLEFT", 16, -165)
    createBackdrop(memberMenu.alts, { 0.07, 0.055, 0.04, 0.98 }, { 0.30, 0.24, 0.16, 1 })
    memberMenu.alts.text = memberMenu.alts:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    memberMenu.alts.text:SetPoint("LEFT", 12, 0)
    memberMenu.alts.text:SetText("Main, Alts & Personal Bank")
    memberMenu.alts.arrow = memberMenu.alts:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    memberMenu.alts.arrow:SetPoint("RIGHT", -12, 0)
    memberMenu.alts.arrow:SetText(">")
    memberMenu.alts:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    styleMemberMenuButton(memberMenu.alts, "character", true)

    memberMenu.altMenu = CreateFrame("Frame", nil, memberMenu, "BackdropTemplate")
    memberMenu.altMenu:SetSize(220, 148)
    memberMenu.altMenu:SetPoint("TOPLEFT", memberMenu, "TOPRIGHT", 3, -149)
    memberMenu.altMenu:SetFrameLevel(memberMenu:GetFrameLevel() + 5)
    memberMenu.altMenu:SetClampedToScreen(true)
    createBackdrop(memberMenu.altMenu, { 0.035, 0.028, 0.02, 0.99 }, { COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 1 })
    memberMenu.altMenu.add = CreateFrame("Button", nil, memberMenu.altMenu, "BackdropTemplate")
    memberMenu.altMenu.add:SetSize(194, 29)
    memberMenu.altMenu.add:SetPoint("TOPLEFT", 13, -10)
    createBackdrop(memberMenu.altMenu.add, { 0.07, 0.055, 0.04, 0.98 }, { 0.30, 0.24, 0.16, 1 })
    memberMenu.altMenu.add.text = memberMenu.altMenu.add:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    memberMenu.altMenu.add.text:SetPoint("LEFT", 10, 0)
    memberMenu.altMenu.add.text:SetText("Add to my characters")
    memberMenu.altMenu.add:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    styleMemberMenuButton(memberMenu.altMenu.add, "character", true)
    memberMenu.altMenu.add:SetScript("OnClick", function()
        local profile = memberMenu.profile
        memberMenu:Hide()
        if not profile or not iRC.Identity then return end
        iRC.Identity:RegisterCharacter(profile.name)
        UI:RefreshIfShown()
    end)
    memberMenu.altMenu.main = CreateFrame("Button", nil, memberMenu.altMenu, "BackdropTemplate")
    memberMenu.altMenu.main:SetSize(194, 29)
    memberMenu.altMenu.main:SetPoint("TOPLEFT", 13, -43)
    createBackdrop(memberMenu.altMenu.main, { 0.07, 0.055, 0.04, 0.98 }, { 0.30, 0.24, 0.16, 1 })
    memberMenu.altMenu.main.text = memberMenu.altMenu.main:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    memberMenu.altMenu.main.text:SetPoint("LEFT", 10, 0)
    memberMenu.altMenu.main.text:SetText("Set as my Main")
    memberMenu.altMenu.main:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    styleMemberMenuButton(memberMenu.altMenu.main, "detail", true)
    memberMenu.altMenu.main:SetScript("OnClick", function()
        local profile = memberMenu.profile
        memberMenu:Hide()
        if profile and iRC.Identity then
            iRC.Identity:ConfirmCurrentCharacterForMain(profile.name)
            UI:RefreshIfShown()
        end
    end)
    memberMenu.altMenu.bank = CreateFrame("Button", nil, memberMenu.altMenu, "BackdropTemplate")
    memberMenu.altMenu.bank:SetSize(194, 29)
    memberMenu.altMenu.bank:SetPoint("TOPLEFT", 13, -76)
    createBackdrop(memberMenu.altMenu.bank, { 0.07, 0.055, 0.04, 0.98 }, { 0.30, 0.24, 0.16, 1 })
    memberMenu.altMenu.bank.text = memberMenu.altMenu.bank:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    memberMenu.altMenu.bank.text:SetPoint("LEFT", 10, 0)
    memberMenu.altMenu.bank:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    styleMemberMenuButton(memberMenu.altMenu.bank, "bank", true)
    memberMenu.altMenu.bank:SetScript("OnClick", function()
        local profile = memberMenu.profile
        memberMenu:Hide()
        if profile and iRC.Identity then
            local enabled = not iRC.Identity:IsPersonalBank(profile.name)
            iRC.Identity:RegisterCharacter(profile.name, enabled and "BANK" or "ALT")
            iRC.Identity:SetPersonalBank(profile.name, enabled)
            UI:RefreshIfShown()
        end
    end)
    memberMenu.altMenu.remove = CreateFrame("Button", nil, memberMenu.altMenu, "BackdropTemplate")
    memberMenu.altMenu.remove:SetSize(194, 29)
    memberMenu.altMenu.remove:SetPoint("TOPLEFT", 13, -109)
    createBackdrop(memberMenu.altMenu.remove, { 0.07, 0.055, 0.04, 0.98 }, { 0.30, 0.24, 0.16, 1 })
    memberMenu.altMenu.remove.text = memberMenu.altMenu.remove:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    memberMenu.altMenu.remove.text:SetPoint("LEFT", 10, 0)
    memberMenu.altMenu.remove.text:SetText("Remove Alt")
    memberMenu.altMenu.remove:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    styleMemberMenuButton(memberMenu.altMenu.remove, "danger", true)
    memberMenu.altMenu.remove:SetScript("OnClick", function()
        local profile = memberMenu.profile
        memberMenu:Hide()
        if profile and iRC.Identity then
            iRC.Identity:RemoveCharacter(profile.name)
            UI:RefreshIfShown()
        end
    end)
    memberMenu.altMenu:Hide()
    memberMenu.alts:SetScript("OnClick", function()
        memberMenu.altMenu:SetShown(not memberMenu.altMenu:IsShown())
    end)

    memberMenu.identityLabel = memberMenu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    memberMenu.identityLabel:SetPoint("TOPLEFT", 18, -202)
    memberMenu.identityLabel:SetText("Guild identity management")
    memberMenu.identityLabel:SetTextColor(unpack(COLORS.gold))

    memberMenu.assignAlt = CreateFrame("Button", nil, memberMenu, "BackdropTemplate")
    memberMenu.assignAlt:SetSize(154, 29)
    memberMenu.assignAlt:SetPoint("TOPLEFT", 16, -218)
    createBackdrop(memberMenu.assignAlt, { 0.07, 0.055, 0.04, 0.98 }, { 0.30, 0.24, 0.16, 1 })
    memberMenu.assignAlt.text = memberMenu.assignAlt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    memberMenu.assignAlt.text:SetPoint("CENTER")
    memberMenu.assignAlt.text:SetText("Assign Alt to Main...")
    memberMenu.assignAlt:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    styleMemberMenuButton(memberMenu.assignAlt, "character", true)
    memberMenu.assignAlt:SetScript("OnClick", function()
        local profile = memberMenu.profile
        memberMenu:Hide()
        if not profile or not iRC.Identity then return end
        assignAltPopup:Open(profile.name)
    end)

    memberMenu.clearIdentity = CreateFrame("Button", nil, memberMenu, "BackdropTemplate")
    memberMenu.clearIdentity:SetSize(80, 29)
    memberMenu.clearIdentity:SetPoint("LEFT", memberMenu.assignAlt, "RIGHT", 4, 0)
    createBackdrop(memberMenu.clearIdentity, { 0.07, 0.055, 0.04, 0.98 }, { 0.30, 0.24, 0.16, 1 })
    memberMenu.clearIdentity.text = memberMenu.clearIdentity:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    memberMenu.clearIdentity.text:SetPoint("CENTER")
    memberMenu.clearIdentity.text:SetText("Clear Link")
    memberMenu.clearIdentity:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    styleMemberMenuButton(memberMenu.clearIdentity, "danger", false)
    memberMenu.clearIdentity:SetScript("OnClick", function()
        local profile = memberMenu.profile
        memberMenu:Hide()
        if not profile or not iRC.Identity then return end
        StaticPopupDialogs.IRC_CLEAR_MEMBER_IDENTITY = StaticPopupDialogs.IRC_CLEAR_MEMBER_IDENTITY or {
            text = "Clear the managed Main/Alt link for %s?",
            button1 = YES or "Yes", button2 = NO or "No",
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
            OnAccept = function(_, data)
                if data and iRC.Identity:AssignGuildCharacter(data.target, nil, "REMOVE") then
                    iRC:Print("Cleared the managed identity link for " .. iRC:FormatPlayerName(data.target) .. ".")
                end
            end,
        }
        StaticPopup_Show("IRC_CLEAR_MEMBER_IDENTITY", iRC:FormatPlayerName(profile.name), nil, { target = profile.name })
    end)
    memberMenu.identityLabel:Hide()
    memberMenu.assignAlt:Hide()
    memberMenu.clearIdentity:Hide()
    memberMenu:Hide()
    frame.memberMenu = memberMenu
    frame:HookScript("OnHide", function()
        resetInactiveMemberView(frame)
        memberMenu:Hide()
        rankMemberMenu:Hide()
        professionReport:Hide()
        disableConfirm:Hide()
        assignAltPopup:Hide()
        removeMemberConfirm:Hide()
        removalQueue:Cancel()
        if iRC.ConnectionDashboard and iRC.ConnectionDashboard.HideEmbedded then
            iRC.ConnectionDashboard:HideEmbedded()
        end
    end)
    local outsideClickWatcher = CreateFrame("Frame")
    outsideClickWatcher:RegisterEvent("GLOBAL_MOUSE_DOWN")
    outsideClickWatcher:SetScript("OnEvent", function()
        local professionSearch = frame.memberProfessionSearch
        if frame:IsShown() and frame.category == "Guild Members" and professionSearch.edit:HasFocus()
            and not iRC:IsMouseOverFrame(professionSearch.edit) and not iRC:IsMouseOverFrame(professionSearch.suggestions) then
            professionSearch.edit:ClearFocus()
        end
        if frame:IsShown() and frame.category == "Guild Log" and frame.guildLogSearch:HasFocus()
            and not iRC:IsMouseOverFrame(frame.guildLogSearch)
            and not iRC:IsMouseOverFrame(frame.guildLogSearch.suggestions) then
            frame.guildLogSearch:ClearFocus()
        end
        if memberMenu:IsShown() and not iRC:IsMouseOverFrame(memberMenu) and not iRC:IsMouseOverFrame(memberMenu.altMenu) then memberMenu:Hide() end
        if rankMemberMenu:IsShown() and not iRC:IsMouseOverFrame(rankMemberMenu) then rankMemberMenu:Hide() end
        if rankDropdown.menu:IsShown() and not iRC:IsMouseOverFrame(rankDropdown)
            and not iRC:IsMouseOverFrame(rankDropdown.menu) then rankDropdown.menu:Hide() end
        if excludeRankDropdown.menu:IsShown() and not iRC:IsMouseOverFrame(excludeRankDropdown)
            and not iRC:IsMouseOverFrame(excludeRankDropdown.menu) then excludeRankDropdown.menu:Hide() end
        if rankTargetDropdown.menu:IsShown() and not iRC:IsMouseOverFrame(rankTargetDropdown)
            and not iRC:IsMouseOverFrame(rankTargetDropdown.menu) then rankTargetDropdown.menu:Hide() end
        if professionReport:IsShown() and not iRC:IsMouseOverFrame(professionReport) then professionReport:Hide() end
    end)
    frame.memberRows, frame.memberData, frame.raceCards, frame.factionSections = {}, {}, {}, {}
    frame.racePodium = makeRacePodium(content)
    frame.racePodium:Hide()
    frame.category = "Race Overview"
    return frame
end

local function ensurePersonalSettings(frame)
    if frame.personalSettings then return frame.personalSettings end

    local page = CreateFrame("Frame", nil, frame.scrollContent)
    page:SetSize(675, 806)
    page:SetPoint("TOPLEFT")
    page.controls = {}

    local function makeCard(y, height, title)
        local card = CreateFrame("Frame", nil, page, "BackdropTemplate")
        card:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
        card:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -y)
        card:SetHeight(height)
        createBackdrop(card, { 0.07, 0.055, 0.038, 0.96 }, { 0.34, 0.27, 0.17, 1 })
        card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        card.title:SetPoint("TOPLEFT", 14, -11)
        card.title:SetText(title)
        card.title:SetTextColor(unpack(COLORS.gold))
        return card
    end

    local function makeToggle(card, y, label, description, getter, setter)
        local title = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOPLEFT", 16, y)
        title:SetText(label)
        local detail = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        detail:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
        detail:SetPoint("RIGHT", card, "RIGHT", -135, 0)
        detail:SetJustifyH("LEFT")
        detail:SetText(description)
        local button = makeIRCActionButton(card, 102, 26, "", false)
        button:SetPoint("TOPRIGHT", card, "TOPRIGHT", -15, y + 5)
        button:SetScript("OnClick", function()
            setter(not getter())
            UI:Refresh()
        end)
        button.Refresh = function(self)
            local enabled = getter() == true
            self:SetText(enabled and "Enabled" or "Disabled")
            self:SetBackdropColor(enabled and 0.12 or 0.055, enabled and 0.10 or 0.045,
                enabled and 0.035 or 0.035, 0.98)
            self:SetBackdropBorderColor(enabled and COLORS.gold[1] or 0.28,
                enabled and COLORS.gold[2] or 0.23, enabled and COLORS.gold[3] or 0.16, 1)
        end
        page.controls[#page.controls + 1] = button
        return button
    end

    local identityCard = makeCard(0, 102, "Personal Characters")
    local identityDescription = identityCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    identityDescription:SetPoint("TOPLEFT", 16, -35)
    identityDescription:SetText("Choose which of your registered guild characters is treated as your Main.")
    local mainLabel = identityCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    mainLabel:SetPoint("TOPLEFT", 16, -62)
    mainLabel:SetText("Main character")
    local mainDropdown = CreateFrame("Frame", "iRCPanelPersonalMainDropdown", identityCard, "UIDropDownMenuTemplate")
    mainDropdown:SetPoint("LEFT", mainLabel, "RIGHT", 14, -2)
    UIDropDownMenu_SetWidth(mainDropdown, 235)
    UIDropDownMenu_Initialize(mainDropdown, function(_, level)
        if level ~= 1 then return end
        if iRC.Identity then iRC.Identity:RegisterCharacter(iRC:GetPlayerName()) end
        for _, character in ipairs(iRC.Identity and iRC.Identity:GetCharacters() or {}) do
            local name = character.name
            local info = UIDropDownMenu_CreateInfo()
            info.text = iRC:FormatPlayerName(name)
            info.value = name
            info.checked = iRC.Identity and iRC.Identity:GetMainName() == name
            info.func = function()
                if iRC.Identity then iRC.Identity:SetMain(name) end
                UI:Refresh()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    page.mainDropdown = mainDropdown

    local startupCard = makeCard(112, 96, "Panel Startup")
    local startupDescription = startupCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    startupDescription:SetPoint("TOPLEFT", 16, -35)
    startupDescription:SetText("Choose which page opens when you launch iRC normally.")
    local startupLabel = startupCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    startupLabel:SetPoint("TOPLEFT", 16, -64)
    startupLabel:SetText("Opening page")
    local startupDropdown = CreateFrame("Frame", "iRCPanelStartupPageDropdown", startupCard, "UIDropDownMenuTemplate")
    startupDropdown:SetPoint("LEFT", startupLabel, "RIGHT", 14, -2)
    UIDropDownMenu_SetWidth(startupDropdown, 235)
    UIDropDownMenu_JustifyText(startupDropdown, "LEFT")
    UIDropDownMenu_Initialize(startupDropdown, function(_, level)
        if level ~= 1 then return end
        local function addChoice(value, label)
            local info = UIDropDownMenu_CreateInfo()
            info.text = label
            info.value = value
            info.checked = iRC:GetSettings().mainPanelDefaultTab == value
            info.func = function()
                iRC:GetSettings().mainPanelDefaultTab = value
                UIDropDownMenu_SetSelectedValue(startupDropdown, value)
                UIDropDownMenu_SetText(startupDropdown, label)
            end
            UIDropDownMenu_AddButton(info, level)
        end
        addChoice(DEFAULT_OPEN_LAST, getNavigationLabel(DEFAULT_OPEN_LAST))
        for _, item in ipairs(MAIN_NAVIGATION) do
            local tab = not item.header and frame.tabs[item.id]
            if tab and tab:IsShown() and not tab.unavailable then addChoice(item.id, item.label) end
        end
    end)
    page.startupDropdown = startupDropdown

    local visibilityCard = makeCard(218, 184, "Visibility & Chat")
    makeToggle(visibilityCard, -38, "Show minimap button", "Show the iRC launcher beside the minimap.",
        function() return not iRC:GetSettings().minimapButton.hide end,
        function(value)
            iRC:GetSettings().minimapButton.hide = not value
            if iRC.Minimap then iRC.Minimap:UpdateVisibility() end
        end)
    makeToggle(visibilityCard, -87, iRC:Text("HIDE_MY_CHAT_ICON"), iRC:Text("HIDE_MY_CHAT_ICON_DESC"),
        function() return iRCCharDB and iRCCharDB.hideChatIcon == true end,
        function(value)
            if iRC.GuildAnnouncements then iRC.GuildAnnouncements:SetHidden(value) end
        end)
    makeToggle(visibilityCard, -136, iRC:Text("HIDE_ALL_CHAT_ICONS"), iRC:Text("HIDE_ALL_CHAT_ICONS_DESC"),
        function() return iRCCharDB and iRCCharDB.hideAllChatIcons == true end,
        function(value)
            iRCCharDB = iRCCharDB or {}
            iRCCharDB.hideAllChatIcons = value and true or false
        end)

    local layoutCard = makeCard(412, 150, "Panel & Map Appearance")
    local pinLabel = layoutCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pinLabel:SetPoint("TOPLEFT", 16, -39)
    pinLabel:SetText(iRC:Text("GUILD_MAP_PIN_SIZE"))
    local pinValue = layoutCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pinValue:SetPoint("LEFT", pinLabel, "RIGHT", 8, 0)
    pinValue:SetTextColor(unpack(COLORS.gold))
    local pinSlider = CreateFrame("Slider", "iRCPanelGuildMapPinSizeSlider", layoutCard, "OptionsSliderTemplate")
    pinSlider:SetPoint("TOPLEFT", 15, -59)
    pinSlider:SetWidth(250)
    pinSlider:SetMinMaxValues(5, 15)
    pinSlider:SetValueStep(1)
    _G[pinSlider:GetName() .. "Low"]:SetText("5")
    _G[pinSlider:GetName() .. "High"]:SetText("15")
    _G[pinSlider:GetName() .. "Text"]:SetText("")
    pinSlider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        pinValue:SetText(tostring(value))
        if page.refreshing then return end
        if iRC.GuildMap then iRC.GuildMap:SetPinSize(value) else iRC:GetSettings().guildMapPinSize = value end
    end)
    page.pinSlider, page.pinValue = pinSlider, pinValue

    local scaleLabel = layoutCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    scaleLabel:SetPoint("TOPLEFT", 340, -39)
    scaleLabel:SetText(iRC:Text("IRC_MAIN_WINDOW_SCALE"))
    local scaleValue = layoutCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleValue:SetPoint("LEFT", scaleLabel, "RIGHT", 8, 0)
    scaleValue:SetTextColor(unpack(COLORS.gold))
    local scaleSlider = CreateFrame("Slider", "iRCPanelMainWindowScaleSlider", layoutCard, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", 339, -59)
    scaleSlider:SetWidth(250)
    scaleSlider:SetMinMaxValues(0.6, 2.0)
    scaleSlider:SetValueStep(0.05)
    _G[scaleSlider:GetName() .. "Low"]:SetText("60%")
    _G[scaleSlider:GetName() .. "High"]:SetText("200%")
    _G[scaleSlider:GetName() .. "Text"]:SetText("")
    local function applyScaleSliderValue()
        if page.refreshing then return end
        local value = scaleSlider.pendingValue
        if not value then return end
        scaleSlider.pendingValue = nil
        iRC:GetSettings().mainWindowScale = value
        frame:SetScale(value)
    end
    scaleSlider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value * 20 + 0.5) / 20
        scaleValue:SetText(math.floor(value * 100 + 0.5) .. "%")
        if page.refreshing then return end
        scaleSlider.pendingValue = value
        if not scaleSlider.dragging then applyScaleSliderValue() end
    end)
    scaleSlider:HookScript("OnMouseDown", function()
        scaleSlider.dragging = true
    end)
    local function finishScaleSliderDrag()
        scaleSlider.dragging = nil
        if C_Timer and C_Timer.After then C_Timer.After(0, applyScaleSliderValue)
        else applyScaleSliderValue() end
    end
    scaleSlider:HookScript("OnMouseUp", finishScaleSliderDrag)
    page.scaleSlider, page.scaleValue = scaleSlider, scaleValue

    local reset = makeIRCActionButton(layoutCard, 180, 27, iRC:Text("IRC_MAIN_WINDOW_RESET"), false)
    reset:SetPoint("BOTTOM", layoutCard, "BOTTOM", 0, 12)
    reset:SetScript("OnClick", function()
        frame:ClearAllPoints()
        frame:SetPoint("CENTER")
        iRC:Print(iRC:Text("MAIN_WINDOW_RESET_DONE"))
    end)

    local roleplayCard = makeCard(572, 234, "Character Speech")
    page.roleplayControls = {}
    local function addRoleplayToggle(y, label, description, settingKey, available)
        local button = makeToggle(roleplayCard, y, label, description,
            function()
                local settings = iRC.Roleplay and iRC.Roleplay:GetPlayerSettings()
                return settings and settings[settingKey] == true
            end,
            function(value)
                local settings = iRC.Roleplay and iRC.Roleplay:GetPlayerSettings()
                if settings then settings[settingKey] = value and true or false end
            end)
        page.roleplayControls[#page.roleplayControls + 1] = { button = button, available = available }
    end
    addRoleplayToggle(-38, "Enable Troll Talk", "Adds simple troll wording to normal chat messages.",
        "trollTalk", function() return iRC.Roleplay and iRC.Roleplay:IsTroll() end)
    addRoleplayToggle(-87, iRC:Text("TAUREN_TALK_ENABLE"), iRC:Text("TAUREN_TALK_DESC"),
        "taurenTalk", function() return iRC.Roleplay and iRC.Roleplay:IsTauren() end)
    addRoleplayToggle(-136, iRC:Text("NIGHT_ELF_TALK_ENABLE"), iRC:Text("NIGHT_ELF_TALK_DESC"),
        "nightElfTalk", function() return iRC.Roleplay and iRC.Roleplay:IsNightElf() end)
    addRoleplayToggle(-185, iRC:Text("UNDEAD_SPEAK_ENABLE"), iRC:Text("UNDEAD_SPEAK_DESC"),
        "undeadSpeak", function() return iRC.Roleplay and iRC.Roleplay:IsUndead() end)

    page:Hide()
    frame.personalSettings = page
    return page
end

local function updatePersonalSettings(frame)
    local page = ensurePersonalSettings(frame)
    for _, row in ipairs(frame.memberRows or {}) do row:Hide() end
    for _, card in ipairs(frame.raceCards or {}) do card:Hide() end
    for _, section in pairs(frame.factionSections or {}) do section:Hide() end
    if frame.racePodium then frame.racePodium:Hide() end
    page.refreshing = true
    if iRC.Identity then iRC.Identity:RegisterCharacter(iRC:GetPlayerName()) end
    local mainName = iRC.Identity and iRC.Identity:GetMainName() or ""
    UIDropDownMenu_SetSelectedValue(page.mainDropdown, mainName)
    UIDropDownMenu_SetText(page.mainDropdown,
        mainName ~= "" and iRC:FormatPlayerName(mainName) or "No character registered")
    local defaultTab = iRC:GetSettings().mainPanelDefaultTab or DEFAULT_OPEN_LAST
    local defaultTabLabel = getNavigationLabel(defaultTab)
    if not defaultTabLabel then
        defaultTab = DEFAULT_OPEN_LAST
        defaultTabLabel = getNavigationLabel(defaultTab)
        iRC:GetSettings().mainPanelDefaultTab = defaultTab
    end
    UIDropDownMenu_SetSelectedValue(page.startupDropdown, defaultTab)
    UIDropDownMenu_SetText(page.startupDropdown, defaultTabLabel)
    for _, control in ipairs(page.controls) do control:Refresh() end
    for _, entry in ipairs(page.roleplayControls or {}) do
        local available = entry.available() == true
        entry.button:SetEnabled(available)
        entry.button:SetAlpha(available and 1 or 0.42)
    end
    local pinSize = math.max(5, math.min(15, math.floor(tonumber(iRC:GetSettings().guildMapPinSize) or 8)))
    page.pinSlider:SetValue(pinSize)
    page.pinValue:SetText(tostring(pinSize))
    local scale = math.max(0.6, math.min(2, tonumber(iRC:GetSettings().mainWindowScale) or 1))
    page.scaleSlider:SetValue(scale)
    page.scaleValue:SetText(math.floor(scale * 100 + 0.5) .. "%")
    page.refreshing = nil
    page:Show()
    frame.scrollContent:SetHeight(page:GetHeight())
    frame.scroll:SetVerticalScroll(0)
    frame.contentTitle:SetText("Personal Settings")
    frame.contentSubtitle:SetText("Your character identity, visibility, chat icons, map markers, panel appearance, and character speech.")
end

function UI:ConfirmDisableGuildConnection()
    local frame = self:Create()
    frame.disableConfirm:Show()
    frame.disableConfirm:Raise()
end

function UI:RenderMemberRows()
    local frame = self.frame
    if not frame or frame.category ~= "Guild Members" then return end
    local profiles = frame.memberData or {}
    local first = math.floor((frame.scroll:GetVerticalScroll() or 0) / 48) + 1
    local scrollHeight = frame.scroll:GetHeight() or 0
    if scrollHeight < 1 then scrollHeight = 480 end
    local visible = math.max(0, math.min(#profiles - first + 1, math.ceil(scrollHeight / 48) + 1))
    for slot = 1, visible do
        local index, profile = first + slot - 1, profiles[first + slot - 1]
        local row = frame.memberRows[slot]
        if not row then
            row = makeMemberRow(frame.scrollContent, index)
            frame.memberRows[slot] = row
        end
        setMemberRowDensity(row, false)
        row:ClearAllPoints()
        row:SetAlpha(1)
        row:SetPoint("TOPLEFT", frame.scrollContent, "TOPLEFT", 0, -((index - 1) * 48))
        row:SetPoint("TOPRIGHT", frame.scrollContent, "TOPRIGHT", 0, -((index - 1) * 48))
        local memberTag, tagColor
        local identityLabel = iRC.Identity and iRC.Identity:GetIdentityLabel(profile.name)
        row.name:SetFontObject(GameFontHighlight)
        if iRC:IsOfficialHardcoreRealm() and profile.dead == true then
            memberTag, tagColor = "Dead", { 1.00, 0.50, 0.50 }
        elseif iRC.Identity and iRC.Identity:IsPersonalBank(profile.name) then
            memberTag, tagColor = "Personal Bank", { 0.40, 0.80, 1.00 }
        elseif identityLabel == "Main" then
            memberTag, tagColor = "Main", { 0.30, 1.00, 0.35 }
        elseif identityLabel and identityLabel:find("^Pending") then
            memberTag, tagColor = "Pending Alt", { 1.00, 0.72, 0.22 }
        elseif identityLabel then
            memberTag, tagColor = "Alt", { 0.70, 0.55, 1.00 }
        elseif profile.selfFound == true then
            memberTag, tagColor = "Self-Found", { 1.00, 0.55, 0.55 }
        elseif iRC:IsGuildFoundProgressionApplicable(profile.level, profile.selfFound)
            and profile.raceLockedStatus and profile.raceLockedStatus.verified == true then
            memberTag, tagColor = "Guild-Found", { 0.30, 1, 0.35 }
        end
        row.name:SetText(iRC:FormatPlayerName(profile.name))
        row.name:SetWidth(math.min(300, row.name:GetStringWidth() + 3))
        row.onlineTag:SetShown(profile.online == true)
        row.tag:ClearAllPoints()
        row.tag:SetPoint("LEFT", profile.online == true and row.onlineTag or row.name, "RIGHT", profile.online == true and 6 or 8, 0)
        row.tag:SetText(memberTag and ("[" .. memberTag .. "]") or "")
        if tagColor then row.tag:SetTextColor(tagColor[1], tagColor[2], tagColor[3]) end
        row.tag:SetShown(memberTag ~= nil)
        row.name:SetTextColor(unpack(iRC:NormalizeName(profile.name) == iRC:NormalizeName(iRC:GetPlayerName()) and COLORS.green or COLORS.gold))
        row.detail:SetText((profile.race or "Unknown") .. " · " .. (profile.class or "Unknown") .. " · Level " .. (profile.level or 1))
        if identityLabel then row.detail:SetText(row.detail:GetText() .. " | " .. identityLabel) end
        row.profileName = profile.name
        local professionData = profile.professionData
        local professionNames = {}
        for _, option in ipairs(iRC.Professions:GetOptions()) do
            local rank = professionData and professionData.skills and professionData.skills[option[1]]
            if rank then professionNames[#professionNames + 1] = option[2] .. " " .. rank end
        end
        if #professionNames > 0 then
            row.detail:SetText(row.detail:GetText() .. " | " .. table.concat(professionNames, ", "))
        end
        row:SetScript("OnClick", nil)
        row:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(iRC:FormatPlayerName(profile.name))
            if professionData and professionData.skills then
                local lines = iRC.Professions:DescribeRecipes(professionData)
                for index = 1, math.min(#lines, 18) do GameTooltip:AddLine(lines[index], 1, 1, 1) end
                if #lines > 18 then GameTooltip:AddLine("Click to view all known recipes.", 1, 0.7, 0.2) end
            else
                GameTooltip:AddLine("No profession data received from this member.", 0.7, 0.7, 0.7)
            end
            GameTooltip:AddLine("Left-click to view member profile.", 1, 0.72, 0.22)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        row:SetScript("OnClick", function(clickedRow, mouseButton)
            if mouseButton == "LeftButton" then
                frame.showMemberProfile(profile)
                return
            end
            if mouseButton ~= "RightButton" then return end
            local menu = frame.memberMenu
            menu.profile = profile
            menu.title:SetText(iRC:FormatPlayerName(profile.name))
            local registered = iRC.Identity and iRC.Identity:IsPersonalCharacter(profile.name)
            local isMain = registered and iRC.Identity:GetMainName() == iRC:FormatPlayerName(profile.name)
            local personalBank = registered and iRC.Identity:IsPersonalBank(profile.name)
            menu.altMenu.bank.text:SetText(personalBank and "Remove Personal Bank Alt" or "Set as Personal Bank Alt")
            frame.styleMemberMenuButton(menu.view, "detail", true)
            frame.styleMemberMenuButton(menu.whisper, "contact", true)
            frame.styleMemberMenuButton(menu.alts, "character", true)
            frame.styleMemberMenuButton(menu.altMenu.add, "character", not registered)
            frame.styleMemberMenuButton(menu.altMenu.main, "detail", not isMain)
            frame.styleMemberMenuButton(menu.altMenu.bank, "bank", not isMain)
            frame.styleMemberMenuButton(menu.altMenu.remove, "danger", registered and not isMain)
            local canManageIdentity = iRC:IsTestAdmin() == true or iRC:IsGuildMaster() == true
                or (iRC:IsGuildConnectionActive() == true and iRC:HasGuildPermission("identity") == true)
            menu.identityLabel:SetShown(canManageIdentity)
            menu.assignAlt:SetShown(canManageIdentity)
            menu.clearIdentity:SetShown(canManageIdentity)
            if canManageIdentity then
                local managedAssignment = iRC.Identity and iRC.Identity:GetManagedAssignment(profile.name)
                frame.styleMemberMenuButton(menu.assignAlt, "character", true)
                frame.styleMemberMenuButton(menu.clearIdentity, "danger", managedAssignment ~= nil)
            end
            menu.altMenu:Hide()
            menu:SetHeight(canManageIdentity and 260 or 214)
            local cursorX, cursorY = GetCursorPosition()
            menu:ClearAllPoints()
            -- Match the Verification popup: convert physical cursor pixels to
            -- this scaled menu's coordinate space before anchoring to UIParent.
            local menuScale = menu:GetEffectiveScale()
            if not menuScale or menuScale <= 0 then menuScale = UIParent:GetEffectiveScale() or 1 end
            menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cursorX / menuScale, cursorY / menuScale)
            menu:Show()
            menu:Raise()
        end)
        row:Show()
    end
    for slot = visible + 1, #frame.memberRows do frame.memberRows[slot]:Hide() end
end

applyMemberSearch = function(frame)
    local profiles = frame.allMemberData or {}
    local selection = frame.memberSearchSelection
    local query = frame.memberProfessionSearch.edit:GetText():lower():gsub("^%s+", ""):gsub("%s+$", "")
    if selection or query ~= "" then
        local members = {}
        if selection then
            for profile in pairs(selection.members) do members[profile] = true end
        else
            for _, entry in ipairs(frame.memberSearchIndex or {}) do
                if entry.lower:find(query, 1, true) then
                    for profile in pairs(entry.members) do members[profile] = true end
                end
            end
        end
        local filtered = {}
        for _, profile in ipairs(profiles) do
            if members[profile] then filtered[#filtered + 1] = profile end
        end
        profiles = filtered
    end
    frame.memberData = profiles
    frame.scrollContent:SetHeight(math.max(1, #profiles * 48))
    frame.scroll:SetVerticalScroll(0)
    UI:RenderMemberRows()
end

local function updateMemberRows(frame)
    -- Index the current roster once per refresh; typing only filters these rows.
    local profiles = iRC:GetGuildRosterRows()
    local entries, byKey, profilesByName = {}, {}, {}
    local function add(kind, label, profile)
        if not label or label == "" then return end
        local key = kind .. ":" .. label:lower()
        local entry = byKey[key]
        if not entry then
            entry = { kind = kind, label = label, lower = label:lower(), members = {} }
            byKey[key] = entry
            entries[#entries + 1] = entry
        end
        entry.members[profile] = true
    end
    for _, profile in ipairs(profiles) do
        profilesByName[iRC:NormalizeName(profile.name)] = profile
    end
    for _, profile in ipairs(profiles) do
        local linkedNames = iRC.Identity and iRC.Identity:GetLinkedCharacters(profile.name) or {}
        if #linkedNames == 0 then
            add("name", iRC:FormatPlayerName(profile.name), profile)
        else
            -- Every character name in an identity group points at every group
            -- member currently in the roster. Searching a main therefore also
            -- finds its Alts and Personal Bank Alts, and vice versa.
            local linkedProfiles = {}
            for _, linkedName in ipairs(linkedNames) do
                local linkedProfile = profilesByName[iRC:NormalizeName(linkedName)]
                if linkedProfile then linkedProfiles[#linkedProfiles + 1] = linkedProfile end
            end
            for _, linkedName in ipairs(linkedNames) do
                local displayName = iRC:FormatPlayerName(linkedName)
                for _, linkedProfile in ipairs(linkedProfiles) do add("name", displayName, linkedProfile) end
            end
        end
        local data = profile.professionData
        if data then
            for _, option in ipairs(iRC.Professions:GetOptions()) do
                if data.skills and data.skills[option[1]] then add("profession", option[2], profile) end
            end
            for _, recipes in pairs(data.recipes or {}) do
                for _, recipe in ipairs(recipes) do
                    if type(recipe) == "string" then
                        local name = recipe:sub(1, 1) == "S" and iRC:GetSpellName(tonumber(recipe:sub(2))) or recipe:sub(2)
                        add("recipe", name, profile)
                    end
                end
            end
        end
    end
    frame.allMemberData, frame.memberSearchIndex = profiles, entries
    -- A selected suggestion may have been rebuilt with new roster data.
    local selection = frame.memberSearchSelection
    if selection then frame.memberSearchSelection = byKey[selection.kind .. ":" .. selection.lower] end
    for _, card in ipairs(frame.raceCards) do card:Hide() end
    for _, section in pairs(frame.factionSections) do section:Hide() end
    frame.racePodium:Hide()
    applyMemberSearch(frame)
    updateMemberSuggestions(frame)
    frame.contentTitle:SetText("Guild Members")
    frame.contentSubtitle:SetText("Search the full roster by character or linked-alt name, profession, and known recipe.")
end

local GUILD_LOG_COLORS = {
    JOIN = COLORS.green, REJOIN = COLORS.green, PROMOTE = COLORS.gold,
    DEMOTE = { 1.00, 0.55, 0.20 }, LEAVE = { 1.00, 0.50, 0.50 }, NAME = COLORS.gold,
    LEVEL = COLORS.green, RETURN = COLORS.green, NOTE = COLORS.parchment, OFFICER_NOTE = COLORS.parchment,
}

local function updateGuildLog(frame)
    if iRC.Identity then iRC.Identity:RequestGuildHistory() end
    for _, card in ipairs(frame.raceCards) do card:Hide() end
    for _, section in pairs(frame.factionSections) do section:Hide() end
    frame.racePodium:Hide()
    local records = iRC.Identity and iRC.Identity:GetGuildLog() or {}
    local query = frame.guildLogSearch and frame.guildLogSearch:GetText() or ""
    query = query:match("^%s*(.-)%s*$"):lower()
    if query ~= "" then
        local filtered = {}
        for _, record in ipairs(records) do
            local searchable = table.concat({ record.name or "", record.eventType or "", record.text or "" }, " "):lower()
            if searchable:find(query, 1, true) then filtered[#filtered + 1] = record end
        end
        records = filtered
    end
    local currentClasses = {}
    for _, member in ipairs(iRC:GetGuildRosterSnapshot()) do
        currentClasses[iRC:NormalizeName(member.name)] = member.classFile
    end
    for index, record in ipairs(records) do
        local row = frame.memberRows[index]
        if not row then
            row = makeMemberRow(frame.scrollContent, index)
            frame.memberRows[index] = row
        end
        setMemberRowDensity(row, true)
        row:SetAlpha(1)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.scrollContent, "TOPLEFT", 0, -((index - 1) * 44))
        row:SetPoint("TOPRIGHT", frame.scrollContent, "TOPRIGHT", 0, -((index - 1) * 44))
        row.name:SetFontObject(GameFontNormal)
        row.name:SetText(record.name or "Unknown member")
        row.name:SetWidth(math.min(300, row.name:GetStringWidth() + 3))
        local classFile = record.classFile or currentClasses[iRC:NormalizeName(record.name)]
        local classColor = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        if classColor then
            row.name:SetTextColor(classColor.r, classColor.g, classColor.b)
        else
            row.name:SetTextColor(unpack(COLORS.gold))
        end
        row.onlineTag:Hide()
        row.tag:ClearAllPoints()
        row.tag:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
        row.tag:SetText("[" .. tostring(record.eventType or "CHANGE"):gsub("_", " ") .. "]")
        row.tag:SetTextColor(unpack(GUILD_LOG_COLORS[record.eventType] or COLORS.parchment))
        row.tag:Show()
        local occurredAt = record.occurredAt and date("%Y-%m-%d %H:%M", record.occurredAt) or "Unknown time"
        row.detail:SetText(occurredAt .. " - " .. (record.text or "Guild roster changed."))
        row:SetScript("OnClick", nil)
        row:SetScript("OnEnter", nil)
        row:SetScript("OnLeave", nil)
        row:Show()
    end
    for index = #records + 1, #frame.memberRows do frame.memberRows[index]:Hide() end
    frame.scrollContent:SetHeight(math.max(1, #records * 44))
    frame.contentTitle:SetText("Guild Log")
    frame.contentSubtitle:SetText(#records > 0 and iRC:Text("GUILD_LOG_DESCRIPTION")
        or (query ~= "" and iRC:Text("GUILD_LOG_NO_SEARCH_RESULTS") or iRC:Text("GUILD_LOG_EMPTY")))
end

local function updateInactiveMembers(frame)
    for _, card in ipairs(frame.raceCards) do card:Hide() end
    for _, section in pairs(frame.factionSections) do section:Hide() end
    frame.racePodium:Hide()

    local threshold = math.max(0, math.min(9999,
        math.floor(tonumber(frame.inactiveMemberDays) or 30)))
    frame.inactiveMemberDays = threshold
    if frame.inactiveThreshold and not frame.inactiveThreshold.input:HasFocus() then
        frame.inactiveThreshold.input:SetText(tostring(threshold))
    end
    if frame.RefreshInactiveRankExclude then frame:RefreshInactiveRankExclude() end
    local members = {}
    local selfKey = iRC:NormalizeName(iRC:GetPlayerName())
    local excludedRank = frame.inactiveExcludedRank
    for _, member in ipairs(iRC:GetGuildRosterSnapshot()) do
        if not member.online and tonumber(member.lastOnlineDays) and member.lastOnlineDays >= threshold
            and iRC:NormalizeName(member.name) ~= selfKey
            and not (excludedRank and type(member.rankIndex) == "number" and member.rankIndex <= excludedRank) then
            members[#members + 1] = member
        end
    end
    table.sort(members, function(a, b)
        if a.lastOnlineDays ~= b.lastOnlineDays then return a.lastOnlineDays > b.lastOnlineDays end
        return iRC:NormalizeName(a.name) < iRC:NormalizeName(b.name)
    end)

    local ownRank = getNativeGuildRank()
    local eligibleCount = 0
    for index, member in ipairs(members) do
        local row = frame.memberRows[index]
        if not row then
            row = makeMemberRow(frame.scrollContent, index)
            frame.memberRows[index] = row
        end
        setMemberRowDensity(row, false)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.scrollContent, "TOPLEFT", 0, -((index - 1) * 48))
        row:SetPoint("TOPRIGHT", frame.scrollContent, "TOPRIGHT", 0, -((index - 1) * 48))
        row.name:SetFontObject(GameFontNormal)
        row.name:SetText(iRC:FormatPlayerName(member.name))
        row.name:SetWidth(math.min(300, row.name:GetStringWidth() + 3))
        local classColor = member.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.classFile]
        if classColor then row.name:SetTextColor(classColor.r, classColor.g, classColor.b)
        else row.name:SetTextColor(unpack(COLORS.gold)) end
        row.onlineTag:Hide()
        local canRemove = type(ownRank) == "number" and type(member.rankIndex) == "number"
            and member.rankIndex > ownRank
        if canRemove then eligibleCount = eligibleCount + 1 end
        row.tag:ClearAllPoints()
        row.tag:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
        row.tag:SetText(canRemove and "[Remove...]" or "[Equal/higher rank]")
        row.tag:SetTextColor(unpack(canRemove and COLORS.red or COLORS.gray))
        row.tag:Show()
        local selectedMember = member
        local days = math.floor(selectedMember.lastOnlineDays + 0.5)
        row.detail:SetText("Offline for approximately " .. tostring(days) .. " days · "
            .. tostring(selectedMember.rankName or "Unknown rank") .. " · Level " .. tostring(selectedMember.level or "?")
            .. " " .. tostring(selectedMember.className or ""))
        row:SetAlpha(canRemove and 1 or 0.58)
        row:SetScript("OnClick", canRemove and function(_, button)
            if button ~= "LeftButton" then return end
            local confirm = frame.removeMemberConfirm
            confirm.removeAll = nil
            confirm.rankAction = nil
            confirm.sourceRank = nil
            confirm.testPreview = nil
            confirm.targetName = selectedMember.name
            confirm.threshold = threshold
            confirm:SetSize(510, 205)
            confirm.rankTargetLabel:Hide()
            confirm.rankTargetDropdown:Hide()
            confirm.rankTargetDropdown.menu:Hide()
            confirm.bulkList:Hide()
            confirm.title:SetText("Remove inactive guild member?")
            confirm.accept.text:SetText("Remove member")
            confirm.accept:SetEnabled(true)
            confirm.accept:SetAlpha(1)
            confirm.body:SetText("Remove " .. iRC:FormatPlayerName(selectedMember.name) .. " from the guild?\n\n"
                .. "They have been offline for approximately " .. tostring(days)
                .. " days. This is a manual, one-member action and still requires your WoW guild rank to permit removal.")
            confirm:Show()
            confirm:Raise()
        end or nil)
        row:SetScript("OnEnter", nil)
        row:SetScript("OnLeave", nil)
        row:Show()
    end
    for index = #members + 1, #frame.memberRows do
        frame.memberRows[index]:SetAlpha(1)
        frame.memberRows[index]:Hide()
    end
    if eligibleCount == 0 and iRC:IsTestAdmin() then
        eligibleCount = #getEligibleInactiveMembers(threshold, true, excludedRank)
    end
    frame.scrollContent:SetHeight(math.max(1, #members * 48))
    frame.inactiveRemoveAll:SetText(iRC:Text("INACTIVE_MEMBERS_REMOVE_ALL", eligibleCount))
    local bulkEnabled = eligibleCount > 0 or iRC:IsTestAdmin()
    frame.inactiveRemoveAll:SetEnabled(bulkEnabled)
    frame.inactiveRemoveAll:SetAlpha(bulkEnabled and 1 or 0.42)
    frame.contentTitle:SetText("Inactive Member Management")
    frame.contentSubtitle:SetText(#members > 0
        and (tostring(#members) .. " offline member(s) at or above " .. tostring(threshold)
            .. " days. Click an eligible member to review a single removal.")
        or ("No offline members have reached " .. tostring(threshold) .. " days."))
end

local function updateRankManagement(frame)
    if frame.rankMemberMenu then frame.rankMemberMenu:Hide() end
    for _, card in ipairs(frame.raceCards) do card:Hide() end
    for _, section in pairs(frame.factionSections) do section:Hide() end
    frame.racePodium:Hide()
    local options = iRC:GetGuildRankOptions()
    local roster = iRC:GetGuildRosterSnapshot()
    local rankCounts = {}
    for _, member in ipairs(roster) do
        if type(member.rankIndex) == "number" then
            rankCounts[member.rankIndex] = (rankCounts[member.rankIndex] or 0) + 1
        end
    end
    local selectedRankExists = false
    for _, rank in ipairs(options) do
        if rank.index == frame.rankManagementRank then selectedRankExists = true break end
    end
    if not selectedRankExists then frame.rankManagementRank = nil end
    local rankName
    for _, rank in ipairs(options) do
        if rank.index == frame.rankManagementRank then rankName = rank.name break end
    end
    if rankName then
        local count = rankCounts[frame.rankManagementRank] or 0
        frame.rankManagementControls.dropdown:SetDisplay(rankName .. " (Rank " .. frame.rankManagementRank
            .. ") - " .. count .. (count == 1 and " member" or " members"))
    else
        frame.rankManagementControls.dropdown:SetDisplay()
    end
    frame.rankManagementControls.dropdown:Refresh(options, rankCounts)

    local members, promoteCount, demoteCount = {}, 0, 0
    if type(frame.rankManagementRank) == "number" then
        for _, member in ipairs(roster) do
            if member.rankIndex == frame.rankManagementRank then
                members[#members + 1] = member
            end
        end
        table.sort(members, function(a, b) return iRC:NormalizeName(a.name) < iRC:NormalizeName(b.name) end)
    end
    for index, member in ipairs(members) do
        local isSelf = iRC:NormalizeName(member.name) == iRC:NormalizeName(iRC:GetPlayerName())
        local nativePromote = not isSelf and isRankActionEligible(member, "PROMOTE", false)
        local nativeDemote = not isSelf and isRankActionEligible(member, "DEMOTE", false)
        local previewPromote = not isSelf and not nativePromote and iRC:IsTestAdmin()
            and isRankActionEligible(member, "PROMOTE", true)
        local previewDemote = not isSelf and not nativeDemote and iRC:IsTestAdmin()
            and isRankActionEligible(member, "DEMOTE", true)
        local canPromote, canDemote = nativePromote or previewPromote, nativeDemote or previewDemote
        if canPromote then promoteCount = promoteCount + 1 end
        if canDemote then demoteCount = demoteCount + 1 end
        local row = frame.memberRows[index]
        if not row then row = makeMemberRow(frame.scrollContent, index); frame.memberRows[index] = row end
        setMemberRowDensity(row, false)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.scrollContent, "TOPLEFT", 0, -((index - 1) * 48))
        row:SetPoint("TOPRIGHT", frame.scrollContent, "TOPRIGHT", 0, -((index - 1) * 48))
        row.name:SetFontObject(GameFontNormal)
        row.name:SetText(iRC:FormatPlayerName(member.name))
        row.name:SetWidth(math.min(300, row.name:GetStringWidth() + 3))
        local classColor = member.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.classFile]
        if isSelf then row.name:SetTextColor(unpack(COLORS.gray))
        elseif classColor then row.name:SetTextColor(classColor.r, classColor.g, classColor.b)
        else row.name:SetTextColor(unpack(COLORS.gold)) end
        row.onlineTag:Hide()
        row.tag:ClearAllPoints()
        row.tag:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
        local previewOnly = not nativePromote and not nativeDemote and (previewPromote or previewDemote)
        local tagText = isSelf and "[Your character]"
            or ((nativePromote or nativeDemote) and "[Click to manage]"
                or (previewOnly and "[Click to preview]" or "[Native restriction]"))
        row.tag:SetText(tagText)
        row.tag:SetTextColor(unpack((canPromote or canDemote) and COLORS.green or COLORS.gray))
        row.tag:Show()
        row.detail:SetText(tostring(member.rankName or "Unknown rank") .. " · Level "
            .. tostring(member.level or "?") .. " " .. tostring(member.className or "")
            .. " · Promote: " .. (canPromote and "yes" or "no")
            .. " · Demote: " .. (canDemote and "yes" or "no"))
        row:SetAlpha(isSelf and 0.42 or ((canPromote or canDemote) and 1 or 0.58))
        local selectedMember = member
        row:SetScript("OnClick", (canPromote or canDemote) and function(self, button)
            if button ~= "LeftButton" or not frame.rankMemberMenu then return end
            frame.rankMemberMenu:Open(selectedMember, self, canPromote, canDemote,
                previewPromote, previewDemote)
        end or nil)
        row:SetScript("OnEnter", nil)
        row:SetScript("OnLeave", nil)
        row:Show()
    end
    for index = #members + 1, #frame.memberRows do frame.memberRows[index]:SetAlpha(1); frame.memberRows[index]:Hide() end
    frame.scrollContent:SetHeight(math.max(1, #members * 48))
    frame.rankManagementControls.promote.text:SetText("Promote selected... (" .. promoteCount .. ")")
    frame.rankManagementControls.demote.text:SetText("Demote selected... (" .. demoteCount .. ")")
    frame.rankManagementControls.promote:SetEnabled(promoteCount > 0)
    frame.rankManagementControls.promote:SetAlpha(promoteCount > 0 and 1 or 0.42)
    frame.rankManagementControls.demote:SetEnabled(demoteCount > 0)
    frame.rankManagementControls.demote:SetAlpha(demoteCount > 0 and 1 or 0.42)
    frame.contentTitle:SetText("Guild Rank Management")
    frame.contentSubtitle:SetText(type(frame.rankManagementRank) == "number"
        and (#members .. " member(s) currently hold " .. tostring(rankName or ("Rank " .. frame.rankManagementRank))
            .. ". Click one member for a single action, or use the buttons above for a selected batch.")
        or "Choose a current guild rank to review its members for one-step promotion or demotion.")
end

local GUILD_HEALTH_CLASS_ORDER = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

local function makeGuildHealthPanel(parent, title, width, height)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetSize(width, height)
    createBackdrop(panel, { 0.04, 0.038, 0.035, 0.98 }, { 0.30, 0.26, 0.19, 1 })
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", 11, -10)
    panel.title:SetText(title)
    panel.title:SetTextColor(unpack(COLORS.gold))
    panel.subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.subtitle:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -3)
    panel.subtitle:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
    panel.subtitle:SetJustifyH("LEFT")
    return panel
end

local function makeGuildHealthBarRow(parent, y, labelWidth, trackWidth)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
    row:SetPoint("RIGHT", parent, "RIGHT", -10, 0)
    row:SetHeight(16)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", 0, 0)
    row.label:SetWidth(labelWidth)
    row.label:SetJustifyH("LEFT")
    row.track = row:CreateTexture(nil, "BACKGROUND")
    row.track:SetPoint("LEFT", row.label, "RIGHT", 5, 0)
    row.track:SetSize(trackWidth, 8)
    row.track:SetColorTexture(0.16, 0.15, 0.14, 1)
    row.fill = row:CreateTexture(nil, "ARTWORK")
    row.fill:SetPoint("LEFT", row.track, "LEFT", 0, 0)
    row.fill:SetHeight(8)
    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.value:SetPoint("LEFT", row.track, "RIGHT", 7, 0)
    row.value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.value:SetJustifyH("RIGHT")
    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 0.12)
    return row
end

local function setGuildHealthBar(row, label, value, maximum, color, valueText)
    row.label:SetText(label)
    row.value:SetText(valueText or tostring(value))
    local fraction = maximum > 0 and math.max(0, math.min(1, value / maximum)) or 0
    row.fill:SetWidth(math.max(1, row.track:GetWidth() * fraction))
    row.fill:SetColorTexture(color[1], color[2], color[3], 0.95)
    row.fill:SetShown(value > 0)
end

local updateGuildOverview

local function ensureGuildOverview(frame)
    if frame.guildOverview then return frame.guildOverview end
    local root = CreateFrame("Frame", nil, frame.scrollContent)
    root:SetPoint("TOPLEFT", frame.scrollContent, "TOPLEFT", 0, 0)
    root:SetPoint("TOPRIGHT", frame.scrollContent, "TOPRIGHT", 0, 0)
    root:SetHeight(462)
    root.metrics = {}
    for index, label in ipairs({ "Guild Members", "Online Now", "Active This Month", "Needs Attention" }) do
        local card = CreateFrame("Frame", nil, root, "BackdropTemplate")
        card:SetSize(160, 66)
        card:SetPoint("TOPLEFT", root, "TOPLEFT", (index - 1) * 170, 0)
        createBackdrop(card, { 0.055, 0.05, 0.043, 0.98 }, { 0.34, 0.29, 0.20, 1 })
        card.accent = card:CreateTexture(nil, "ARTWORK")
        card.accent:SetPoint("TOPLEFT", 4, -4)
        card.accent:SetPoint("BOTTOMLEFT", 4, 4)
        card.accent:SetWidth(3)
        card.label = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        card.label:SetPoint("TOPLEFT", 12, -10)
        card.label:SetText(label)
        card.value = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        card.value:SetPoint("TOPLEFT", 12, -25)
        card.detail = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        card.detail:SetPoint("BOTTOMLEFT", 12, 7)
        card.detail:SetPoint("RIGHT", card, "RIGHT", -8, 0)
        card.detail:SetJustifyH("LEFT")
        root.metrics[index] = card
    end

    root.levels = makeGuildHealthPanel(root, "Level Distribution", 330, 188)
    root.levels:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -76)
    root.levels.rows = {}
    for index = 1, 6 do root.levels.rows[index] = makeGuildHealthBarRow(root.levels, -45 - (index - 1) * 23, 82, 160) end

    root.classes = makeGuildHealthPanel(root, "Class Distribution", 340, 188)
    root.classes:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -76)
    root.classes.rows = {}
    for index = 1, #GUILD_HEALTH_CLASS_ORDER do
        root.classes.rows[index] = makeGuildHealthBarRow(root.classes, -41 - (index - 1) * 16, 72, 155)
    end

    root.retention = makeGuildHealthPanel(root, "Member Activity", 330, 190)
    root.retention:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -272)
    root.retention.rows = {}
    for index = 1, 6 do root.retention.rows[index] = makeGuildHealthBarRow(root.retention, -45 - (index - 1) * 24, 108, 134) end

    root.vitality = makeGuildHealthPanel(root, "Guild Activity Score", 340, 190)
    root.vitality:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -272)
    root.vitality.score = root.vitality:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    root.vitality.score:SetPoint("TOP", root.vitality, "TOP", 0, -43)
    root.vitality.explanation = root.vitality:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    root.vitality.explanation:SetPoint("TOP", root.vitality.score, "BOTTOM", 0, -5)
    root.vitality.explanation:SetWidth(300)
    root.vitality.explanation:SetJustifyH("CENTER")
    root.vitality.separator = root.vitality:CreateTexture(nil, "ARTWORK")
    root.vitality.separator:SetPoint("TOPLEFT", 14, -105)
    root.vitality.separator:SetPoint("TOPRIGHT", -14, -105)
    root.vitality.separator:SetHeight(1)
    root.vitality.separator:SetColorTexture(0.30, 0.26, 0.19, 0.8)
    root.vitality.activity = root.vitality:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    root.vitality.activity:SetPoint("TOPLEFT", 16, -119)
    root.vitality.coverage = root.vitality:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    root.vitality.coverage:SetPoint("TOPLEFT", 16, -142)
    root.vitality.risk = root.vitality:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    root.vitality.risk:SetPoint("TOPLEFT", 16, -165)
    frame.guildOverview = root
    return root
end

updateGuildOverview = function(frame)
    for _, card in ipairs(frame.raceCards) do card:Hide() end
    for _, section in pairs(frame.factionSections) do section:Hide() end
    for _, row in ipairs(frame.memberRows) do row:Hide() end
    frame.racePodium:Hide()

    local overview = ensureGuildOverview(frame)
    frame.scroll:SetVerticalScroll(0)
    local excludeAlts = iRC:GetSettings().excludeAltsFromGuildSnapshot ~= false
    frame.guildOverviewAltToggle:SetText(excludeAlts and "Main characters only: ON" or "Main characters only: OFF")
    frame.guildOverviewAltToggle:SetBackdropColor(excludeAlts and 0.18 or 0.055,
        excludeAlts and 0.09 or 0.045, excludeAlts and 0.025 or 0.035, 0.98)
    frame.guildOverviewAltToggle:SetBackdropBorderColor(excludeAlts and COLORS.gold[1] or 0.28,
        excludeAlts and COLORS.gold[2] or 0.23, excludeAlts and COLORS.gold[3] or 0.16, excludeAlts and 1 or 0.9)
    local rosterMembers, members = iRC:GetGuildRosterRows(), {}
    for _, member in ipairs(rosterMembers) do
        if not excludeAlts or not (iRC.Identity and iRC.Identity:IsAlt(member.name)) then
            members[#members + 1] = member
        end
    end
    local total, online, active30, verifiedOnline, attention = #members, 0, 0, 0, 0
    local levelCounts = { 0, 0, 0, 0, 0, 0 }
    local classTotals, classActive = {}, {}
    local retention = { 0, 0, 0, 0, 0, 0 }
    local retentionPoints, knownActivity, recencyTotal = 0, 0, 0
    local responseRequired = iRC:IsAddonResponseRequired()

    for _, member in ipairs(members) do
        local level = math.max(1, math.min(60, math.floor(tonumber(member.level) or 1)))
        levelCounts[math.min(6, math.floor((level - 1) / 10) + 1)] = levelCounts[math.min(6, math.floor((level - 1) / 10) + 1)] + 1
        local class = tostring(member.class or "UNKNOWN"):upper():gsub("[^A-Z]", "")
        classTotals[class] = (classTotals[class] or 0) + 1
        if member.online then online = online + 1 end
        if member.online and member.verification and member.verification.state == "verified" then verifiedOnline = verifiedOnline + 1 end

        local recencyAttention = false
        recencyTotal = recencyTotal + 1
        local bucket, weight
        local days = tonumber(member.lastOnlineDays)
        if member.online or days and days <= 7 then bucket, weight = 1, 1
        elseif days and days <= 13 then bucket, weight = 2, 0.8
        elseif days and days <= 29 then bucket, weight = 3, 0.5
        elseif days and days <= 59 then bucket, weight = 4, 0.2
        elseif days then bucket, weight = 5, 0
        else bucket = 6 end
        retention[bucket] = retention[bucket] + 1
        if bucket <= 3 then
            active30 = active30 + 1
            classActive[class] = (classActive[class] or 0) + 1
        end
        if weight then
            retentionPoints = retentionPoints + weight
            knownActivity = knownActivity + 1
        end
        recencyAttention = bucket == 4 or bucket == 5
        local needsIRC = responseRequired and member.online
            and (not member.verification or member.verification.state ~= "verified")
        if recencyAttention or needsIRC then attention = attention + 1 end
    end

    local metricValues = {
        { total, excludeAlts and "main and unlinked characters" or "characters counted", COLORS.gold },
        { online, total > 0 and (math.floor(online / total * 100 + 0.5) .. "% of counted members") or "No members counted", COLORS.green },
        { active30, recencyTotal > 0 and (math.floor(active30 / recencyTotal * 100 + 0.5)
            .. "% active this month") or "No activity data", { 0.32, 0.75, 1 } },
        { attention, responseRequired and "inactive or missing iRC" or "inactive-member review", attention > 0 and COLORS.red or COLORS.green },
    }
    for index, values in ipairs(metricValues) do
        local card, color = overview.metrics[index], values[3]
        card.value:SetText(tostring(values[1]))
        card.value:SetTextColor(color[1], color[2], color[3])
        card.detail:SetText(values[2])
        card.accent:SetColorTexture(color[1], color[2], color[3], 0.95)
    end

    overview.levels.subtitle:SetText(tostring(total) .. " counted members grouped by level")
    local maxLevelCount = 0
    for _, count in ipairs(levelCounts) do maxLevelCount = math.max(maxLevelCount, count) end
    for index, count in ipairs(levelCounts) do
        setGuildHealthBar(overview.levels.rows[index], "Level " .. tostring((index - 1) * 10 + 1) .. "-" .. tostring(index * 10),
            count, maxLevelCount, { 0.32, 0.66, 1 })
    end

    overview.classes.subtitle:SetText("Active this month / total counted")
    local maxClassTotal = 0
    for _, class in ipairs(GUILD_HEALTH_CLASS_ORDER) do
        maxClassTotal = math.max(maxClassTotal, classTotals[class] or 0)
    end
    for index, class in ipairs(GUILD_HEALTH_CLASS_ORDER) do
        local totalClass, activeClass = classTotals[class] or 0, classActive[class] or 0
        local rawColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] or FALLBACK_CLASS_COLORS[class] or COLORS.gray
        local color = { rawColor.r or rawColor[1], rawColor.g or rawColor[2], rawColor.b or rawColor[3] }
        local label = _G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[class]
            or class:sub(1, 1) .. class:sub(2):lower()
        setGuildHealthBar(overview.classes.rows[index], label, totalClass, maxClassTotal, color,
            tostring(activeClass) .. " / " .. tostring(totalClass))
        overview.classes.rows[index].label:SetTextColor(color[1], color[2], color[3])
    end

    overview.retention.subtitle:SetText("Last seen by the guild roster - "
        .. (excludeAlts and "main characters only" or "all characters"))
    local retentionLabels = { "Seen this week", "Seen last week", "Seen this month", "Inactive 30-59 days", "Inactive 60+ days", "Activity unknown" }
    local retentionColors = { { 0.30, 0.85, 0.48 }, { 1, 0.67, 0.25 }, { 1, 0.47, 0.18 }, { 0.95, 0.25, 0.18 }, { 0.50, 0.18, 0.16 }, COLORS.gray }
    local retentionThresholds = { 0, 8, 14, 30, 60 }
    local canReviewInactive = iRC:HasGuildPermission("memberRemoval") or iRC:IsTestAdmin()
    for index, count in ipairs(retention) do
        local row = overview.retention.rows[index]
        setGuildHealthBar(row, retentionLabels[index], count, math.max(1, recencyTotal), retentionColors[index])
        local threshold = retentionThresholds[index]
        local clickable = canReviewInactive and threshold ~= nil and count > 0
        row:EnableMouse(clickable)
        row:SetScript("OnMouseUp", clickable and function(_, button)
            if button == "LeftButton" then UI:OpenInactiveMembers(threshold) end
        end or nil)
        row:SetScript("OnEnter", clickable and function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Open Inactive Members")
            GameTooltip:AddLine("Review offline members from " .. tostring(threshold) .. " days onward.", 1, 1, 1, true)
            GameTooltip:Show()
        end or nil)
        row:SetScript("OnLeave", clickable and function() if GameTooltip then GameTooltip:Hide() end end or nil)
    end

    local vitality = knownActivity > 0 and math.floor(retentionPoints / knownActivity * 100 + 0.5) or 0
    local vitalityColor = vitality >= 70 and COLORS.green or vitality >= 40 and COLORS.gold or COLORS.red
    overview.vitality.subtitle:SetText("Weighted from each member's last-seen time")
    overview.vitality.score:SetText(tostring(vitality) .. " / 100")
    overview.vitality.score:SetTextColor(vitalityColor[1], vitalityColor[2], vitalityColor[3])
    overview.vitality.explanation:SetText(knownActivity > 0
        and ("Based on " .. tostring(knownActivity) .. " members with known activity") or "No activity history is available yet")
    overview.vitality.activity:SetText("Active this month:  " .. tostring(active30) .. " / " .. tostring(recencyTotal))
    overview.vitality.coverage:SetText("Online using iRC:  " .. tostring(verifiedOnline) .. " / " .. tostring(online))
    overview.vitality.risk:SetText("Inactive 30+ days:  " .. tostring(retention[4] + retention[5]))

    overview:Show()
    frame.scrollContent:SetHeight(462)
    frame.contentTitle:SetText("Guild Overview")
    local updated = date and date("%H:%M") or "now"
    frame.contentSubtitle:SetText("Membership, activity, level and class distribution, and iRC adoption. Updated "
        .. updated .. ".")
end

local function updateGuildRules(frame)
    for _, card in ipairs(frame.raceCards) do card:Hide() end
    for _, section in pairs(frame.factionSections) do section:Hide() end
    for _, row in ipairs(frame.memberRows) do row:Hide() end
    frame.racePodium:Hide()

    local connection = iRC:GetConnection()
    local rules = iRC:GetConnectionRules()
    local isGuildMaster = iRC:IsGuildMaster()
    local viewAsMember = isGuildMaster and frame.rulesViewAsMember == true
    local canEdit = isGuildMaster and not viewAsMember
    local connectionActive = connection and connection.active == true
    local progression = iRC:GetProgressionMode(rules)
    local maxLevelProgression = iRC:GetMaxLevelProgressionMode(rules)
    local guildFoundRuleActive = rules.guildFoundOnly == true or rules.level60GuildFound == true
    local entries = {
        {
            section = "Guild Connection",
            title = "iRC Guild Connection",
            description = "Controls whether this guild uses iRC rules, enforcement, verification, roster sharing, and community synchronization.",
            active = connectionActive,
            activeLabel = "ENABLED",
            inactiveLabel = iRC:Text("GUILD_CONNECTION_REQUIRED"),
            requiredWhenInactive = true,
            activation = true,
            set = function(value) return iRC:SetGuildConnectionActive(value) end,
        },
        {
            section = "Guild Connection",
            title = "Require iRC AddOn",
            description = "Requires every online guild member to run and respond with iRC, even when no progression or group rule is active.",
            active = rules.requireIRC == true,
            activeLabel = "REQUIRED",
            inactiveLabel = "OPTIONAL",
            set = function(value) return iRC:SetConnectionRule("requireIRC", value) end,
        },
        {
            section = "Race-Locked",
            title = "Race-Locked Guild",
            description = "Defines the guild as Race-Locked at every level and makes the dependent race and language rules available.",
            active = rules.raceLock == true,
            activeLabel = "ENFORCED",
            inactiveLabel = "NOT REQUIRED",
            set = function(value) return iRC:SetConnectionRule("raceLock", value) end,
        },
        {
            section = "Race-Locked",
            title = "Native Language Chat",
            description = "At levels 1–60, outgoing supported chat uses the character's native racial language while Race-Locked is enforced.",
            active = rules.raceLock == true and rules.nativeTongueOnly == true,
            activeLabel = "ENABLED",
            inactiveLabel = "DISABLED",
            available = rules.raceLock == true,
            dependencyDepth = 1,
            set = function(value) return iRC:SetConnectionRule("nativeTongueOnly", value) end,
        },
        {
            section = "Race-Locked",
            title = "Same-Race Groups",
            description = "From level " .. tostring(rules.sameRaceMinimumLevel or 1)
                .. (rules.allowLevel60MixedRaceGroups and " through level 59" or " through level 60")
                .. ", parties and raids may contain only characters of the guild's selected race.",
            active = rules.raceLock == true and rules.sameRaceGroupsOnly == true,
            activeLabel = "REQUIRED",
            inactiveLabel = "NOT REQUIRED",
            available = rules.raceLock == true,
            dependencyDepth = 1,
            set = function(value) return iRC:SetConnectionRule("sameRaceGroupsOnly", value) end,
        },
        {
            section = "Race-Locked",
            title = "Level 60 Mixed-Race Exception",
            description = "At level 60, mixed-race parties and raids are allowed; the same-race requirement still applies below level 60.",
            active = rules.raceLock == true and rules.sameRaceGroupsOnly == true
                and rules.allowLevel60MixedRaceGroups == true,
            available = rules.raceLock == true and rules.sameRaceGroupsOnly == true,
            activeLabel = "ALLOWED",
            inactiveLabel = "NOT ALLOWED",
            dependencyDepth = 2,
            set = function(value) return iRC:SetConnectionRule("allowLevel60MixedRaceGroups", value) end,
        },
        {
            section = "Self-Found",
            title = "Self-Found Progression",
            description = maxLevelProgression == "GUILD_FOUND"
                and "Characters must remain Self-Found from levels 1–59 and then follow the configured level 60 Guild-Found rule."
                or maxLevelProgression == "UNRESTRICTED"
                    and "Characters must remain Self-Found from levels 1–59; progression becomes unrestricted at level 60."
                or "Characters must remain Self-Found throughout levels 1–60.",
            active = progression == "SELF_FOUND",
            activeLabel = "REQUIRED",
            inactiveLabel = "NOT REQUIRED",
            set = function(value) return iRC:SetProgressionMode(value and "SELF_FOUND" or "NONE") end,
        },
        {
            section = "Self-Found",
            title = "Level 60 Guild-Found Transition",
            description = "Characters must be Self-Found during levels 1–59. Upon reaching level 60, Guild-Found rules replace the Self-Found requirement.",
            active = progression == "SELF_FOUND" and maxLevelProgression == "GUILD_FOUND",
            available = progression == "SELF_FOUND",
            activeLabel = "ENABLED",
            inactiveLabel = "DISABLED",
            dependencyDepth = 1,
            set = function(value) return iRC:SetMaxLevelProgressionMode(value and "GUILD_FOUND" or "SELF_FOUND") end,
        },
        {
            section = "Self-Found",
            title = "Level 60 Unrestricted Transition",
            description = "Characters must be Self-Found during levels 1–59. At level 60, the progression restriction is removed.",
            active = progression == "SELF_FOUND" and maxLevelProgression == "UNRESTRICTED",
            available = progression == "SELF_FOUND",
            dependencyDepth = 1,
            activeLabel = "ENABLED",
            inactiveLabel = "DISABLED",
            set = function(value) return iRC:SetMaxLevelProgressionMode(value and "UNRESTRICTED" or "SELF_FOUND") end,
        },
        {
            section = "Guild-Found",
            title = "Guild-Found Progression",
            description = "Characters must follow Guild-Found item, money, and trade restrictions throughout levels 1–60.",
            active = progression == "GUILD_FOUND",
            activeLabel = "REQUIRED",
            inactiveLabel = "NOT REQUIRED",
            set = function(value) return iRC:SetProgressionMode(value and "GUILD_FOUND" or "NONE") end,
        },
        {
            section = "Guild-Found",
            title = "Self-Found or Guild-Found Progression",
            description = "Throughout levels 1–60, each character may qualify through either verified Self-Found or verified Guild-Found progression.",
            active = progression == "SELF_FOUND_OR_GUILD_FOUND",
            activeLabel = "REQUIRED",
            inactiveLabel = "NOT REQUIRED",
            set = function(value) return iRC:SetProgressionMode(value and "SELF_FOUND_OR_GUILD_FOUND" or "NONE") end,
        },
        {
            section = "Group Rules",
            title = "Guild-Only Groups",
            description = "From level " .. tostring(rules.guildGroupsMinimumLevel or 1)
                .. " through level 60, parties and raids may contain only members of this guild.",
            active = rules.guildGroupsOnly == true,
            activeLabel = "REQUIRED",
            inactiveLabel = "NOT REQUIRED",
            set = function(value) return iRC:SetConnectionRule("guildGroupsOnly", value) end,
        },
        {
            section = "Guild-Found",
            title = "Approved Guild-Found Trade Exceptions",
            description = "At any level where Guild-Found rules apply, items in the guild's approved exception list may be traded as configured.",
            active = guildFoundRuleActive and rules.guildFoundTradeExceptions == true,
            available = guildFoundRuleActive,
            activeLabel = "ALLOWED",
            inactiveLabel = "NOT ALLOWED",
            dependencyDepth = 1,
            set = function(value) return iRC:SetConnectionRule("guildFoundTradeExceptions", value) end,
        },
        {
            section = "Guild Features",
            title = "Guild Member Map",
            description = "At every level, participating guild members may share their current position and appear as pins on the world map.",
            active = rules.guildMapEnabled == true,
            activeLabel = "ENABLED",
            inactiveLabel = "DISABLED",
            set = function(value) return iRC:SetConnectionRule("guildMapEnabled", value) end,
        },
        {
            section = "Announcements",
            title = "Level 60 Guild Announcements",
            description = "Send a guild-chat announcement when an eligible character reaches level 60.",
            active = rules.enableGuildLevel60Message == true,
            activeLabel = "ENABLED",
            inactiveLabel = "DISABLED",
            set = function(value) return iRC:SetConnectionRule("enableGuildLevel60Message", value) end,
        },
        {
            section = "Announcements",
            title = "Hardcore Death Guild Announcements",
            description = iRC:IsOfficialHardcoreRealm()
                and "On this official Hardcore realm, send a guild-chat announcement when a character permanently dies at any level."
                or "Available only on official Hardcore realms. Death announcements remain disabled on this realm.",
            active = iRC:IsOfficialHardcoreRealm() and rules.enableGuildDeathMessage == true,
            available = iRC:IsOfficialHardcoreRealm(),
            activeLabel = "ENABLED",
            inactiveLabel = "DISABLED",
            set = function(value) return iRC:SetConnectionRule("enableGuildDeathMessage", value) end,
        },
    }

    local visible = {}
    for sourceIndex, entry in ipairs(entries) do
        entry.sourceIndex = sourceIndex
        -- Preserve the configured rules while the connection is disabled,
        -- but do not present any of them as currently enforced.
        if not entry.activation and not connectionActive then entry.active = false end
        if canEdit or entry.active or entry.activation then visible[#visible + 1] = entry end
    end
    local sectionOrder = {
        ["Guild Connection"] = 1, ["Guild Features"] = 2, Announcements = 3,
        ["Race-Locked"] = 4, ["Group Rules"] = 5, ["Self-Found"] = 6, ["Guild-Found"] = 7,
    }
    table.sort(visible, function(a, b)
        local aOrder, bOrder = sectionOrder[a.section] or 99, sectionOrder[b.section] or 99
        if aOrder ~= bOrder then return aOrder < bOrder end
        return a.sourceIndex < b.sourceIndex
    end)
    if not frame.rulesEmpty then
        frame.rulesEmpty = frame.scrollContent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        frame.rulesEmpty:SetPoint("TOPLEFT", frame.scrollContent, "TOPLEFT", 14, -14)
        frame.rulesEmpty:SetPoint("RIGHT", frame.scrollContent, "RIGHT", -14, 0)
        frame.rulesEmpty:SetJustifyH("LEFT")
        frame.rulesEmpty:SetText("No active guild rules have been published.")
    end
    frame.rulesEmpty:SetShown(#visible == 0)
    frame.ruleRows = frame.ruleRows or {}
    frame.ruleSectionHeaders = frame.ruleSectionHeaders or {}
    local sectionIndex, yOffset, lastSection = 0, 0, nil
    for index, entry in ipairs(visible) do
        if entry.section ~= lastSection then
            sectionIndex = sectionIndex + 1
            local header = frame.ruleSectionHeaders[sectionIndex]
            if not header then
                header = CreateFrame("Frame", nil, frame.scrollContent, "BackdropTemplate")
                header:SetHeight(22)
                createBackdrop(header, { 0.13, 0.085, 0.035, 0.96 }, { 0.48, 0.35, 0.16, 1 })
                header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                header.text:SetPoint("LEFT", header, "LEFT", 12, 0)
                header.text:SetTextColor(unpack(COLORS.gold))
                frame.ruleSectionHeaders[sectionIndex] = header
            end
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", frame.scrollContent, "TOPLEFT", 0, -yOffset)
            header:SetPoint("TOPRIGHT", frame.scrollContent, "TOPRIGHT", 0, -yOffset)
            header.text:SetText(entry.section)
            header:Show()
            yOffset = yOffset + 27
            lastSection = entry.section
        end
        local row = frame.ruleRows[index]
        if not row then
            row = makeGuildRuleRow(frame.scrollContent, index)
            frame.ruleRows[index] = row
        end
        local dependencyDepth = tonumber(entry.dependencyDepth) or 0
        local leftInset = 10 + dependencyDepth * 18
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.scrollContent, "TOPLEFT", leftInset, -yOffset)
        row:SetPoint("TOPRIGHT", frame.scrollContent, "TOPRIGHT", -10, -yOffset)
        row.dependencyVertical:ClearAllPoints()
        row.dependencyHorizontal:ClearAllPoints()
        if dependencyDepth > 0 then
            -- Draw an L from the dependency branch above into this rule card.
            row.dependencyVertical:SetPoint("TOPLEFT", row, "TOPLEFT", -10, 7)
            row.dependencyVertical:SetPoint("BOTTOMLEFT", row, "LEFT", -10, 0)
            row.dependencyHorizontal:SetPoint("LEFT", row.dependencyVertical, "BOTTOMLEFT", 0, 0)
            row.dependencyHorizontal:SetPoint("RIGHT", row, "LEFT", 1, 0)
            row.dependencyVertical:Show()
            row.dependencyHorizontal:Show()
        else
            row.dependencyVertical:Hide()
            row.dependencyHorizontal:Hide()
        end
        row.title:SetText(entry.title)
        row.description:SetText(entry.description)
        row.state:SetText(entry.active and (entry.activeLabel or "ACTIVE") or (entry.inactiveLabel or "INACTIVE"))
        local editable = canEdit and (entry.activation or connectionActive) and entry.available ~= false
        local blocked = canEdit and not editable
        local currentEntry, currentEditable = entry, editable
        row:SetEnabled(editable and true or false)
        row:SetAlpha(blocked and 0.45 or 1)
        row.title:SetTextColor(blocked and 0.62 or 1, blocked and 0.62 or 1, blocked and 0.62 or 1)
        row.description:SetTextColor(blocked and 0.42 or 0.62, blocked and 0.42 or 0.62, blocked and 0.42 or 0.62)
        local requiredWarning = entry.requiredWhenInactive and not entry.active
        row.state:SetTextColor(requiredWarning and 1 or (blocked and 0.50 or (entry.active and 0.25 or 0.62)),
            requiredWarning and 0.18 or (blocked and 0.50 or (entry.active and 1 or 0.62)),
            requiredWarning and 0.12 or (blocked and 0.50 or (entry.active and 0.35 or 0.62)))
        row.stateBackground:SetColorTexture(requiredWarning and 0.24 or (entry.active and 0.04 or 0.10),
            requiredWarning and 0.025 or (entry.active and 0.24 or 0.085),
            requiredWarning and 0.02 or (entry.active and 0.08 or 0.06), blocked and 0.32 or 0.82)
        row.accent:SetColorTexture(blocked and 0.35 or (entry.active and 0.20 or 0.62),
            blocked and 0.35 or (entry.active and 0.86 or 0.42),
            blocked and 0.35 or (entry.active and 0.30 or 0.18), 1)
        row:SetBackdropColor(entry.active and 0.045 or 0.075, entry.active and 0.12 or 0.065,
            entry.active and 0.055 or 0.05, editable and 0.98 or 0.72)
        row:SetBackdropBorderColor(requiredWarning and 0.85 or (entry.active and 0.20 or 0.30),
            requiredWarning and 0.12 or (entry.active and 0.72 or 0.26),
            requiredWarning and 0.08 or (entry.active and 0.27 or 0.19), 1)
        row:SetScript("OnClick", function()
            if not currentEditable then return end
            if currentEntry.activation and currentEntry.active then
                UI:ConfirmDisableGuildConnection()
                return
            end
            if currentEntry.set(not currentEntry.active) ~= false then UI:Refresh() end
        end)
        row:Show()
        yOffset = yOffset + 48
    end
    for index = #visible + 1, #frame.ruleRows do frame.ruleRows[index]:Hide() end
    for index = sectionIndex + 1, #frame.ruleSectionHeaders do frame.ruleSectionHeaders[index]:Hide() end

    frame.scrollContent:SetHeight(math.max(1, yOffset))
    frame.contentTitle:SetText("Guild Rules")
    if viewAsMember then
        frame.contentSubtitle:SetText("Member preview: only active guild rules are shown.")
    elseif canEdit then
        frame.contentSubtitle:SetText(connectionActive
            and "Click a rule to activate or deactivate it. Race-Locked can be combined with Self-Found or Guild-Found progression."
            or "Enable iRC for this guild to configure and synchronize guild rules.")
    else
        frame.contentSubtitle:SetText(connectionActive
            and "Active guild rules. Only the Guild Master can change this ruleset."
            or iRC:Text("CONNECTION_DETAIL_INACTIVE",
                connection and connection.guildName or (GetGuildInfo and GetGuildInfo("player")) or "this guild"))
    end
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
local CLASS_BREAKDOWN_ORDER = {
    "WARRIOR", "HUNTER", "MAGE", "ROGUE", "PRIEST", "WARLOCK", "PALADIN", "DRUID", "SHAMAN",
}

local function classBreakdownTitle(group)
    local mode = group and group.classBreakdownMode or "ALL"
    if mode == "MAX" then return iRC:Text("GUILD_STATS_CLASS_BREAKDOWN_MAX") end
    if mode == "RANGE" then
        return iRC:Text("GUILD_STATS_CLASS_BREAKDOWN_RANGE",
            tonumber(group.classBreakdownMinLevel) or 1, tonumber(group.classBreakdownMaxLevel) or 60)
    end
    return iRC:Text("GUILD_STATS_CLASS_BREAKDOWN")
end

local function updateClassBreakdown(card, classes, totalMembers)
    local classGroups = {}
    totalMembers = 0
    for _, class in ipairs(CLASS_BREAKDOWN_ORDER) do
        local count = tonumber((classes or {})[class]) or 0
        if count > 0 then
            classGroups[#classGroups + 1] = { class = class, count = count }
            totalMembers = totalMembers + count
        end
    end
    local usedWidth = 0
    local availableWidth = math.max(1, (card:GetWidth() or 651) - 36)
    for index, group in ipairs(classGroups) do
        local share = totalMembers > 0 and group.count / totalMembers or 0
        local percent = math.floor(share * 100 + 0.5)
        local segment = card.classSegments[index]
        if not segment then
            segment = CreateFrame("Frame", nil, card.classBar, "BackdropTemplate")
            segment:SetHeight(10)
            segment:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            segment:EnableMouse(true)
            segment:SetScript("OnEnter", function(self)
                if not GameTooltip or not self.className then return end
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(self.className, self.red or 1, self.green or 1, self.blue or 1)
                GameTooltip:AddLine(iRC:Text("GUILD_STATS_CLASS_MEMBERS", self.count or 0), 1, 1, 1)
                GameTooltip:AddLine(iRC:Text("GUILD_STATS_CLASS_SHARE", self.percent or 0), 0.75, 0.75, 0.75)
                GameTooltip:Show()
            end)
            segment:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            card.classSegments[index] = segment
        end
        segment:ClearAllPoints()
        segment:SetPoint("LEFT", card.classBar, "LEFT", 2 + usedWidth, 0)
        local width = index == #classGroups and availableWidth - usedWidth or math.floor(availableWidth * share)
        segment:SetWidth(math.max(1, width))
        local red, green, blue = getClassColor(group.class)
        segment:SetBackdropColor(red, green, blue, 1)
        segment:SetBackdropBorderColor(0.02, 0.02, 0.02, 1)
        segment.className = _G["LOCALIZED_CLASS_NAMES_MALE"] and _G["LOCALIZED_CLASS_NAMES_MALE"][group.class]
            or group.class:sub(1, 1) .. group.class:sub(2):lower()
        segment.count = group.count
        segment.percent = share * 100
        segment.red, segment.green, segment.blue = red, green, blue
        segment:Show()
        local label = card.classLabels[index]
        if not label then
            label = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            label:SetJustifyH("CENTER")
            card.classLabels[index] = label
        end
        label:ClearAllPoints()
        label:SetPoint("BOTTOMLEFT", card.classBar, "TOPLEFT", 2 + usedWidth, 2)
        label:SetWidth(math.max(1, width))
        label:SetText((CLASS_SHORT_NAMES[group.class] or group.class) .. " " .. (percent == 0 and "<1" or percent) .. "%")
        label:SetTextColor(red, green, blue)
        label:SetShown(share >= 0.10)
        usedWidth = usedWidth + width
    end
    for index = #classGroups + 1, #card.classSegments do card.classSegments[index]:Hide() end
    for index = #classGroups + 1, #card.classLabels do card.classLabels[index]:Hide() end
    card.classText:SetText(#classGroups == 0 and iRC:Text("GUILD_STATS_NO_DATA") or "")
end

local function guildCardKey(group)
    return string.lower(tostring(group.guildName or "")) .. "@" .. tostring(group.race or "")
end

local function getActiveRuleLines(group)
    if not group.rulesKnown or type(group.rules) ~= "table" then return { iRC:Text("GUILD_STATS_RULES_UNKNOWN") } end
    local rules, lines = group.rules, {}
    if rules.requireIRC then lines[#lines + 1] = iRC:Text("GUILD_STATS_RULE_REQUIRE_IRC") end
    if rules.raceLock then lines[#lines + 1] = iRC:Text("GUILD_STATS_RULE_RACE_LOCK") end
    if rules.raceLock and rules.nativeTongueOnly then lines[#lines + 1] = iRC:Text("GUILD_STATS_RULE_NATIVE_TONGUE") end
    local progressionMode = iRC:GetProgressionMode(rules)
    if progressionMode == "GUILD_FOUND" then
        lines[#lines + 1] = iRC:Text("GUILD_STATS_RULE_GUILD_FOUND")
    elseif progressionMode == "SELF_FOUND_OR_GUILD_FOUND" then
        lines[#lines + 1] = iRC:Text("GUILD_STATS_RULE_HYBRID")
    elseif progressionMode == "SELF_FOUND" then
        local maxMode = iRC:GetMaxLevelProgressionMode(rules)
        if maxMode == "GUILD_FOUND" then lines[#lines + 1] = iRC:Text("GUILD_STATS_RULE_SELF_FOUND_TO_GF")
        elseif maxMode == "UNRESTRICTED" then lines[#lines + 1] = iRC:Text("GUILD_STATS_RULE_SELF_FOUND_TO_FREE")
        else lines[#lines + 1] = iRC:Text("GUILD_STATS_RULE_SELF_FOUND_REMAIN") end
    else
        lines[#lines + 1] = iRC:Text("GUILD_STATS_RULE_NO_PROGRESSION")
    end
    if rules.raceLock and rules.sameRaceGroupsOnly then lines[#lines + 1] = iRC:Text("GUILD_STATS_RULE_SAME_RACE", rules.sameRaceMinimumLevel or 1) end
    if rules.raceLock and rules.allowLevel60MixedRaceGroups then lines[#lines + 1] = iRC:Text("GUILD_STATS_RULE_MIXED_RACE_60") end
    if rules.guildGroupsOnly then lines[#lines + 1] = iRC:Text("GUILD_STATS_RULE_GUILD_ONLY", rules.guildGroupsMinimumLevel or 1) end
    if rules.guildFoundTradeExceptions then lines[#lines + 1] = iRC:Text("GUILD_STATS_RULE_TRADE_EXCEPTIONS") end
    if rules.guildMapEnabled then lines[#lines + 1] = iRC:Text("GUILD_STATS_RULE_GUILD_MAP") end
    if #lines == 0 then lines[1] = iRC:Text("GUILD_STATS_NO_ACTIVE_RULES") end
    for index, line in ipairs(lines) do lines[index] = "- " .. line end
    return lines
end

local function getGuildProfileLines(group)
    local description = tostring(group.guildDescription or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if description == "" then description = iRC:Text("GUILD_STATS_NO_DESCRIPTION") end
    local lines = {
        description,
    }
    if (tonumber(group.guildDescriptionTimestamp) or 0) > 0 and tostring(group.guildDescriptionEditedBy or "") ~= "" then
        lines[#lines + 1] = iRC.Colors.Gray
            .. iRC:Text("GUILD_STATS_DESCRIPTION_META", iRC:FormatPlayerName(group.guildDescriptionEditedBy),
                date("%Y-%m-%d %H:%M", group.guildDescriptionTimestamp))
            .. iRC.Colors.Reset
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = iRC:Text("GUILD_STATS_ACTIVE_RULES") .. ":"
    for _, line in ipairs(getActiveRuleLines(group)) do lines[#lines + 1] = line end
    return lines
end

local function guildCardHeight(group, forceExpanded)
    if not forceExpanded and not expandedGuildCards[guildCardKey(group)] then return 138 end
    local descriptionLines = math.max(1, math.ceil(#tostring(group.guildDescription or "") / 72))
    return 210 + #getGuildProfileLines(group) * 14 + (descriptionLines - 1) * 14
end

local function setRaceCard(card, group, rank, forceExpanded)
    local rules = group and group.rulesKnown and group.rules
    local accent = rules and rules.raceLock == true and (RACE_COLORS[group.race] or RACE_COLORS.Unknown)
        or isGuildFoundRules(rules)
            and { 0.30, 1, 0.35 } or RACE_COLORS.Unknown
    card.accent:SetColorTexture(accent[1], accent[2], accent[3], 1)
    card.icon:SetTexture(getGuildCardIcon(group))
    card.race:SetText(group.guildName or iRC:Text("GUILD_STATS_UNKNOWN_GUILD"))
    card.rank:SetText("#" .. rank)
    local tag, tagColor = getGuildCardTag(group)
    card.tag:SetText(tag and ("[" .. tag .. "]") or "")
    if tagColor then card.tag:SetTextColor(tagColor[1], tagColor[2], tagColor[3]) end
    card.tag:SetShown(tag ~= nil)
    card.average:SetText(group.activeLevel30 ~= nil and formatNumber(group.activeLevel30) or "—")
    card.members:SetText(formatNumber(group.activePlayers or 0))
    card.total:SetText(group.activeMembers ~= nil and formatNumber(group.activeMembers) or "—")
    card.totalMembers:SetText(formatNumber(group.members or 0))
    card.report = group
    card.guildKey = guildCardKey(group)
    local expanded = forceExpanded or expandedGuildCards[card.guildKey]
    local reportTime = tonumber(group.timestamp) and group.timestamp > 0
        and date("%Y-%m-%d %H:%M", group.timestamp) or iRC:Text("RULESET_METADATA_UNKNOWN")
    local reportSender = iRC:FormatPlayerName(group.relayedBy or group.name or iRC:Text("RULESET_METADATA_UNKNOWN"))
    card.freshness:SetText(iRC:Text("GUILD_STATS_REPORT_META", reportTime, reportSender)
        .. (group.cached and (" · " .. iRC:Text("RL_GRID_CACHED")) or ""))
    card.expandHint:SetText(iRC:Text(expanded and "GUILD_STATS_COLLAPSE_RULES" or "GUILD_STATS_EXPAND_RULES"))
    card.rulesSeparator:SetShown(expanded and true or false)
    card.rulesTitle:SetShown(expanded and true or false)
    card.rulesText:SetShown(expanded and true or false)
    card.contactsLabel:SetShown(expanded and true or false)
    if expanded then
        card.rulesText:SetText(table.concat(getGuildProfileLines(group), "\n"))
        card.contactsLabel:ClearAllPoints()
        card.contactsLabel:SetPoint("TOPLEFT", card.rulesText, "BOTTOMLEFT", 0, -10)
        local contacts, originalIndex = {}, 0
        local onlineMask = math.floor(tonumber(group.guildContactsOnlineMask) or 0)
        local onlineSnapshotFresh = tonumber(group.timestamp) and time() - tonumber(group.timestamp) <= 1800
        for name in tostring(group.guildContacts or ""):gmatch("[^,]+") do
            name = name:gsub("^%s+", ""):gsub("%s+$", "")
            if name ~= "" and #contacts < 5 then
                originalIndex = originalIndex + 1
                contacts[#contacts + 1] = {
                    name = name, order = originalIndex,
                    online = onlineSnapshotFresh and math.floor(onlineMask / (2 ^ (originalIndex - 1))) % 2 == 1,
                }
            end
        end
        table.sort(contacts, function(a, b)
            if a.online ~= b.online then return a.online end
            return a.order < b.order
        end)
        card.contactsLabel:SetText(#contacts > 0 and (iRC:Text("GUILD_CONTACTS_LABEL") .. ":") or iRC:Text("GUILD_STATS_NO_CONTACTS"))
        local previousButton
        for index, contact in ipairs(contacts) do
            local button = card.contactButtons[index]
            if not button then
                button = CreateFrame("Button", nil, card)
                button:SetHeight(18)
                button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                button.text:SetAllPoints(); button.text:SetJustifyH("LEFT")
                button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
                button.highlight:SetAllPoints(); button.highlight:SetColorTexture(1, 0.55, 0, 0.15)
                card.contactButtons[index] = button
            end
            local contactName = contact.name
            local displayName = iRC:FormatInviteContactName(contact.name)
            button:ClearAllPoints()
            if previousButton then button:SetPoint("LEFT", previousButton, "RIGHT", 6, 0)
            else button:SetPoint("LEFT", card.contactsLabel, "RIGHT", 8, 0) end
            button.text:SetText(contact.online
                and ("|TInterface\\FriendsFrame\\StatusIcon-Online:10:10:0:0|t " .. displayName) or displayName)
            button:SetWidth(math.max(55, button.text:GetStringWidth() + 14))
            button:SetScript("OnClick", function()
                local playerFaction = UnitFactionGroup and UnitFactionGroup("player")
                if playerFaction and group.faction and playerFaction ~= group.faction then
                    iRC:Print(iRC:Text("GUILD_CONTACT_CROSS_FACTION"))
                    return
                end
                iRC:OpenWhisper(contactName)
            end)
            button:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(iRC:Text("GUILD_CONTACT_WHISPER", displayName)); GameTooltip:Show()
            end)
            button:SetScript("OnLeave", function() GameTooltip:Hide() end)
            button:Show(); previousButton = button
        end
        for index = #contacts + 1, #card.contactButtons do card.contactButtons[index]:Hide() end
    else
        for _, button in ipairs(card.contactButtons) do button:Hide() end
    end
    card.classesTitle:SetText(classBreakdownTitle(group))
    updateClassBreakdown(card, group.classBreakdownClasses or group.classes, group.members)
    card:Show()
end

function UI:CreateGuildHomepagePreview(parent)
    local preview = CreateFrame("Frame", nil, parent)
    preview:SetHeight(450)

    preview.title = preview:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    preview.title:SetPoint("TOPLEFT", preview, "TOPLEFT", 2, 0)
    preview.title:SetText(iRC:Text("GUILD_HOMEPAGE_PREVIEW"))
    preview.title:SetTextColor(unpack(COLORS.gold))

    preview.card = makeRaceCard(preview)
    preview.card:SetPoint("TOPLEFT", preview, "TOPLEFT", 0, -22)
    preview.card:SetPoint("TOPRIGHT", preview, "TOPRIGHT", 0, -22)
    preview.card:SetScript("OnMouseUp", nil)
    preview.card:EnableMouse(false)

    preview.empty = preview:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    preview.empty:SetPoint("TOPLEFT", preview, "TOPLEFT", 16, -48)
    preview.empty:SetPoint("TOPRIGHT", preview, "TOPRIGHT", -16, -48)
    preview.empty:SetJustifyH("CENTER")
    preview.empty:SetText(iRC:Text("GUILD_HOMEPAGE_PREVIEW_UNAVAILABLE"))

    function preview:Refresh()
        local group = iRC.RaceGrid and iRC.RaceGrid:GetLocalReport()
        if type(group) ~= "table" or not group.guildName or group.guildName == "" then
            self.card:Hide()
            self.empty:Show()
            return
        end

        setRaceCard(self.card, group, 1, true)
        self.card:SetHeight(guildCardHeight(group, true))
        self.card.rank:SetText(iRC:Text("GUILD_HOMEPAGE_PREVIEW_BADGE"))
        self.card.expandHint:SetText(iRC:Text("GUILD_HOMEPAGE_PREVIEW_EXPANDED"))
        for _, button in ipairs(self.card.contactButtons) do button:EnableMouse(false) end
        self.empty:Hide()
    end

    preview:Refresh()
    return preview
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
            entry.icon:SetTexture(getGuildCardIcon(group))
            entry.race:SetText(group.guildName or iRC:Text("GUILD_STATS_UNKNOWN_GUILD"))
            local tag, tagColor = getGuildCardTag(group)
            local showTag = guildStatsFilter == "ALL" and tag ~= nil
            entry.race:ClearAllPoints()
            entry.race:SetPoint("LEFT", entry.rank, "RIGHT", 5, showTag and 7 or 0)
            entry.race:SetPoint("RIGHT", entry, "RIGHT", -8, showTag and 7 or 0)
            entry.tag:SetText(showTag and ("[" .. tag .. "]") or "")
            if tagColor then entry.tag:SetTextColor(tagColor[1], tagColor[2], tagColor[3]) end
            entry.tag:SetShown(showTag)
        else
            entry.icon:SetTexture("Interface\\Icons\\Achievement_General")
            entry.race:SetText(iRC:Text("GUILD_STATS_NO_DATA"))
            entry.race:ClearAllPoints()
            entry.race:SetPoint("LEFT", entry.rank, "RIGHT", 5, 0)
            entry.race:SetPoint("RIGHT", entry, "RIGHT", -8, 0)
            entry.tag:Hide()
        end
        entry:Show()
    end
    frame.racePodium:Show()
end

local function updateRaceOverview(frame)
    local allGroups = iRC:GetRaceGridOverview()
    if guildStatsFilter == "RACE_LOCKED" then
        local filtered = {}
        for _, group in ipairs(allGroups) do
            if group.rulesKnown and group.rules and group.rules.raceLock == true then filtered[#filtered + 1] = group end
        end
        allGroups = filtered
    elseif guildStatsFilter == "GUILD_FOUND" then
        local filtered = {}
        for _, group in ipairs(allGroups) do
            if group.rulesKnown and group.rules and group.rules.raceLock == false
                and isGuildFoundRules(group.rules) then
                filtered[#filtered + 1] = group
            end
        end
        allGroups = filtered
    elseif guildStatsFilter == "SELF_FOUND" then
        local filtered = {}
        for _, group in ipairs(allGroups) do
            if group.rulesKnown and group.rules and group.rules.raceLock ~= true
                and iRC:GetProgressionMode(group.rules) == "SELF_FOUND"
                and iRC:GetMaxLevelProgressionMode(group.rules) == "SELF_FOUND" then
                filtered[#filtered + 1] = group
            end
        end
        allGroups = filtered
    end
    local searchText = frame.guildStatsSearch and frame.guildStatsSearch:GetText() or ""
    searchText = searchText:match("^%s*(.-)%s*$"):lower()
    if searchText ~= "" then
        local filtered = {}
        for _, group in ipairs(allGroups) do
            if tostring(group.guildName or ""):lower():find(searchText, 1, true) then
                filtered[#filtered + 1] = group
            end
        end
        allGroups = filtered
    end
    local ranks = {}
    for index, group in ipairs(allGroups) do ranks[group.guildName] = index end

    local gap, contentWidth = 9, 675
    updateRacePodium(frame, allGroups)
    local usedCards, yOffset = 0, 95

    local playerFaction = UnitFactionGroup and UnitFactionGroup("player") or "Horde"
    local factionOrder = playerFaction == "Alliance" and { "Alliance", "Horde" } or { "Horde", "Alliance" }
    local ownGuildName = GetGuildInfo and GetGuildInfo("player") or ""
    local ownGuildKey = ownGuildName:match("^%s*(.-)%s*$"):lower()
    local ownGuilds = {}
    if ownGuildKey ~= "" then
        for _, group in ipairs(allGroups) do
            if tostring(group.guildName or ""):match("^%s*(.-)%s*$"):lower() == ownGuildKey then
                ownGuilds[1] = group
                break
            end
        end
    end

    local function renderGuildSection(sectionKey, title, guilds)
        local section = frame.factionSections[sectionKey]
        if not section then
            section = makeFactionSection(frame.scrollContent, sectionKey, title)
            frame.factionSections[sectionKey] = section
        end
        local collapsed = collapsedFactionSections[sectionKey] == true
        section.title:SetText((collapsed and "+ " or "- ") .. title .. " (" .. #guilds .. ")")
        local cardsHeight = 0
        if not collapsed then
            for index, group in ipairs(guilds) do cardsHeight = cardsHeight + guildCardHeight(group) + (index > 1 and gap or 0) end
        end
        local sectionHeight = collapsed and 36 or (44 + cardsHeight + 10)
        section:ClearAllPoints()
        section:SetSize(contentWidth, sectionHeight)
        section:SetPoint("TOPLEFT", frame.scrollContent, "TOPLEFT", 0, -yOffset)
        section:Show()
        local cardWidth = contentWidth - 24
        local cardOffset = 36
        for _, group in ipairs(collapsed and {} or guilds) do
            usedCards = usedCards + 1
            local card = frame.raceCards[usedCards]
            if not card then
                card = makeRaceCard(section)
                frame.raceCards[usedCards] = card
            elseif card:GetParent() ~= section then
                card:SetParent(section)
            end
            local cardHeight = guildCardHeight(group)
            card:ClearAllPoints()
            card:SetSize(cardWidth, cardHeight)
            card:SetPoint("TOPLEFT", section, "TOPLEFT", 12, -cardOffset)
            setRaceCard(card, group, ranks[group.guildName] or usedCards)
            cardOffset = cardOffset + cardHeight + gap
        end
        yOffset = yOffset + sectionHeight + gap
    end

    if #ownGuilds > 0 then
        renderGuildSection("MyGuild", iRC:Text("GUILD_STATS_MY_GUILD"), ownGuilds)
    elseif frame.factionSections.MyGuild then
        frame.factionSections.MyGuild:Hide()
    end
    for _, faction in ipairs(factionOrder) do
        local guilds = {}
        for _, group in ipairs(allGroups) do
            local groupKey = tostring(group.guildName or ""):match("^%s*(.-)%s*$"):lower()
            if group.faction == faction and groupKey ~= ownGuildKey then guilds[#guilds + 1] = group end
        end
        renderGuildSection(faction, faction, guilds)
    end
    for index = usedCards + 1, #frame.raceCards do frame.raceCards[index]:Hide() end
    for _, row in ipairs(frame.memberRows) do row:Hide() end
    frame.scrollContent:SetHeight(math.max(1, yOffset - gap))
    frame.scroll:SetVerticalScroll(UI.preservedRaceScroll or 0)
    UI.preservedRaceScroll = nil
    frame.contentTitle:SetText(iRC:Text("GUILD_STATS_TITLE"))
    frame.contentSubtitle:SetText(iRC:Text("RL_GRID_OVERVIEW_DESC"))
    return #allGroups
end

function UI:Refresh()
    self.pendingRefresh = nil
    local frame = self:Create()
    local preservedGuildRulesScroll = frame.category == "Guild Rules" and frame.scroll
        and frame.scroll:GetVerticalScroll() or nil
    if frame.LayoutNavigation then frame.LayoutNavigation() end
    local managementPanelKey = MANAGEMENT_PANEL_KEYS[frame.category]
    local dashboardTab = DASHBOARD_PANEL_TABS[frame.category]
    if managementPanelKey then
        if iRC.ConnectionDashboard and iRC.ConnectionDashboard.HideEmbedded then iRC.ConnectionDashboard:HideEmbedded() end
        if iRC.ShowManagementPanel then iRC:ShowManagementPanel(managementPanelKey, frame.main) end
    elseif dashboardTab then
        if iRC.HideManagementPanels then iRC:HideManagementPanels() end
        if iRC.ConnectionDashboard and iRC.ConnectionDashboard.ShowEmbedded then
            iRC.ConnectionDashboard:ShowEmbedded(frame.main, frame, dashboardTab)
        end
    elseif iRC.HideManagementPanels then
        iRC:HideManagementPanels()
        if iRC.ConnectionDashboard and iRC.ConnectionDashboard.HideEmbedded then iRC.ConnectionDashboard:HideEmbedded() end
    end
    if frame.category ~= "Guild Members" then
        frame.professionReport:Hide()
        frame.memberMenu:Hide()
    end
    frame.serverNameHeader:SetText(currentServerNavigationName())
    frame.guildNameHeader:SetText(currentGuildNavigationName())
    local embeddedManagement = managementPanelKey or dashboardTab
    frame.raceRefresh:SetShown(not embeddedManagement and frame.category == "Race Overview")
    frame.guildOverviewRefresh:SetShown(not embeddedManagement and frame.category == "Guild Overview")
    frame.guildOverviewAltToggle:SetShown(not embeddedManagement and frame.category == "Guild Overview")
    local showRulesViewToggle = frame.category == "Guild Rules" and iRC:IsGuildMaster()
    frame.rulesViewToggle:SetShown(showRulesViewToggle)
    if showRulesViewToggle then
        frame.rulesViewToggle.text:SetText(frame.rulesViewAsMember and "Back to edit" or "View as member")
        frame.rulesViewToggle:SetBackdropColor(frame.rulesViewAsMember and 0.18 or 0.055,
            frame.rulesViewAsMember and 0.09 or 0.045, frame.rulesViewAsMember and 0.025 or 0.035, 0.98)
        frame.rulesViewToggle:SetBackdropBorderColor(frame.rulesViewAsMember and COLORS.gold[1] or 0.28,
            frame.rulesViewAsMember and COLORS.gold[2] or 0.23, frame.rulesViewAsMember and COLORS.gold[3] or 0.16,
            frame.rulesViewAsMember and 1 or 0.9)
    end
    frame.memberProfessionSearch:SetShown(not embeddedManagement and frame.category == "Guild Members")
    if frame.category ~= "Guild Members" then frame.memberProfessionSearch.suggestions:Hide() end
    frame.guildStatsSearch:SetShown(not embeddedManagement and frame.category == "Race Overview")
    frame.guildLogSearch:SetShown(not embeddedManagement and frame.category == "Guild Log")
    local showInactiveControls = not embeddedManagement and frame.category == "Inactive Member Management"
    frame.inactiveThreshold:SetShown(showInactiveControls)
    frame.inactiveRemoveAll:SetShown(showInactiveControls)
    frame.scroll:ClearAllPoints()
    frame.scroll:SetPoint("TOPLEFT", frame.main, "TOPLEFT", 15, showInactiveControls and -112 or -78)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame.main, "BOTTOMRIGHT", -31, 14)
    frame.rankManagementControls:SetShown(not embeddedManagement and frame.category == "Rank Management")
    if frame.category ~= "Rank Management" and frame.rankMemberMenu then frame.rankMemberMenu:Hide() end
    if frame.category ~= "Guild Log" then frame.guildLogSearch.suggestions:Hide() end
    if frame.category ~= "Guild Rules" then
        for _, row in ipairs(frame.ruleRows or {}) do row:Hide() end
        for _, header in ipairs(frame.ruleSectionHeaders or {}) do header:Hide() end
        if frame.rulesEmpty then frame.rulesEmpty:Hide() end
    end
    if frame.category ~= "Guild Overview" and frame.guildOverview then frame.guildOverview:Hide() end
    if frame.category ~= "Personal Settings" and frame.personalSettings then frame.personalSettings:Hide() end
    for _, button in ipairs(frame.guildStatsFilters or {}) do
        local shown = frame.category == "Race Overview"
        button:SetShown(shown)
        if shown then
            local active = button.filterKey == guildStatsFilter
            button.activeGlow:SetColorTexture(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], active and 0.18 or 0)
            button:SetBackdropColor(active and 0.18 or 0.055, active and 0.09 or 0.045, active and 0.025 or 0.035, 0.98)
            button:SetBackdropBorderColor(active and COLORS.gold[1] or 0.28, active and COLORS.gold[2] or 0.23,
                active and COLORS.gold[3] or 0.16, active and 1 or 0.9)
            button.text:SetFontObject(active and GameFontHighlight or GameFontNormal)
            button.text:SetTextColor(active and 1 or 0.78, active and 0.82 or 0.72, active and 0.36 or 0.62)
        end
    end
    frame.scroll:ClearAllPoints()
    local usesSearchHeader = frame.category == "Race Overview" or frame.category == "Guild Log"
        or frame.category == "Inactive Member Management" or frame.category == "Rank Management"
    frame.scroll:SetPoint("TOPLEFT", frame.main, "TOPLEFT", 15, usesSearchHeader and -112 or -78)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame.main, "BOTTOMRIGHT", -31, 14)
    frame.scroll:SetShown(not embeddedManagement)
    if frame.scroll.ScrollBar then
        frame.scroll.ScrollBar:SetShown(frame.category ~= "Guild Overview")
    end
    frame.contentTitle:SetShown(not embeddedManagement)
    frame.contentSubtitle:SetShown(not embeddedManagement)
    frame.cacheUpdating:SetShown(frame.category == "Race Overview" and iRC.RaceGrid and iRC.RaceGrid:IsCacheUpdating())
    local connection = iRC:GetConnection()
    if connection and iRC:IsGuildConnectionActive() then
        frame.connectionStatus:SetText(iRC.Colors.Green .. "Connected" .. iRC.Colors.Reset)
        frame.connectionGuild:SetText(connection.guildName or (GetGuildInfo and GetGuildInfo("player")) or "")
    elseif connection then
        frame.connectionStatus:SetText(iRC.Colors.Yellow .. "iRC disabled" .. iRC.Colors.Reset)
        frame.connectionGuild:SetText((connection.guildName or "Guild") .. " · Shared rules and sync are inactive")
    else
        frame.connectionStatus:SetText(iRC.Colors.Red .. "Not connected" .. iRC.Colors.Reset)
        frame.connectionGuild:SetText("Join a guild to use guild sync")
    end
    local profile = getProfile(frame)
    local name = iRC:FormatPlayerName(profile and profile.name or frame.subjectName or iRC:GetPlayerName())
    local race, class, level = profile and profile.race or "Unknown", profile and profile.class or "Unknown", profile and profile.level or 1
    frame.player:SetText(name .. "  " .. iRC.Colors.Gray .. race .. " " .. class .. " · Level " .. level .. iRC.Colors.Reset)
    for category, tab in pairs(frame.tabs) do setTabAppearance(tab, frame.category == category) end
    if frame.category == "Guild Overview" then
        frame.player:SetText((connection and connection.guildName or "No guild") .. iRC.Colors.Gray
            .. "  Membership, activity, and iRC adoption" .. iRC.Colors.Reset)
        updateGuildOverview(frame)
    elseif frame.category == "Guild Members" then
        updateMemberRows(frame)
    elseif frame.category == "Guild Log" then
        updateGuildLog(frame)
    elseif frame.category == "Inactive Member Management" then
        updateInactiveMembers(frame)
    elseif frame.category == "Rank Management" then
        updateRankManagement(frame)
    elseif frame.category == "Guild Rules" then
        frame.player:SetText((connection and connection.guildName or "No guild") .. iRC.Colors.Gray
            .. "  Guild connection and shared rules" .. iRC.Colors.Reset)
        updateGuildRules(frame)
    elseif frame.category == "Personal Settings" then
        frame.player:SetText(iRC:FormatPlayerName(iRC:GetPlayerName()) .. iRC.Colors.Gray
            .. "  Personal iRC preferences" .. iRC.Colors.Reset)
        updatePersonalSettings(frame)
    elseif embeddedManagement then
        frame.player:SetText((connection and connection.guildName or "No guild") .. iRC.Colors.Gray
            .. "  Delegated guild management" .. iRC.Colors.Reset)
    elseif frame.category == "Race Overview" then
        frame.player:SetText((connection and connection.guildName or "No guild") .. iRC.Colors.Gray .. "  " .. iRC:Text("GUILD_STATS_HEADER_DESC") .. iRC.Colors.Reset)
        updateRaceOverview(frame)
    end
    if preservedGuildRulesScroll ~= nil and frame.category == "Guild Rules" and frame.scroll then
        local function restoreGuildRulesScroll()
            if frame.category ~= "Guild Rules" then return end
            local maximum = math.max(0, frame.scrollContent:GetHeight() - frame.scroll:GetHeight())
            frame.scroll:SetVerticalScroll(math.max(0, math.min(maximum, preservedGuildRulesScroll)))
        end
        restoreGuildRulesScroll()
        if C_Timer and C_Timer.After then C_Timer.After(0, restoreGuildRulesScroll) end
    end
end

function UI:OpenCategory(category)
    local frame = self:Create()
    if frame.tabs[category] then
        if frame.category ~= category and (frame.category == "Inactive Member Management"
            or category == "Inactive Member Management") then
            resetInactiveMemberView(frame)
        end
        frame.category = category
    end
    return self:Open(nil, category == "Race Overview", category)
end

function UI:OpenInactiveMembers(days)
    if not iRC:HasGuildPermission("memberRemoval") and not iRC:IsTestAdmin() then
        iRC:Print(iRC.Colors.Red .. "You do not have the delegated inactive-member management permission." .. iRC.Colors.Reset)
        return false
    end
    local frame = self:Create()
    frame.inactiveMemberDays = math.max(0, math.min(9999,
        math.floor(tonumber(days) or 30)))
    frame.category = "Inactive Member Management"
    iRC:RefreshGuildRoster()
    return self:Open(nil, false, "Inactive Member Management")
end

function UI:Open(subjectName, requestCacheFromOpen, requestedCategory)
    if not iRC:CanOpenPanel() then return false end
    local frame = self:Create()
    local opening = not frame:IsShown()
    if iRC.CloseWindowsExcept then iRC:CloseWindowsExcept(frame) end
    frame.subjectName = subjectName or iRC:GetPlayerName()
    if requestedCategory and frame.tabs[requestedCategory] then
        frame.category = requestedCategory
    elseif opening then
        local defaultTab = iRC:GetSettings().mainPanelDefaultTab or DEFAULT_OPEN_LAST
        if defaultTab ~= DEFAULT_OPEN_LAST and frame.tabs[defaultTab] then frame.category = defaultTab end
    end
    if not frame.category or not frame.tabs[frame.category] then frame.category = "Race Overview" end
    if frame.category == "Race Overview" then
        guildStatsFilter = getCurrentGuildStatsFilter()
        self.preservedRaceScroll = 0
    end
    if frame.category == "Guild Overview" or frame.category == "Guild Members"
        or frame.category == "Inactive Member Management" or frame.category == "Rank Management" then
        iRC:RefreshGuildRoster()
    end
    frame:SetScale(iRC:GetSettings().mainWindowScale or 1)
    self:Refresh()
    frame:Show()
    frame:Raise()
    -- A normal panel launch should refresh shared leaderboard data even when
    -- the user's preferred opening page is elsewhere in the panel.
    if requestCacheFromOpen and iRC.RaceGrid then
        iRC.RaceGrid:RequestGuildCacheFromOpen()
    end
    return true
end

function UI:Toggle(requestCacheFromOpen)
    local frame = self.frame
    if frame and frame:IsShown() then
        frame:Hide()
    else
        return self:Open(nil, requestCacheFromOpen)
    end
end

function UI:RefreshIfShown()
    if not self.frame or not self.frame:IsShown() or self.pendingRefresh then return end
    if not C_Timer or not C_Timer.After then
        if self.frame.category == "Race Overview" and self.frame.scroll then
            self.preservedRaceScroll = self.frame.scroll:GetVerticalScroll()
        end
        self:Refresh()
        return
    end
    local ticket = {}
    self.pendingRefresh = ticket
    C_Timer.After(0.2, function()
        if UI.pendingRefresh ~= ticket then return end
        UI.pendingRefresh = nil
        if UI.frame and UI.frame:IsShown() then
            if UI.frame.category == "Race Overview" and UI.frame.scroll then
                UI.preservedRaceScroll = UI.frame.scroll:GetVerticalScroll()
            end
            UI:Refresh()
        end
    end)
end
