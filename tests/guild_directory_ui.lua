-- Run from the addon directory. Exercise the real guild list and draft preview
-- with lightweight frames; no game, saved-variable, or network writes occur.
unpack = table.unpack
date = os.date
local now, created, methods = 1800000000, {}, {}
local function widget(kind, parent, template)
    local object = { kind = kind, parent = parent, template = template,
        children = {}, scripts = {}, hooks = {}, points = {}, shown = true, mouseEnabled = kind == "Button" }
    setmetatable(object, { __index = function(_, key)
        if methods[key] then return methods[key] end
        if key:match("^Set") or key:match("^Register") or key == "Raise" then return function() end end
    end })
    if parent then parent.children[#parent.children + 1] = object end
    created[#created + 1] = object
    return object
end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetWidth(width) self.width = width end
function methods:SetHeight(height) self.height = height end
function methods:GetWidth() return self.width or self.parent and self.parent:GetWidth() or 675 end
function methods:GetHeight() return self.height or 1 end
function methods:SetParent(parent) self.parent = parent end
function methods:GetParent() return self.parent end
function methods:SetPoint(...) self.points[#self.points + 1] = { ... } end
function methods:ClearAllPoints() self.points = {} end
function methods:SetText(value)
    if self.fontString then self.fontString:SetText(value) else self.label = value end
end
function methods:GetText() return self.label or "" end
function methods:SetFormattedText(format, ...) self:SetText(string.format(format, ...)) end
function methods:SetFontString(fontString) self.fontString = fontString end
local function plainText(value)
    return tostring(value or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
end
function methods:GetStringWidth() return #plainText(self:GetText()) * 7 end
function methods:GetStringHeight()
    local count, width = 0, math.max(1, self:GetWidth())
    for line in (plainText(self:GetText()) .. "\n"):gmatch("(.-)\n") do
        count = count + (self.wordWrap == false and 1 or math.max(1, math.ceil(#line * 7 / width)))
    end
    return count * 14
end
function methods:SetWordWrap(value) self.wordWrap = value end
function methods:CreateFontString(_, _, template) return widget("FontString", self, template) end
function methods:CreateTexture() return widget("Texture", self) end
function methods:SetTexture(value) self.texture = value end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:HookScript(event, callback)
    self.hooks[event] = self.hooks[event] or {}
    self.hooks[event][#self.hooks[event] + 1] = callback
end
function methods:Fire(event, ...)
    if self.scripts[event] then self.scripts[event](self, ...) end
    for _, callback in ipairs(self.hooks[event] or {}) do callback(self, ...) end
end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(value) self.shown = value == true end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:EnableMouse(value) self.mouseEnabled = value == true end
function methods:GetFrameLevel() return 1 end
function methods:GetVerticalScroll() return self.verticalScroll or 0 end
function methods:SetVerticalScroll(value) self.verticalScroll = value end
function CreateFrame(kind, _, parent, template) return widget(kind, parent, template) end
function GetTime() return now end
function time() return now end
function UnitFactionGroup() return "Alliance" end
UIParent = widget("Root")
C_Timer = { After = function(_, callback) callback() end }

local guildKey, rosterReads = "example guild", 0
local roster = {
    { name = "First Main", classFile = "MAGE", class = "Mage", level = 60, online = true },
    { name = "Second Main", classFile = "PALADIN", class = "Paladin", level = 60, online = true },
    { name = "Third Main", classFile = "MAGE", class = "Mage", level = 15, online = true },
    { name = "Fourth Main", classFile = "WARRIOR", class = "Warrior", level = 25, online = false },
    { name = " first-main ", classFile = "MAGE", class = "Mage", level = 60, online = true },
    { name = "THIRD MAIN", classFile = "MAGE", class = "Mage", level = 15, online = true },
    { name = "", classFile = "MAGE", class = "Mage", level = 60, online = true },
}
local rules = { raceLock = false, classLock = false, requireIRC = true, guildMapEnabled = true }
local live = { guildName = "Example Guild", name = "Reporter Main", guid = "Player-1-Reporter",
    race = "HUMAN", faction = "Alliance", timestamp = now - 120, members = 4,
    activeLevel60 = 2, activeMembers = 4, activePlayers = 3, rulesKnown = true, rules = rules,
    classes = { MAGE = 2, PALADIN = 1, WARRIOR = 1 }, guildDescription = "Saved guild description",
    guildDescriptionTimestamp = now - 3600, guildDescriptionEditedBy = "Editor Main",
    guildHomepageIcon = 1, guildHomepageTag = "PVE", guildContacts = "Saved Contact",
    classBreakdownMode = "ALL", classBreakdownMinLevel = 1, classBreakdownMaxLevel = 60,
}
local addon = { ColorValues = { Orange = { 1, .59, .09 }, Green = { .3, 1, .35 }, Gray = { .5, .5, .5 } },
    Colors = setmetatable({}, { __index = function() return "" end }),
    GuildHomepageIcons = { "SavedIcon", "DraftIcon" } }
local private = { iRC = addon }
function addon:IsForeverClient() return false end
function addon:GetGuildDirectoryScope() return "s-18-3-10-0-pve" end
function addon:GetGuildDirectoryRulesetLabel(scope)
    return scope and scope:match("%-pvp$") and "PvP" or "PvE"
end
function addon:Text(key, ...)
    local value = self.L and self.L[key] or key
    return select("#", ...) > 0 and string.format(value, ...) or value
end
function addon:NormalizeName(name)
    return tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%-", " "):gsub("%s+", " "):lower()
end
function addon:FormatPlayerName(name) return name end
function addon:FormatInviteContactName(name) return name end
function addon:GetPlayerName() return "First Main" end
function addon:GetGuildKey() return guildKey end
function addon:GetGuildRosterSnapshot() rosterReads = rosterReads + 1; return roster end
function addon:GetGuildRosterRows() rosterReads = rosterReads + 1; return roster end
function addon:GetConnectionRules() return rules end
function addon:IsGuildConnectionActive() return true end
function addon:GetProgressionMode(value) return value and value.progression or "NONE" end
function addon:GetMaxLevelProgressionMode(value) return value and value.maximumProgression or "SELF_FOUND" end
function addon:NormalizeGuildClass(value) return value or "" end
function addon:GetClassDisplayName(value) return value end
function addon:GetSettings() return {} end
function addon:OpenWhisper() error("the preview must not contact players") end
addon.RaceGrid = { GetLocalReport = function() return live end }
assert(loadfile("Localization/enUS.lua"))("iRC", private)

-- Loading only this real source prefix avoids unrelated Lua 5.1-only contact
-- loops later in the file when the standalone runner uses newer Lua syntax.
local sourceFile = assert(io.open("iRC_MainUI.lua", "r"))
local source = sourceFile:read("*a")
sourceFile:close()
local boundary = assert(source:find("-- Page refresh and window lifecycle", 1, true))
local render = assert(load(source:sub(1, boundary - 1)
    .. "\nreturn { create = makeRaceCard, set = setRaceCard, height = guildCardHeight, ui = UI, overview = updateGuildOverview,"
    .. " directory = function(frame, view, filter) guildStatsView, guildStatsFilter = view, filter; return updateRaceOverview(frame) end }",
    "@iRC_MainUI.lua"))("iRC", private)

local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, entry in pairs(value) do result[key] = deepCopy(entry) end
    return result
end
local function equal(first, second)
    if type(first) ~= type(second) then return false end
    if type(first) ~= "table" then return first == second end
    for key, entry in pairs(first) do if not equal(entry, second[key]) then return false end end
    for key in pairs(second) do if first[key] == nil then return false end end
    return true
end
local function visibleText(root)
    local texts = {}
    local function append(object)
        if not object:IsVisible() then return end
        if object.kind == "FontString" then texts[#texts + 1] = object:GetText() end
        for _, child in ipairs(object.children) do append(child) end
    end
    append(root)
    return table.concat(texts, "\n")
end

local parent = widget("Container", UIParent)
parent:SetSize(675, 900)
local card = render.create(parent)
card:SetWidth(651)
render.set(card, live, false)
local compactHeight = render.height(live, false)
assert(compactHeight <= 44 and card:GetHeight() == compactHeight, "collapsed guilds occupy a slim single-line row")
assert(card.header and card.header.kind == "Button" and card.header:GetHeight() == compactHeight,
    "the clickable guild header retains the collapsed row height")
assert(card.details and not card.details:IsVisible(), "the detail panel starts hidden beneath the row")
assert(not card.groupOutline:IsVisible() and not card.groupBackground:IsVisible(),
    "collapsed rows do not retain expanded group styling")
assert(card.tag:IsVisible() and card.tag:GetText():find("PvE", 1, true), "keywords remain visible while collapsed")
assert(not card.classBar:IsVisible(), "class distribution belongs to expanded information")
assert(not visibleText(card):find("#1", 1, true), "the directory card never displays ranking")
assert(not visibleText(card):find(live.guildDescription, 1, true), "the compact list does not include the full description")

-- A saved numeric-string timestamp should show the same age and metadata as a
-- numeric timestamp, rather than crashing a card during report restoration.
local numericMetadata, numericFreshness = card.reportMetadata, card.freshness:GetText()
local stringTimestamp = deepCopy(live)
stringTimestamp.timestamp = tostring(stringTimestamp.timestamp)
render.set(card, stringTimestamp, false)
assert(card.reportMetadata == numericMetadata and card.freshness:GetText() == numericFreshness,
    "restored numeric-string report timestamps render consistently")

local unmeasuredCard = render.create(parent)
unmeasuredCard:SetWidth(0)
render.set(unmeasuredCard, live, false)
for _, stat in ipairs(unmeasuredCard.stats) do
    assert(stat:GetWidth() > 0 and stat:GetWidth() < 675, "newly anchored cards never create negative stat widths")
end

-- Resolve the anchors stored by the lightweight widgets so the regression
-- checks the actual visible columns, including at the narrower editor width.
local function anchorFraction(point)
    if point:find("LEFT", 1, true) then return 0 end
    if point:find("RIGHT", 1, true) then return 1 end
    return 0.5
end
local function horizontalBounds(object, root)
    if object == root then return 0, root:GetWidth() end
    local anchors = {}
    for _, point in ipairs(object.points) do
        local relative, relativePoint, offset
        if type(point[2]) == "table" then
            relative, relativePoint, offset = point[2], point[3] or point[1], point[4] or 0
        else
            relative, relativePoint, offset = object.parent, point[1], point[2] or 0
        end
        local left, right = horizontalBounds(relative, root)
        anchors[#anchors + 1] = { fraction = anchorFraction(point[1]),
            position = left + (right - left) * anchorFraction(relativePoint) + offset }
    end
    local width = object.width
    if not width then
        for _, first in ipairs(anchors) do
            for _, second in ipairs(anchors) do
                if second.fraction ~= first.fraction then
                    width = (second.position - first.position) / (second.fraction - first.fraction)
                end
            end
        end
    end
    width = width or object:GetWidth()
    local anchor = assert(anchors[1], "visible columns have an anchor")
    local left = anchor.position - width * anchor.fraction
    return left, left + width
end
local function assertRowColumns(row, width)
    assert(row:GetHeight() <= 44, "names and metrics stay in one slim row")
    assert(row.race.wordWrap == false and row.tag.wordWrap == false, "guild names and tags never wrap")
    local fields = { row.iconFrame, row.race, row.tag }
    for _, stat in ipairs(row.stats) do
        fields[#fields + 1] = stat
        assert(not stat.label or not stat.label:IsVisible(), "metric labels belong to shared column headings")
        assert(stat.value:IsVisible(), "all three numeric metrics remain visible")
        assert(stat.value:GetStringWidth() <= stat:GetWidth(), "guild member counts fit their aligned numeric columns")
    end
    if row.rowAge:IsVisible() then fields[#fields + 1] = row.rowAge end
    fields[#fields + 1] = row.expandButton
    local previousRight = 0
    for _, field in ipairs(fields) do
        local left, right = horizontalBounds(field, row)
        assert(right > left and left >= previousRight and right <= width,
            "guild name, tag, metrics, age, and expansion control stay in nonoverlapping columns")
        previousRight = right
    end
end
local longName = deepCopy(live)
longName.guildName = string.rep("A long guild name ", 8)
longName.activeMembers, longName.activePlayers, longName.members = 987, 999, 1000
longName.rules = deepCopy(rules)
longName.rules.classLock, longName.rules.guildClass = true, "PALADIN"
for _, width in ipairs({ 651, 630, 629, 496 }) do
    card:SetWidth(width)
    render.set(card, longName, false)
    assertRowColumns(card, width)
    assert(card.tag:IsVisible() and card.tag:GetText():find("Class-Locked", 1, true),
        "narrow rows preserve mandatory classification beside long guild names")
    local tagLeft, tagRight = horizontalBounds(card.tag, card)
    assert(tagRight - tagLeft >= card.tag:GetStringWidth(), "mandatory tags retain enough room to stay readable")
    assert(card.rowAge:IsVisible() == (width >= 630), "the update-age column yields space in narrow previews")
end
card:SetWidth(651)
render.set(card, live, false)

card:SetWidth(496)
render.set(card, live, true)
assert(card.metaHit:IsVisible() and visibleText(card):find(numericFreshness, 1, true),
    "narrow rows keep the full report age in their expanded details")
card:SetWidth(651)
render.set(card, live, true)
assert(render.height(live, true) > compactHeight and card.classBar:IsVisible(), "expanding reveals more information")
assert(card.details:IsVisible() and card.header:GetHeight() == compactHeight,
    "expansion reveals a separate panel without stretching the clickable row")
assert(card.groupOutline:IsVisible() and card.groupBackground:IsVisible(),
    "one visible group joins the selected header to its expanded details")
assert(card.detailsGuildName:IsVisible() and card.detailsGuildName:GetText() == live.guildName,
    "the expanded details clearly identify their guild")
assert(visibleText(card):find(live.guildDescription, 1, true), "expanded information includes the guild description")
assert(visibleText(card):find("Saved Contact", 1, true), "expanded information includes published contacts")
render.set(card, live, false)
assert(not card.classBar:IsVisible() and not visibleText(card):find("Saved Contact", 1, true), "collapsing hides expanded children")
assert(not card.details:IsVisible(), "collapsing hides the detail panel")
assert(not card.groupOutline:IsVisible() and not card.groupBackground:IsVisible(),
    "collapsing clears the selected group styling")

local longProfile = deepCopy(live)
local contactNames = {}
for index = 1, 5 do contactNames[index] = "Long Contact " .. index .. " " .. string.rep("Lastname", 6) end
longProfile.guildContacts = table.concat(contactNames, ",")
longProfile.guildDescription = string.rep("Long guild description with wrapped text. ", 10) .. "\nAnother paragraph."
longProfile.guildName = string.rep("Long Guild Name ", 10)
render.set(card, longProfile, true)
assert(card.detailsGuildName:GetText() == longProfile.guildName
    and card.detailsGuildName:GetHeight() >= card.detailsGuildName:GetStringHeight(),
    "reused rows show the new guild identity and allow its full name to wrap")
local nameBottom = -card.detailsGuildName.points[1][5] + card.detailsGuildName:GetHeight()
assert(-card.metaHit.points[1][5] > nameBottom, "wrapped guild names do not overlap report metadata")
assert(#card.contactButtons == 5, "expanded information keeps all five published contacts")
assert(card.description:GetHeight() >= card.description:GetStringHeight(), "wrapped description fits its measured height")
for _, button in ipairs(card.contactButtons) do
    local point = assert(button.points[1], "contact has an anchor")
    assert(button:GetWidth() <= card:GetWidth() / 2, "long contact names stay in bounded columns")
    assert(point[4] + button:GetWidth() <= card:GetWidth() - 12, "contact columns stay inside the card")
    assert(-point[5] + button:GetHeight() <= card:GetHeight(), "all contact rows fit the expanded card")
end
render.set(card, live, false)

local before = deepCopy(live)
local preview = render.ui:CreateGuildHomepagePreview(parent)
preview:SetWidth(496)
local draft = { description = "Unsaved guild description", icon = 2, tag = "RP",
    classBreakdown = { mode = "MAX", minLevel = 60, maxLevel = 60 },
    contacts = { "First Draft Contact", "Second Draft Contact" },
    contactNotes = { ["first draft contact"] = "Private contact note" },
}
preview:Refresh(draft)
assertRowColumns(preview.card, 496)
assert(equal(live, before), "refreshing a draft never mutates the saved report or nested tables")
assert(preview.card.report.guildDescription == draft.description, "the preview shows the draft description")
assert(preview.card.report.guildHomepageTag == "RP" and preview.card.icon.texture == "DraftIcon", "draft appearance is previewed")
local draftContacts = tostring(preview.card.report.guildContacts or "")
assert(draftContacts:find("First Draft Contact", 1, true) and draftContacts:find("Second Draft Contact", 1, true)
    and not draftContacts:find("Saved Contact", 1, true), "the preview shows unsaved public contacts")
assert(preview.card.report.classBreakdownClasses.MAGE == 1 and preview.card.report.classBreakdownClasses.PALADIN == 1
    and not preview.card.report.classBreakdownClasses.WARRIOR, "MAX counts each normalized character once")
draft.classBreakdown = { mode = "RANGE", minLevel = 15, maxLevel = 15 }
preview:Refresh(draft)
assert(preview.card.report.classBreakdownClasses.MAGE == 1
    and not preview.card.report.classBreakdownClasses.PALADIN and not preview.card.report.classBreakdownClasses.WARRIOR,
    "RANGE includes both endpoints and counts normalized character aliases once")
draft.classBreakdown = { mode = "MAX", minLevel = 60, maxLevel = 60 }
preview:Refresh(draft)
assert(not visibleText(preview):find("Private contact note", 1, true), "private notes never appear in the public preview")
preview.card.header:Fire("OnClick", "LeftButton")
assert(preview.card.expanded and visibleText(preview):find(draft.description, 1, true),
    "clicking the preview row expands unsaved details")
preview.card.details:Fire("OnClick", "LeftButton")
preview.card.details:Fire("OnMouseUp", "LeftButton")
assert(preview.card.expanded, "clicking the expanded detail panel does not collapse the row")
preview.card.expandButton:Fire("OnClick", "LeftButton")
assert(not preview.card.expanded and not preview.card.details:IsVisible(), "the expansion control collapses the preview")
preview.card.expandButton:Fire("OnClick", "LeftButton")
assert(preview.card.expanded, "the expansion control can reopen the preview")
render.set(card, live)
assert(not card.expanded, "expanding the editor preview does not expand the public directory card")
for _, button in ipairs(preview.card.contactButtons or {}) do
    assert(not button.mouseEnabled or not button.scripts.OnClick, "preview contacts cannot open whispers")
end

rules.classLock, rules.guildClass = true, "PALADIN"
preview:Refresh(draft)
assert(preview.card.tag:GetText():find("Class-Locked", 1, true), "a draft tag cannot replace mandatory Class-Locked classification")
assert(preview.card.icon.texture ~= "DraftIcon", "Class-Locked retains its required class icon")
rules.classLock, rules.guildClass, rules.raceLock = false, nil, true
preview:Refresh(draft)
assert(preview.card.tag:GetText():find("Race-Locked", 1, true), "a draft tag cannot replace mandatory Race-Locked classification")
assert(preview.card.icon.texture ~= "DraftIcon", "Race-Locked retains its required race icon")
rules.raceLock = false

-- Repeated previews should reuse contacts/class segments, and must not grow a
-- new set of frames whenever a text field or appearance choice changes.
preview:Refresh(draft)
local frameCount = #created
local rosterReadsBeforeTyping = rosterReads
for index = 1, 100 do
    draft.description = "Unsaved edit " .. index
    preview:Refresh(draft)
end
assert(#created == frameCount, "draft updates reuse existing frames")
assert(rosterReads == rosterReadsBeforeTyping, "typing presentation text does not rescan class data")
preview:Refresh(nil)
assert(preview.card.report.guildDescription == before.guildDescription, "clearing the draft restores the saved report")
assert(equal(live, before), "draft interactions leave persistent data unchanged")
local expandedPreviewHeight, heightNotifications, notifiedHeight = preview:GetHeight(), 0, nil
assert(preview.expanded and expandedPreviewHeight > compactHeight, "exercise report loss from an expanded preview")
preview.onHeightChanged = function(self)
    heightNotifications = heightNotifications + 1
    notifiedHeight = self:GetHeight()
end
addon.RaceGrid.GetLocalReport = function() return nil end
guildKey = nil
preview:Refresh(draft)
assert(not preview.card:IsVisible() and preview.empty:IsVisible(), "an unavailable guild report shows the empty preview state")
assert(preview:GetHeight() < expandedPreviewHeight and heightNotifications == 1 and notifiedHeight == preview:GetHeight(),
    "an unavailable report shrinks the expanded preview and updates its parent layout")
preview:Refresh(draft)
assert(heightNotifications == 1, "an unchanged empty preview does not repeat layout notifications")
print("PASS: slim guild rows, nonoverlapping columns, header expansion, restored timestamps, isolated draft previews, unique class counts, and frame reuse")

-- Render the real compact roster with 1,000 cached profiles. Scrolling must
-- reuse its visible rows, including their labels, highlights and callbacks.
function addon:IsOfficialHardcoreRealm() return false end
function addon:IsGuildFoundProgressionApplicable() return false end
function addon:IsLiveAddonState(value) return value == "verified" end
addon.Identity = {
    GetIdentityLabel = function(_, name)
        if name == "First Main" then return "Main" end
        if name == "Second Alt" then return "Alt of First Main" end
    end,
    GetMainCharacterName = function() return "First Main" end,
    IsPersonalBank = function() return false end,
}
addon.Professions = {
    GetOptions = function() return { { 171, "Alchemy" }, { 182, "Herbalism" }, { 185, "Cooking" }, { 129, "First Aid" } } end,
    DescribeRecipes = function() return { "Alchemy", "Recipe details" } end,
}
local memberView = { category = "Guild Members", memberRows = {}, memberData = {},
    scroll = widget("ScrollFrame", parent), scrollContent = widget("Frame", parent) }
memberView.scroll:SetHeight(234)
memberView.scrollContent:SetWidth(675)
for index = 1, 1000 do
    memberView.memberData[index] = { name = index == 1 and "First Main" or index == 2 and "Second Alt" or "Member " .. index,
        race = "Human", class = "MAGE", level = 60, online = index % 2 == 1,
        verification = { state = "verified" }, lastOnlineDays = 1,
        professionData = { skills = { [171] = 300, [182] = 300, [185] = 150, [129] = 225 } } }
end
local openedMember
memberView.showMemberProfile = function(value) openedMember = value end
render.ui.frame = memberView
local beforeRosterReads = rosterReads
render.ui:RenderMemberRows()
assert(#memberView.memberRows == 7, "a compact roster creates only visible rows plus one extra")
local mainRow, altRow = memberView.memberRows[1], memberView.memberRows[2]
assert(mainRow:GetHeight() == 36 and not mainRow.detail.wordWrap and mainRow.memberDivider:IsShown(),
    "roster rows are compact, separated, and keep details on one line")
assert(mainRow.tag:GetText() == "[Main]" and not mainRow.identityDetail:IsShown(),
    "the Main tag no longer repeats a second main-character label")
assert(altRow.tag:GetText() == "[Alt]" and altRow.identityDetail:GetText() == "Main: First Main",
    "alts keep their confirmed main visible")
assert(mainRow.onlineTag:GetText() == "ONLINE  |  iRC", "live iRC presence remains prominent")
assert(mainRow.detail:GetText():find("Alchemy 300", 1, true), "professions remain in the compact summary")
assert(mainRow.detail.points[2][1] == "TOPRIGHT" and mainRow.detail.points[2][5] == -20
    and altRow.detail.points[2][1] == "TOPRIGHT" and altRow.detail.points[2][5] == 0,
    "both ends of the detail line align at the same height without compressing or clipping text")
local tooltipLines = {}
GameTooltip = widget("Tooltip", UIParent)
function GameTooltip:AddLine(value) tooltipLines[#tooltipLines + 1] = value end
mainRow:Fire("OnEnter")
assert(table.concat(tooltipLines, "\n"):find("First Aid 225", 1, true), "hover keeps full profession details available")
memberView.scroll:SetVerticalScroll(500 * 39)
render.ui:RenderMemberRows()
assert(#memberView.memberRows == 7 and mainRow.profileName == "Member 501", "scrolling reuses compact row frames")
mainRow:Fire("OnClick", "LeftButton")
assert(openedMember == memberView.memberData[501], "reused rows open the correct current member")
memberView.scroll:SetVerticalScroll(999 * 39)
render.ui:RenderMemberRows()
assert(mainRow.profileName == "Member 1000" and not altRow:IsShown(), "the last page hides unused rows")
assert(rosterReads == beforeRosterReads, "scrolling the compact roster does not rebuild guild data")
print("PASS: compact member rows, full profession hover, confirmed identities, live presence, and bounded scrolling for 1,000 members")

-- Race statistics follow the same confirmed main/alt scope as other totals.
local overviewSettings = { excludeAltsFromGuildSnapshot = true }
function addon:GetSettings() return overviewSettings end
function addon:NormalizeGuildRace(value)
    local token = tostring(value or ""):upper():gsub("%s+", "")
    if token == "UNDEAD" then token = "SCOURGE" end
    return ({ HUMAN = true, NIGHTELF = true, SKYBORNE = true, SCOURGE = true })[token] and token or ""
end
function addon:IsAddonResponseRequired() return false end
function addon:HasGuildPermission() return false end
function addon:IsTestAdminGuildMaster() return false end
function addon:GetConnection() return { guildName = "Example Guild" } end
addon.Identity.GetMainCharacterName = function(_, name)
    if name == "Main Human" or name == "Alt Undead" then return "Main Human" end
end
roster = {
    { name = "Main Human", race = "HUMAN", class = "MAGE", level = 60, lastOnlineDays = 20 },
    { name = "Alt Undead", race = "SCOURGE", class = "WARLOCK", level = 20, online = true },
    { name = "Elf Main", race = "NIGHTELF", class = "DRUID", level = 15, lastOnlineDays = 2 },
    { name = "Sky Main", race = "SKYBORNE", class = "MAGE", level = 40, online = true },
    { name = "Unknown Main", race = "Unknown", class = "PRIEST", level = 10 },
}
local overviewFrame = { raceCards = {}, factionSections = {}, memberRows = {},
    scrollContent = widget("Frame", parent), scroll = widget("ScrollFrame", parent),
    guildOverviewAltToggle = widget("Button", parent), contentTitle = widget("FontString", parent),
    contentSubtitle = widget("FontString", parent) }
overviewFrame.scroll:SetHeight(300)
overviewFrame.scroll:SetVerticalScroll(75)
render.overview(overviewFrame)
local overview = overviewFrame.guildOverview
assert(overview.exportData.total == 4 and #overview.exportData.races == 4)
local raceTotals, raceSum = {}, 0
for _, race in ipairs(overview.exportData.races) do
    raceTotals[race.race], raceSum = race.total, raceSum + race.total
    assert(race.percent == 25)
end
assert(raceSum == 4 and raceTotals.HUMAN == 1 and not raceTotals.SCOURGE and raceTotals.UNKNOWN == 1,
    "a linked alt uses the main's race; unavailable races remain explicit instead of being guessed")
assert(overviewFrame.scroll:GetVerticalScroll() == 75 and overviewFrame.scrollContent:GetHeight() > 462,
    "the expanded overview can scroll and refreshes preserve its position")
overviewSettings.excludeAltsFromGuildSnapshot = false
render.overview(overviewFrame)
assert(overview.exportData.total == 5 and #overview.exportData.races == 5)
local raceRows = #overview.races.rows
render.overview(overviewFrame)
assert(#overview.races.rows == raceRows, "overview refreshes reuse race rows")
local raceReport = deepCopy(live)
raceReport.races = { HUMAN = 2, SKYBORNE = 1, UNKNOWN = 1 }
render.set(card, raceReport, true)
assert(card.racesTitle:IsVisible() and card.racesText:GetText():find("Human: 2 (50%)", 1, true)
    and card.racesText:GetText():find("Unknown: 1 (25%)", 1, true), "guild previews show reported race totals and shares")
render.set(card, live, true)
assert(card.racesText:GetText() == "No race data reported yet.", "older reports do not invent race populations")
render.set(card, raceReport, false)
assert(not card.racesText:IsVisible(), "race details stay inside the expanded guild preview")
print("PASS: overview race counts, main/alt scope, unknown races, reusable rows and expanded guild previews")

-- Use the real shared search styling and dashboard input setup. Clearing a
-- typed/autofilled name must reset the search, suggestions, and scroll position.
function methods:GetRegions() end
function methods:HasFocus() return self.focused == true end
function methods:GetNumLetters() return #self:GetText() end
function methods:ClearFocus() self.focused = false; self:Fire("OnEditFocusLost") end
local previousSetText = methods.SetText
function methods:SetText(value)
    previousSetText(self, value)
    if self.kind == "EditBox" then self:Fire("OnTextChanged", false) end
end
local coreFile = assert(io.open("iRC_Core.lua", "r"))
local coreSource = coreFile:read("*a"); coreFile:close()
local skinStart = assert(coreSource:find("function iRC:StyleSearchBox", 1, true))
local skinEnd = assert(coreSource:find("-- Safe values and identity normalization", skinStart, true))
assert(load("local iRC = ...\n" .. coreSource:sub(skinStart, skinEnd - 1), "@iRC_Core.lua"))(addon)
local dashboardFile = assert(io.open("iRC_ConnectionDashboard.lua", "r"))
local dashboardSource = dashboardFile:read("*a"); dashboardFile:close()
local inputStart = assert(dashboardSource:find("    frame.verificationSearch = CreateFrame", 1, true))
local inputEnd = assert(dashboardSource:find("    frame.summaryCards = {}", inputStart, true))
local searchFrame = { tab = "Verification", main = widget("Frame", parent), scroll = widget("ScrollFrame", parent) }
local searchRefreshes = 0
local dashboard = { Refresh = function() searchRefreshes = searchRefreshes + 1 end }
assert(load("local iRC, Dashboard, frame = ...\nlocal main = frame.main\nlocal function setBackdrop() end\n"
    .. dashboardSource:sub(inputStart, inputEnd - 1), "@iRC_ConnectionDashboard.lua"))(addon, dashboard, searchFrame)
local search = searchFrame.verificationSearch
assert(not search.iRCSearchClear:IsShown(), "an empty input hides its clear button")
search.focused = true
search:SetText("Main H")
assert(search.iRCSearchClear:IsShown() and searchFrame.verificationSuggestions:IsShown(),
    "typing a name reveals the clear button and roster suggestions")
search:Fire("OnTabPressed")
assert(search:GetText() == "Main Human" and search.iRCSearchClear:IsShown(), "autofilled names remain clearable")
searchFrame.scroll:SetVerticalScroll(500)
local beforeClear = searchRefreshes
search.iRCSearchClear:Fire("OnClick")
assert(search:GetText() == "" and not search:HasFocus() and not search.iRCSearchClear:IsShown())
assert(not searchFrame.verificationSuggestions:IsShown() and searchFrame.scroll:GetVerticalScroll() == 0
    and searchRefreshes == beforeClear + 1, "one clear click restores the unsearched list without extra refreshes")
print("PASS: real verification search styling, autocomplete, clear button, focus and scroll reset")

local home, abroad, locked = deepCopy(live), deepCopy(live), deepCopy(live)
home.serverRuleset, home.serverName = "s-18-3-10-0-pve", "Home Realm"
abroad.serverRuleset, abroad.serverName = "s-18-3-11-0-pvp", "Other Realm"
abroad.rules = { guildFoundOnly = true, progression = "GUILD_FOUND" }
locked.guildName, locked.serverRuleset, locked.serverName = "Locked Guild", home.serverRuleset, "Third Realm"
locked.rules = { classLock = true, guildClass = "MAGE" }
function addon:GetGuildDirectoryOverview() return { home, abroad, locked } end
local oldGuildInfo, oldRealm = GetGuildInfo, GetRealmName
GetGuildInfo = function() return home.guildName end
GetRealmName = function() return home.serverName end
local directory = { factionSections = {}, raceCards = {}, memberRows = {},
    scrollContent = widget("Frame", parent), scroll = widget("ScrollFrame", parent),
    guildStatsSearch = widget("EditBox", parent), contentTitle = widget("FontString", parent),
    contentSubtitle = widget("FontString", parent) }
assert(render.directory(directory, "ALL", "ALL") == 3)
assert(directory.factionSections.MyGuild and directory.factionSections.MyGuild.title:GetText():find("(1)", 1, true),
    "a foreign guild with the same name is not marked as the player's own guild")
local tags = {}
for _, row in ipairs(directory.raceCards) do if row:IsShown() then tags[row.origin:GetText()] = row.tag:GetText() end end
assert(tags["[Other Realm · PvP]"]:find("Guild-Found", 1, true), "origin and guild challenge use independent visible tags")
assert(render.directory(directory, "ALL", "pvp") == 1, "All filters by server ruleset")
assert(render.directory(directory, "CHALLENGES", "ALL") == 2, "Challenges excludes ordinary guilds")
assert(render.directory(directory, "CHALLENGES", "CLASS_LOCKED") == 1, "challenge filters do not depend on server ruleset")
directory.guildStatsSearch:SetText("other realm")
assert(render.directory(directory, "ALL", "ALL") == 1, "guild search also finds the report's realm")
GetGuildInfo, GetRealmName = oldGuildInfo, oldRealm
function addon:IsForeverClient() return true end
local internalRealm = deepCopy(abroad)
internalRealm.serverName = "CAMWOW EU4 Realm 6 PvP"
render.set(card, internalRealm, false)
assert(card.origin:GetText() == "[PvP]" and internalRealm.serverName == "CAMWOW EU4 Realm 6 PvP",
    "Forever tags hide internal realm names while preserving the report origin")
print("PASS: independent server/challenge browsing, origin tags, realm search, and same-name own-guild detection")
