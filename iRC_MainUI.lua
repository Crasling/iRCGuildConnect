local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local UI = {}
iRC.MainUI = UI
local expandedGuildCards = {}
local guildStatsFilter = "ALL"
local collapsedFactionSections = {}
local MEMBER_SEARCH_PRIORITY = { name = 1, profession = 2, recipe = 3 }

local function getGuildCardTag(group)
    local rules = group and group.rulesKnown and group.rules
    if not rules then return nil end
    if rules.raceLock == true then return "Race-Locked", { 0.25, 0.85, 1 } end
    local progression = iRC:GetProgressionMode(rules)
    if progression == "GUILD_FOUND" or progression == "SELF_FOUND_OR_GUILD_FOUND" then
        return "Guild-Found", { 0.30, 1, 0.35 }
    end
    if progression == "SELF_FOUND" and iRC:GetMaxLevelProgressionMode(rules) == "SELF_FOUND" then
        return "Self-Found", { 1.00, 0.55, 0.55 }
    end
    return "Normal", { 0.72, 0.72, 0.72 }
end

local function getCurrentGuildStatsFilter()
    if not iRC:IsGuildConnectionActive() then return "ALL" end
    local rules = iRC:GetConnectionRules()
    if rules.raceLock == true then return "RACE_LOCKED" end
    local progression = iRC:GetProgressionMode(rules)
    if progression == "GUILD_FOUND" or progression == "SELF_FOUND_OR_GUILD_FOUND" then return "GUILD_FOUND" end
    if progression == "SELF_FOUND" and iRC:GetMaxLevelProgressionMode(rules) == "SELF_FOUND" then return "SELF_FOUND" end
    return "ALL"
end

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

local function makeMemberRow(parent, index)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetHeight(54)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * 60))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -((index - 1) * 60))
    createBackdrop(row, { 0.10, 0.085, 0.07, 0.96 }, { 0.28, 0.25, 0.20, 1 })
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", 14, -10)
    row.name:SetWidth(220)
    row.name:SetJustifyH("LEFT")
    row.onlineTag = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.onlineTag:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    row.onlineTag:SetText("[Online]")
    row.onlineTag:SetTextColor(0.30, 1, 0.35)
    row.tag = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.tag:SetPoint("LEFT", row.onlineTag, "RIGHT", 6, 0)
    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -5)
    row.detail:SetPoint("RIGHT", row, "RIGHT", -14, 0)
    row.detail:SetJustifyH("LEFT")
    return row
end

