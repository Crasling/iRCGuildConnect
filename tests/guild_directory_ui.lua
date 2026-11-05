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
function methods:GetVerticalScroll() return 0 end
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
local boundary = assert(source:find("local function updateRaceOverview(frame)", 1, true))
local render = assert(load(source:sub(1, boundary - 1)
    .. "\nreturn { create = makeRaceCard, set = setRaceCard, height = guildCardHeight, ui = UI }",
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
