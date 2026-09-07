local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local UI = {}
iRC.MainUI = UI
local expandedGuildCards = {}

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

local function makeMemberRow(parent, index)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(54)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * 60))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -((index - 1) * 60))
    createBackdrop(row, { 0.10, 0.085, 0.07, 0.96 }, { 0.28, 0.25, 0.20, 1 })
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", 14, -10)
    row.name:SetPoint("RIGHT", row, "RIGHT", -14, 0)
    row.name:SetJustifyH("LEFT")
    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -5)
    row.detail:SetPoint("RIGHT", row, "RIGHT", -14, 0)
    row.detail:SetJustifyH("LEFT")
    return row
end

local function makeRaceCard(parent)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetHeight(148)
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
    card.guildLabel:SetPoint("TOP", card, "TOP", -35, -43)
    card.guildLabel:SetText(iRC:Text("GUILD_STATS_RACE"))
    card.guildLabel:SetTextColor(unpack(COLORS.gold))
    card.guild = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.guild:SetPoint("LEFT", card.guildLabel, "RIGHT", 7, 0)
    card.guild:SetWidth(180)
    card.guild:SetJustifyH("LEFT")

    card.averageLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.averageLabel:SetPoint("TOP", card, "TOP", -170, -58)
    card.averageLabel:SetText(iRC:Text("GUILD_STATS_LEVEL_60"))
    card.membersLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.membersLabel:SetPoint("TOP", card, "TOP", 0, -58)
    card.membersLabel:SetText(iRC:Text("GUILD_STATS_ACTIVE_PLAYERS"))
    card.totalLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.totalLabel:SetPoint("TOP", card, "TOP", 170, -58)
    card.totalLabel:SetText(iRC:Text("GUILD_STATS_TOTAL_PLAYERS"))
    card.average = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.average:SetPoint("TOP", card.averageLabel, "BOTTOM", 0, -3)
    card.members = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.members:SetPoint("TOP", card.membersLabel, "BOTTOM", 0, -3)
    card.total = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.total:SetPoint("TOP", card.totalLabel, "BOTTOM", 0, -3)

    card.classesTitle = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.classesTitle:SetPoint("TOP", card, "TOP", 0, -85)
    card.classesTitle:SetText(iRC:Text("GUILD_STATS_CLASS_BREAKDOWN"))
    card.classText = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.classText:SetPoint("TOPLEFT", 15, -98)
    card.classText:SetPoint("TOPRIGHT", -15, -98)
    card.classText:SetJustifyH("CENTER")
    card.classText:SetWordWrap(false)
    card.classBar = CreateFrame("Frame", nil, card, "BackdropTemplate")
    card.classBar:SetPoint("TOPLEFT", 16, -113)
    card.classBar:SetPoint("TOPRIGHT", -16, -113)
    card.classBar:SetHeight(12)
    createBackdrop(card.classBar, { 0.015, 0.015, 0.015, 1 }, { 0.48, 0.42, 0.30, 1 })
    card.classSegments = {}
    card.classLabels = {}
    card.expandHint = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.expandHint:SetPoint("TOPRIGHT", -16, -132)
    card.expandHint:SetWidth(630)
    card.expandHint:SetJustifyH("RIGHT")
    card.rulesSeparator = card:CreateTexture(nil, "ARTWORK")
    card.rulesSeparator:SetColorTexture(0.35, 0.29, 0.16, 0.8)
    card.rulesSeparator:SetPoint("TOPLEFT", 16, -149)
    card.rulesSeparator:SetPoint("TOPRIGHT", -16, -149)
    card.rulesSeparator:SetHeight(1)
    card.rulesTitle = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.rulesTitle:SetPoint("TOPLEFT", 16, -159)
    card.rulesTitle:SetText(iRC:Text("GUILD_STATS_GUILD_PROFILE"))
    card.rulesTitle:SetTextColor(unpack(COLORS.gold))
    card.rulesText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.rulesText:SetPoint("TOPLEFT", 20, -178)
    card.rulesText:SetPoint("TOPRIGHT", -20, -178)
    card.rulesText:SetJustifyH("LEFT")
    card.rulesText:SetJustifyV("TOP")
    card.rulesText:SetWordWrap(true)
    card:EnableMouse(true)
    card:SetScript("OnEnter", function(self)
        if not GameTooltip or not self.report then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.report.guildName or "—")
        if self.report.timestamp and self.report.timestamp > 0 then GameTooltip:AddLine(iRC:Text("RL_GRID_UPDATED", date("%Y-%m-%d %H:%M", self.report.timestamp))) end
        if self.report.source then GameTooltip:AddLine(iRC:Text("RL_GRID_SOURCE", self.report.source)) end
        GameTooltip:AddLine(iRC:Text("GUILD_STATS_POPULATION", self.report.membersLevel60 or 0, self.report.activePlayers or 0, self.report.members or 0), 1, 1, 1, true)
        if self.report.cached then GameTooltip:AddLine(iRC:Text("RL_GRID_CACHED"), 1, 0.65, 0) end
        for class, average in pairs(self.report.classAverageLevels or {}) do
            GameTooltip:AddLine(iRC:Text("RL_GRID_CLASS_LEVEL", class, average))
        end
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    card:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" or not self.guildKey then return end
        expandedGuildCards[self.guildKey] = not expandedGuildCards[self.guildKey]
        if GameTooltip then GameTooltip:Hide() end
        if UI.frame and UI.frame.scroll then UI.preservedRaceScroll = UI.frame.scroll:GetVerticalScroll() end
        UI:Refresh()
    end)
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
        entry.rank:SetPoint("TOPLEFT", entry.icon, "TOPRIGHT", 7, -7)
        entry.rank:SetTextColor(unpack(PODIUM_COLORS[rank]))
        entry.race = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        entry.race:SetPoint("LEFT", entry.rank, "RIGHT", 5, 0)
        entry.race:SetPoint("RIGHT", entry, "RIGHT", -8, 0)
        entry.race:SetJustifyH("LEFT")
        entry.detail = entry:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        entry.detail:SetPoint("TOPLEFT", entry.rank, "BOTTOMLEFT", 0, -3)
        podium.entries[rank] = entry
    end
    return podium