local function makeGuildRuleRow(parent, index)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(54)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * 60))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -((index - 1) * 60))
    createBackdrop(row, { 0.075, 0.065, 0.05, 0.96 }, { 0.30, 0.26, 0.19, 1 })
    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetWidth(3)
    row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -5)
    row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 5)
    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.title:SetPoint("TOPLEFT", 15, -7)
    row.title:SetPoint("RIGHT", row, "RIGHT", -137, 0)
    row.title:SetJustifyH("LEFT")
    row.description = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.description:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
    row.description:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -137, 6)
    row.description:SetJustifyH("LEFT")
    row.description:SetJustifyV("TOP")
    row.description:SetWordWrap(true)
    row.stateBackground = row:CreateTexture(nil, "ARTWORK")
    row.stateBackground:SetSize(112, 28)
    row.stateBackground:SetPoint("RIGHT", row, "RIGHT", -11, 0)
    row.state = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.state:SetPoint("CENTER", row.stateBackground, "CENTER", 0, 0)
    row.state:SetWidth(104)
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
    card:SetHeight(158)
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
    card.tag = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.tag:SetPoint("LEFT", card.race, "RIGHT", 9, 0)
    card.rank = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.rank:SetPoint("TOPRIGHT", -14, -16)
    card.rank:SetTextColor(unpack(COLORS.gold))
    card.freshness = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.freshness:SetPoint("TOPLEFT", card.iconFrame, "TOPRIGHT", 9, -27)
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
    card.averageLabel:SetPoint("TOP", card, "TOP", -240, -58)
    card.averageLabel:SetWidth(145)
    card.averageLabel:SetText(iRC:Text("GUILD_STATS_ACTIVE_LEVEL_20"))
    card.membersLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.membersLabel:SetPoint("TOP", card, "TOP", -80, -58)
    card.membersLabel:SetWidth(145)
    card.membersLabel:SetText(iRC:Text("GUILD_STATS_ONLINE_PEAK"))
    card.totalLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.totalLabel:SetPoint("TOP", card, "TOP", 80, -58)
    card.totalLabel:SetWidth(145)
    card.totalLabel:SetText(iRC:Text("GUILD_STATS_ACTIVE_MEMBERS"))
    card.totalMembersLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.totalMembersLabel:SetPoint("TOP", card, "TOP", 240, -58)
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
    card.classesTitle:SetPoint("TOP", card, "TOP", 0, -97)
    card.classesTitle:SetText(iRC:Text("GUILD_STATS_CLASS_BREAKDOWN"))
    card.classText = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.classText:SetPoint("TOPLEFT", 15, -109)
    card.classText:SetPoint("TOPRIGHT", -15, -109)
    card.classText:SetJustifyH("CENTER")
    card.classText:SetWordWrap(false)
    card.classBar = CreateFrame("Frame", nil, card, "BackdropTemplate")
    card.classBar:SetPoint("TOPLEFT", 16, -126)
    card.classBar:SetPoint("TOPRIGHT", -16, -126)
    card.classBar:SetHeight(14)
    createBackdrop(card.classBar, { 0.015, 0.015, 0.015, 1 }, { 0.48, 0.42, 0.30, 1 })
    card.classSegments = {}
    card.classLabels = {}
    card.expandHint = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.expandHint:SetPoint("TOPRIGHT", -16, -143)
    card.expandHint:SetWidth(630)
    card.expandHint:SetJustifyH("RIGHT")
    card.rulesSeparator = card:CreateTexture(nil, "ARTWORK")
    card.rulesSeparator:SetColorTexture(0.35, 0.29, 0.16, 0.8)
    card.rulesSeparator:SetPoint("TOPLEFT", 16, -159)
    card.rulesSeparator:SetPoint("TOPRIGHT", -16, -159)
    card.rulesSeparator:SetHeight(1)
    card.rulesTitle = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.rulesTitle:SetPoint("TOPLEFT", 16, -169)
    card.rulesTitle:SetText(iRC:Text("GUILD_STATS_GUILD_PROFILE"))
    card.rulesTitle:SetTextColor(unpack(COLORS.gold))
    card.rulesText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.rulesText:SetPoint("TOPLEFT", 20, -188)
    card.rulesText:SetPoint("TOPRIGHT", -20, -188)
    card.rulesText:SetJustifyH("LEFT")
    card.rulesText:SetJustifyV("TOP")
    card.rulesText:SetWordWrap(true)
    card.contactsLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.contactsLabel:SetPoint("TOPLEFT", 20, -202)
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
    { id = "Guild Rules", label = "Guild Rules", child = true },
    { id = "Guild Members", label = "Guild Members", child = true },
    { id = "Management", header = true, managementHeader = true },
    { id = "Guild Log", label = "Guild Log", child = true, anyPermission = true },
    { id = "Verification Management", label = iRC:Text("DASHBOARD_VERIFICATION_TITLE"), child = true, permission = "verification", dashboardTab = "Verification" },
    { id = "Incident Management", label = iRC:Text("INCIDENT_TAB"), grandchild = true, permission = "incidents", dashboardTab = "Incidents" },
    { id = "Notification Management", label = iRC:Text("GUILD_NOTIFICATIONS_TAB"), child = true, permission = "notifications", panelKey = "notifications" },
    { id = "Homepage Management", label = iRC:Text("GUILD_HOMEPAGE_TAB"), child = true, permission = "homepage", panelKey = "homepage" },
    { id = "Guild-Found Management", label = iRC:Text("GUILDFOUND_TOOLS_TAB"), child = true, permission = "tradeExceptions", panelKey = "guildFound" },
}