end

local MAIN_NAVIGATION = {
    { id = "Race Overview", label = iRC:Text("GUILD_STATS_TITLE") },
    { id = "Guild Members", label = "Guild Members" },
}

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

function UI:Create()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "iRacelockConnectionMainFrame", UIParent, "BackdropTemplate")
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
    frame.title:SetText(iRC.DisplayName)
    frame.title:SetTextColor(unpack(COLORS.gold))
    frame.player = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.player:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 17, 13)
    local sidebar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -106)
    sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 17)
    sidebar:SetWidth(210)
    createBackdrop(sidebar, { 0.18, 0.11, 0.045, 0.98 }, { 0.58, 0.43, 0.18, 1 })
    frame.sidebar = sidebar

    local sidebarTitle = sidebar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sidebarTitle:SetPoint("TOPLEFT", 14, -13)
    sidebarTitle:SetText(iRC:Text("IRC_MAIN_NAV_TITLE"))
    sidebarTitle:SetTextColor(unpack(COLORS.gold))
    frame.tabs = {}
    local visibleTabIndex = 0
    for _, item in ipairs(MAIN_NAVIGATION) do
        if not item.hidden then
            visibleTabIndex = visibleTabIndex + 1
            local tab = CreateFrame("Button", nil, sidebar, "BackdropTemplate")
            tab:SetSize(item.child and 166 or 180, 31)
            tab:SetPoint("TOPLEFT", item.child and 28 or 14, -((visibleTabIndex - 1) * 35 + 41))
            createBackdrop(tab, { 0.08, 0.065, 0.05, 0.96 }, { 0.34, 0.28, 0.20, 1 })
            tab:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            tab.label:SetPoint("LEFT", 12, 0)
            tab.label:SetText(item.child and "- " .. item.label or item.label)
            tab.category = item.id
            tab:SetScript("OnClick", function(self)
                frame.category = self.category
                if self.category == "Guild Members" then iRC:RefreshGuildRoster() end
                if self.category ~= "Guild Members" and self.category ~= "Race Overview" then frame.subjectName = iRC:GetPlayerName() end
                UI:Refresh()
            end)
            frame.tabs[item.id] = tab
        end
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
    frame.raceRefresh:SetScript("OnUpdate", function(self, elapsed)
        self.cooldownElapsed = (self.cooldownElapsed or 0) + elapsed
        if self.cooldownElapsed < 0.25 then return end
        self.cooldownElapsed = 0
        local remaining = iRC.RaceGrid and iRC.RaceGrid:GetRefreshCooldownRemaining() or 0
        self:SetEnabled(remaining <= 0)
        self:SetText(remaining > 0 and iRC:Text("RL_GRID_REFRESH_COOLDOWN", math.ceil(remaining)) or iRC:Text("RL_GRID_REFRESH"))
    end)
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
    scroll:HookScript("OnVerticalScroll", function()
        if frame.category == "Guild Members" then UI:RenderMemberRows() end
    end)
    frame.scrollContent = content
    frame.memberRows, frame.memberData, frame.raceCards, frame.factionSections = {}, {}, {}, {}
    frame.racePodium = makeRacePodium(content)
    frame.racePodium:Hide()
    frame.category = "Race Overview"
    return frame
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
        row.name:SetText(profile.name)
        row.name:SetTextColor(unpack(iRC:NormalizeName(profile.name) == iRC:NormalizeName(iRC:GetPlayerName()) and COLORS.green or COLORS.gold))
        row.detail:SetText((profile.race or "Unknown") .. " · " .. (profile.class or "Unknown") .. " · Level " .. (profile.level or 1))
        row.profileName = profile.name
        row:SetScript("OnClick", nil)
        row:Show()
    end
    for slot = visible + 1, #frame.memberRows do frame.memberRows[slot]:Hide() end
end

local function updateMemberRows(frame)
    -- The live roster is authoritative for membership and level. Cached iRC
    -- details are used only through rows that still exist in that roster.
    local profiles = iRC:GetGuildRosterRows()
    frame.memberData = profiles
    for _, card in ipairs(frame.raceCards) do card:Hide() end
    for _, section in pairs(frame.factionSections) do section:Hide() end
    frame.racePodium:Hide()
    frame.scrollContent:SetHeight(math.max(1, #profiles * 60))
    frame.scroll:SetVerticalScroll(0)
    UI:RenderMemberRows()
    frame.contentTitle:SetText("Guild Members")
    frame.contentSubtitle:SetText("Current guild roster and live addon information.")
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
    totalMembers = 0
    for class, count in pairs(classes or {}) do
        count = tonumber(count) or 0
        if count > 0 then
            classGroups[#classGroups + 1] = { class = class, count = count }
            totalMembers = totalMembers + count
        end
    end
    table.sort(classGroups, function(a, b) return a.count > b.count end)
    local usedWidth = 0
    local availableWidth = math.max(1, (card:GetWidth() or 651) - 36)
    for index, group in ipairs(classGroups) do
        local share = totalMembers > 0 and group.count / totalMembers or 0
        local percent = math.floor(share * 100 + 0.5)
        local segment = card.classSegments[index]
        if not segment then
            segment = CreateFrame("Frame", nil, card.classBar, "BackdropTemplate")
            segment:SetHeight(8)
            segment:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            card.classSegments[index] = segment
        end
        segment:ClearAllPoints()
        segment:SetPoint("LEFT", card.classBar, "LEFT", 2 + usedWidth, 0)
        local width = index == #classGroups and availableWidth - usedWidth or math.floor(availableWidth * share)
        segment:SetWidth(math.max(1, width))
        local red, green, blue = getClassColor(group.class)
        segment:SetBackdropColor(red, green, blue, 1)
        segment:SetBackdropBorderColor(0.02, 0.02, 0.02, 1)
        segment:Show()
        local label = card.classLabels[index]
        if not label then
            label = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            label:SetJustifyH("CENTER")
            card.classLabels[index] = label
        end
        label:ClearAllPoints()
        label:SetPoint("BOTTOM", segment, "TOP", 0, 2)
        label:SetText((CLASS_SHORT_NAMES[group.class] or group.class) .. " " .. percent .. "%")
        label:Show()
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
    if rules.nativeTongueOnly then lines[#lines + 1] = iRC:Text("GUILD_STATS_RULE_NATIVE_TONGUE") end
    if rules.selfFoundOnly then lines[#lines + 1] = iRC:Text("GUILD_STATS_RULE_SELF_FOUND") end
    if rules.level60GuildFound then lines[#lines + 1] = iRC:Text("GUILD_STATS_RULE_LEVEL60_GUILD_FOUND") end
    if rules.allowLevel60WithoutSelfFound then lines[#lines + 1] = iRC:Text("GUILD_STATS_RULE_LEVEL60_SF_EXCEPTION") end
    if rules.sameRaceGroupsOnly then lines[#lines + 1] = iRC:Text("GUILD_STATS_RULE_SAME_RACE", rules.sameRaceMinimumLevel or 1) end
    if rules.allowLevel60MixedRaceGroups then lines[#lines + 1] = iRC:Text("GUILD_STATS_RULE_MIXED_RACE_60") end
    if rules.guildGroupsOnly then lines[#lines + 1] = iRC:Text("GUILD_STATS_RULE_GUILD_ONLY", rules.guildGroupsMinimumLevel or 1) end
    if #lines == 0 then lines[1] = iRC:Text("GUILD_STATS_NO_ACTIVE_RULES") end
    for index, line in ipairs(lines) do lines[index] = "- " .. line end
    return lines
end

local function getGuildProfileLines(group)
    local contacts = tostring(group.guildContacts or "")
    local lines = {
        iRC:Text("GUILD_STATS_RACELOCKED_EXPLANATION"),
        contacts ~= "" and iRC:Text("GUILD_STATS_CONTACTS", contacts) or iRC:Text("GUILD_STATS_NO_CONTACTS"),
        "",
        iRC:Text("GUILD_STATS_ACTIVE_RULES") .. ":",
    }
    for _, line in ipairs(getActiveRuleLines(group)) do lines[#lines + 1] = line end
    return lines
end

local function guildCardHeight(group)
    if not expandedGuildCards[guildCardKey(group)] then return 148 end
    return 190 + #getGuildProfileLines(group) * 14
end

local function setRaceCard(card, group, rank)
    local accent = RACE_COLORS[group.race] or RACE_COLORS.Unknown
    card.accent:SetColorTexture(accent[1], accent[2], accent[3], 1)
    card.icon:SetTexture(RACE_ICONS[group.race] or "Interface\\Icons\\Achievement_General")
    card.race:SetText(group.guildName or iRC:Text("GUILD_STATS_UNKNOWN_GUILD"))
    card.rank:SetText("#" .. rank)
    card.guild:SetText(RACE_LABELS[group.race] or group.race)
    card.average:SetText(formatNumber(group.membersLevel60 or 0))
    card.members:SetText(formatNumber(group.activePlayers or 0))
    card.total:SetText(formatNumber(group.members or 0))
    card.report = group
    card.guildKey = guildCardKey(group)
    local expanded = expandedGuildCards[card.guildKey]
    card.freshness:SetText(group.source and iRC:Text(group.cached and "RL_GRID_CACHED" or "RL_GRID_RECENT") or "")
    card.expandHint:SetText(iRC:Text(expanded and "GUILD_STATS_COLLAPSE_RULES" or "GUILD_STATS_EXPAND_RULES"))
    card.rulesSeparator:SetShown(expanded and true or false)
    card.rulesTitle:SetShown(expanded and true or false)
    card.rulesText:SetShown(expanded and true or false)
    if expanded then card.rulesText:SetText(table.concat(getGuildProfileLines(group), "\n")) end
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
            entry.icon:SetTexture(RACE_ICONS[group.race] or "Interface\\Icons\\Achievement_General")
            entry.race:SetText(group.guildName or iRC:Text("GUILD_STATS_UNKNOWN_GUILD"))
            entry.detail:SetText(iRC:Text("GUILD_STATS_POPULATION", group.membersLevel60 or 0, group.activePlayers or 0, group.members or 0))
        else
            entry.icon:SetTexture("Interface\\Icons\\Achievement_General")
            entry.race:SetText(iRC:Text("GUILD_STATS_NO_DATA"))
            entry.detail:SetText(iRC:Text("GUILD_STATS_ZERO_PLAYERS"))
        end
        entry:Show()
    end
    frame.racePodium:Show()
end

local function updateRaceOverview(frame)
    local allGroups = iRC:GetRaceGridOverview()
    local ranks = {}
    for index, group in ipairs(allGroups) do ranks[group.guildName] = index end

    local gap, contentWidth = 9, 675
    updateRacePodium(frame, allGroups)
    local usedCards, yOffset = 0, 95

    for _, faction in ipairs({ "Horde", "Alliance" }) do
        local section = frame.factionSections[faction]
        if not section then
            section = makeFactionSection(frame.scrollContent, faction)
            frame.factionSections[faction] = section
        end
        local guilds = {}
        for _, group in ipairs(allGroups) do if group.faction == faction then guilds[#guilds + 1] = group end end
        local cardsHeight = 0
        for index, group in ipairs(guilds) do cardsHeight = cardsHeight + guildCardHeight(group) + (index > 1 and gap or 0) end
        local sectionHeight = 44 + cardsHeight + 10
        section:ClearAllPoints()
        section:SetSize(contentWidth, sectionHeight)
        section:SetPoint("TOPLEFT", frame.scrollContent, "TOPLEFT", 0, -yOffset)
        section:Show()
        local cardWidth = contentWidth - 24
        local cardOffset = 36
        for _, group in ipairs(guilds) do
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
    frame.raceRefresh:SetShown(frame.category == "Race Overview")
    local profile = getProfile(frame)
    local name = profile and profile.name or frame.subjectName or iRC:GetPlayerName()
    local race, class, level = profile and profile.race or "Unknown", profile and profile.class or "Unknown", profile and profile.level or 1
    frame.player:SetText(name .. "  " .. iRC.Colors.Gray .. race .. " " .. class .. " · Level " .. level .. iRC.Colors.Reset)
    for category, tab in pairs(frame.tabs) do setTabAppearance(tab, frame.category == category) end
    if frame.category == "Guild Members" then
        updateMemberRows(frame)
    elseif frame.category == "Race Overview" then
        local connection = iRC:GetConnection()
        frame.player:SetText((connection and connection.guildName or "No guild") .. iRC.Colors.Gray .. "  " .. iRC:Text("GUILD_STATS_HEADER_DESC") .. iRC.Colors.Reset)
        updateRaceOverview(frame)
    end
end

function UI:Open(subjectName, publishFromClick)
    local frame = self:Create()
    if iRC.CloseWindowsExcept then iRC:CloseWindowsExcept(frame) end
    frame.subjectName = subjectName or iRC:GetPlayerName()
    if not frame.category or not frame.tabs[frame.category] then frame.category = "Race Overview" end
    if frame.category == "Guild Members" then iRC:RefreshGuildRoster() end
    frame:SetScale(iRC:GetSettings().mainWindowScale or 1)
    self:Refresh()
    frame:Show()
    frame:Raise()
    if publishFromClick and iRC.RaceGrid then iRC.RaceGrid:PublishFromClick() end
end

function UI:Toggle(publishFromClick)
    local frame = self:Create()
    if frame:IsShown() then
        frame:Hide()
    else
        self:Open(nil, publishFromClick)
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