local MANAGEMENT_PANEL_KEYS = {
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

local function setTabAppearance(button, active)
    button:SetBackdropColor(active and 0.24 or 0.08, active and 0.16 or 0.065, active and 0.04 or 0.05, 0.96)
    button:SetBackdropBorderColor(active and 1 or 0.34, active and 0.72 or 0.28, active and 0.18 or 0.20, 1)
    button.label:SetTextColor(unpack(active and COLORS.gold or COLORS.parchment))
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
    search:SetSize(235, 28)
    search:SetPoint("TOPRIGHT", main, "TOPRIGHT", -18, -11)
    search.edit = CreateFrame("EditBox", nil, search, "InputBoxTemplate")
    search.edit:SetSize(222, 22)
    search.edit:SetPoint("RIGHT", search, "RIGHT", 0, 0)
    search.edit:SetAutoFocus(false)
    search.edit:SetMaxLetters(80)
    search.edit:SetTextInsets(5, 5, 0, 0)
    search.edit:SetText("")
    search.hint = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    search.hint:SetPoint("LEFT", search.edit, "LEFT", 6, 0)
    search.hint:SetText("Search characters, professions, or recipes")
    search.suggestions = CreateFrame("Frame", nil, search, "BackdropTemplate")
    search.suggestions:SetSize(235, 128)
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
        button:SetSize(217, 23)
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

    frame.tabs = {}
    for itemIndex, item in ipairs(MAIN_NAVIGATION) do
        if not item.hidden then
            local y = -((itemIndex - 1) * 35 + 14)
            if item.header then
                local heading = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                heading:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 18, y - 7)
                heading:SetWidth(180)
                heading:SetJustifyH("LEFT")
                heading:SetWordWrap(false)
                heading:SetTextColor(unpack(COLORS.gold))
                if item.id == "Current Server" then
                    heading:SetText(currentServerNavigationName())
                    frame.serverNameHeader = heading
                elseif item.managementHeader then
                    heading:SetText("Management")
                else
                    heading:SetText(currentGuildNavigationName())
                    frame.guildNameHeader = heading
                end
                item.widget = heading
            else
                local tab = CreateFrame("Button", nil, sidebar, "BackdropTemplate")
                tab:SetSize(item.grandchild and 152 or (item.child and 166 or 180), 31)
                tab:SetPoint("TOPLEFT", item.grandchild and 42 or (item.child and 28 or 14), y)
                createBackdrop(tab, { 0.08, 0.065, 0.05, 0.96 }, { 0.34, 0.28, 0.20, 1 })
                tab:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                tab.label:SetPoint("LEFT", 12, 0)
                tab.label:SetText((item.child or item.grandchild) and "- " .. item.label or item.label)
                tab.category = item.id
                tab:SetScript("OnClick", function(self)
                    local previousCategory = frame.category
                    frame.category = self.category
                    if self.category == "Guild Rules" and frame.scroll then frame.scroll:SetVerticalScroll(0) end
                    if self.category == "Race Overview" then
                        guildStatsFilter = getCurrentGuildStatsFilter()
                        UI.preservedRaceScroll = 0
                        if previousCategory ~= self.category and iRC.RaceGrid then
                            iRC.RaceGrid:RequestGuildCacheFromOpen()
                        end
                    end
                    if self.category == "Guild Members" then iRC:RefreshGuildRoster() end
                    if self.category ~= "Guild Members" and self.category ~= "Race Overview" then frame.subjectName = iRC:GetPlayerName() end
                    UI:Refresh()
                end)
                frame.tabs[item.id] = tab
                item.widget = tab
            end
        end
    end
    frame.LayoutNavigation = function()
        local showManagement = iRC:HasAnyManagementPermission()
        for _, navigationItem in ipairs(MAIN_NAVIGATION) do
            if navigationItem.permission and iRC:HasGuildPermission(navigationItem.permission) then
                showManagement = true
                break
            end
        end
        local visibleIndex = 0
        for _, item in ipairs(MAIN_NAVIGATION) do
            local visible = not item.hidden
                and (not item.managementHeader or showManagement)
                and (not item.permission or iRC:HasGuildPermission(item.permission))
                and (not item.anyPermission or showManagement)
            local widget = item.widget
            if widget then
                widget:SetShown(visible)
                if visible then
                    visibleIndex = visibleIndex + 1
                    local y = -((visibleIndex - 1) * 35 + 14)
                    widget:ClearAllPoints()
                    widget:SetPoint("TOPLEFT", sidebar, "TOPLEFT",
                        item.header and 18 or (item.grandchild and 42 or (item.child and 28 or 14)), item.header and y - 7 or y)
                end
            end
        end
        for _, item in ipairs(MAIN_NAVIGATION) do
            if item.id == frame.category and ((item.permission and not iRC:HasGuildPermission(item.permission))
                or (item.anyPermission and not showManagement)) then
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
    frame.raceRefresh = CreateFrame("Button", nil, main, "UIPanelButtonTemplate")
    frame.raceRefresh:SetSize(125, 23)
    frame.raceRefresh:SetPoint("TOPRIGHT", -14, -9)
    frame.raceRefresh:SetText(iRC:Text("RL_GRID_REFRESH"))
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
        self:SetText(remaining > 0 and iRC:Text("RL_GRID_REFRESH_COOLDOWN", math.ceil(remaining)) or iRC:Text("RL_GRID_REFRESH"))
    end)
    frame.raceRefresh:Hide()
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

    local scroll = CreateFrame("ScrollFrame", nil, main, "UIPanelScrollFrameTemplate")
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
            iRC.Identity:RegisterCharacter(profile.name)
            iRC.Identity:SetMain(profile.name)
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
            iRC.Identity:RegisterCharacter(profile.name)
            local enabled = not iRC.Identity:IsPersonalBank(profile.name)
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
    memberMenu:Hide()
    frame.memberMenu = memberMenu
    frame:HookScript("OnHide", function()
        memberMenu:Hide()
        professionReport:Hide()
        disableConfirm:Hide()
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
        if professionReport:IsShown() and not iRC:IsMouseOverFrame(professionReport) then professionReport:Hide() end
    end)
    frame.memberRows, frame.memberData, frame.raceCards, frame.factionSections = {}, {}, {}, {}
    frame.racePodium = makeRacePodium(content)
    frame.racePodium:Hide()
    frame.category = "Race Overview"
    return frame
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
    local first = math.floor((frame.scroll:GetVerticalScroll() or 0) / 60) + 1
    local scrollHeight = frame.scroll:GetHeight() or 0
    if scrollHeight < 1 then scrollHeight = 480 end
    local visible = math.max(0, math.min(#profiles - first + 1, math.ceil(scrollHeight / 60) + 1))
    for slot = 1, visible do
        local index, profile = first + slot - 1, profiles[first + slot - 1]
        local row = frame.memberRows[slot]
        if not row then
            row = makeMemberRow(frame.scrollContent, index)
            frame.memberRows[slot] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.scrollContent, "TOPLEFT", 0, -((index - 1) * 60))
        row:SetPoint("TOPRIGHT", frame.scrollContent, "TOPRIGHT", 0, -((index - 1) * 60))
        local memberTag, tagColor
        row.name:SetFontObject(GameFontHighlight)
        if iRC:IsOfficialHardcoreRealm() and profile.dead == true then
            memberTag, tagColor = "Dead", { 1.00, 0.50, 0.50 }
        elseif iRC.Identity and iRC.Identity:IsPersonalBank(profile.name) then
            memberTag, tagColor = "Personal Bank", { 0.40, 0.80, 1.00 }
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
        local identityLabel = iRC.Identity and iRC.Identity:GetIdentityLabel(profile.name)
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
            menu.altMenu:Hide()
            menu:SetHeight(214)
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
    frame.scrollContent:SetHeight(math.max(1, #profiles * 60))
    frame.scroll:SetVerticalScroll(0)
    UI:RenderMemberRows()
end

local function updateMemberRows(frame)
    -- Index the current roster once per refresh; typing only filters these rows.
    local profiles = iRC:GetGuildRosterRows()
    local entries, byKey = {}, {}
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
        add("name", iRC:FormatPlayerName(profile.name), profile)
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
    frame.contentSubtitle:SetText("Current guild roster and live addon information.")
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
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.scrollContent, "TOPLEFT", 0, -((index - 1) * 60))
        row:SetPoint("TOPRIGHT", frame.scrollContent, "TOPRIGHT", 0, -((index - 1) * 60))
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
    frame.scrollContent:SetHeight(math.max(1, #records * 60))
    frame.contentTitle:SetText("Guild Log")
    frame.contentSubtitle:SetText(#records > 0 and iRC:Text("GUILD_LOG_DESCRIPTION")
        or (query ~= "" and iRC:Text("GUILD_LOG_NO_SEARCH_RESULTS") or iRC:Text("GUILD_LOG_EMPTY")))
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
        yOffset = yOffset + 60
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

local function guildCardHeight(group)
    if not expandedGuildCards[guildCardKey(group)] then return 158 end
    local descriptionLines = math.max(1, math.ceil(#tostring(group.guildDescription or "") / 72))
    return 230 + #getGuildProfileLines(group) * 14 + (descriptionLines - 1) * 14
end

local function setRaceCard(card, group, rank)
    local rules = group and group.rulesKnown and group.rules
    local progression = rules and iRC:GetProgressionMode(rules) or "NONE"
    local accent = rules and rules.raceLock == true and (RACE_COLORS[group.race] or RACE_COLORS.Unknown)
        or (progression == "GUILD_FOUND" or progression == "SELF_FOUND_OR_GUILD_FOUND")
            and { 0.30, 1, 0.35 } or RACE_COLORS.Unknown
    card.accent:SetColorTexture(accent[1], accent[2], accent[3], 1)
    card.icon:SetTexture(getGuildCardIcon(group))
    card.race:SetText(group.guildName or iRC:Text("GUILD_STATS_UNKNOWN_GUILD"))
    card.rank:SetText("#" .. rank)
    local tag, tagColor = getGuildCardTag(group)
    card.tag:SetText(tag and ("[" .. tag .. "]") or "")
    if tagColor then card.tag:SetTextColor(tagColor[1], tagColor[2], tagColor[3]) end
    card.tag:SetShown(tag ~= nil)
    card.average:SetText(group.activeLevel20 ~= nil and formatNumber(group.activeLevel20) or "—")
    card.members:SetText(formatNumber(group.activePlayers or 0))
    card.total:SetText(group.activeMembers ~= nil and formatNumber(group.activeMembers) or "—")
    card.totalMembers:SetText(formatNumber(group.members or 0))
    card.report = group
    card.guildKey = guildCardKey(group)
    local expanded = expandedGuildCards[card.guildKey]
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
    updateClassBreakdown(card, group.classes, group.members)
    card:Show()
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
                and (iRC:GetProgressionMode(group.rules) == "GUILD_FOUND"
                    or iRC:GetProgressionMode(group.rules) == "SELF_FOUND_OR_GUILD_FOUND") then
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
    if frame.category ~= "Guild Log" then frame.guildLogSearch.suggestions:Hide() end
    if frame.category ~= "Guild Rules" then
        for _, row in ipairs(frame.ruleRows or {}) do row:Hide() end
        for _, header in ipairs(frame.ruleSectionHeaders or {}) do header:Hide() end
        if frame.rulesEmpty then frame.rulesEmpty:Hide() end
    end
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
    frame.scroll:SetPoint("TOPLEFT", frame.main, "TOPLEFT", 15, usesSearchHeader and -112 or -78)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame.main, "BOTTOMRIGHT", -31, 14)
    frame.scroll:SetShown(not embeddedManagement)
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
    if frame.category == "Guild Members" then
        updateMemberRows(frame)
    elseif frame.category == "Guild Log" then
        updateGuildLog(frame)
    elseif frame.category == "Guild Rules" then
        frame.player:SetText((connection and connection.guildName or "No guild") .. iRC.Colors.Gray
            .. "  Guild connection and shared rules" .. iRC.Colors.Reset)
        updateGuildRules(frame)
    elseif embeddedManagement then
        frame.player:SetText((connection and connection.guildName or "No guild") .. iRC.Colors.Gray
            .. "  Delegated guild management" .. iRC.Colors.Reset)
    elseif frame.category == "Race Overview" then
        frame.player:SetText((connection and connection.guildName or "No guild") .. iRC.Colors.Gray .. "  " .. iRC:Text("GUILD_STATS_HEADER_DESC") .. iRC.Colors.Reset)
        updateRaceOverview(frame)
    end
end

function UI:OpenCategory(category)
    local frame = self:Create()
    if frame.tabs[category] then frame.category = category end
    return self:Open(nil, category == "Race Overview")
end

function UI:Open(subjectName, requestCacheFromOpen)
    if not iRC:CanOpenPanel() then return false end
    local frame = self:Create()
    if iRC.CloseWindowsExcept then iRC:CloseWindowsExcept(frame) end
    frame.subjectName = subjectName or iRC:GetPlayerName()
    if not frame.category or not frame.tabs[frame.category] then frame.category = "Race Overview" end
    if frame.category == "Race Overview" then
        guildStatsFilter = getCurrentGuildStatsFilter()
        self.preservedRaceScroll = 0
    end
    if frame.category == "Guild Members" then iRC:RefreshGuildRoster() end
    frame:SetScale(iRC:GetSettings().mainWindowScale or 1)
    self:Refresh()
    frame:Show()
    frame:Raise()
    if requestCacheFromOpen and frame.category == "Race Overview" and iRC.RaceGrid then
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
