local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local GuildMap = { positions = {}, pins = {}, pool = {} }
iRC.GuildMap = GuildMap

local POSITION_VERSION = "1"
local POSITION_LIFETIME = 90
local POSITION_UPDATE_INTERVAL = 5
local POSITION_HEARTBEAT = 20
local DEFAULT_PIN_SIZE = 12
local CLUSTER_MINIMUM_DISTANCE = 18
local MAX_CLUSTER_TOOLTIP_MEMBERS = 5
local initialized, mapInitialized, mapInitializationArmed, mapInitializationPending, positionSendPending
local mapTicker
local pinMenu
local mapControls
local lastSentMapId, lastSentXWire, lastSentYWire, lastPositionSentAt
local lastDisplayedMapId
local lastGroupedMembers = {}

local function hidePinMenu()
    if pinMenu then pinMenu:Hide() end
end

local function classColoredName(name, classFile)
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile or ""]
    if not color then return name end
    return string.format("|cff%02x%02x%02x%s|r",
        math.floor(color.r * 255 + 0.5),
        math.floor(color.g * 255 + 0.5),
        math.floor(color.b * 255 + 0.5), name)
end

local function showPinMenu(pin)
    if not pin.playerName or (pin.clusterMembers and #pin.clusterMembers > 1) then return end
    if not pinMenu then
        pinMenu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        pinMenu:SetSize(120, 58)
        pinMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        pinMenu:SetClampedToScreen(true)
        pinMenu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        pinMenu:SetBackdropColor(0.025, 0.02, 0.015, 0.97)
        pinMenu:SetBackdropBorderColor(0.65, 0.43, 0.15, 1)
        pinMenu:EnableMouse(true)
        local function addAction(offset, prefix, action)
            local button = CreateFrame("Button", nil, pinMenu, "BackdropTemplate")
            button:SetHeight(23)
            button:SetPoint("TOPLEFT", 5, offset)
            button:SetPoint("TOPRIGHT", -5, offset)
            button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
            button:SetBackdropColor(0.09, 0.07, 0.045, 0.9)
            button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            button.text:SetPoint("LEFT", 8, 0)
            button:SetScript("OnClick", function()
                local name = pinMenu.playerName
                hidePinMenu()
                if name then action(name) end
            end)
            button.prefix = prefix
            return button
        end
        pinMenu.whisper = addAction(-5, "Whisper ", function(name)
            iRC:OpenWhisper(name)
        end)
        pinMenu.invite = addAction(-30, "Invite ", function(name)
            if C_PartyInfo and C_PartyInfo.InviteUnit then
                C_PartyInfo.InviteUnit(name)
            end
        end)
        pinMenu:Hide()
        local outsideClickWatcher = CreateFrame("Frame")
        outsideClickWatcher:RegisterEvent("GLOBAL_MOUSE_DOWN")
        outsideClickWatcher:SetScript("OnEvent", function()
            if pinMenu:IsShown() and not iRC:IsMouseOverFrame(pinMenu) then hidePinMenu() end
        end)
    end
    pinMenu.playerName = pin.playerName
    local shortName = iRC:FormatPlayerName(pin.playerName)
    local coloredName = classColoredName(shortName, pin.classFile)
    pinMenu.whisper.text:SetText(pinMenu.whisper.prefix .. coloredName)
    pinMenu.invite.text:SetText(pinMenu.invite.prefix .. coloredName)
    pinMenu:SetWidth(math.max(100, math.ceil(math.max(pinMenu.whisper.text:GetStringWidth(), pinMenu.invite.text:GetStringWidth())) + 26))
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    pinMenu:ClearAllPoints()
    pinMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    pinMenu:Show()
end

local function enabled()
    return iRC:IsGuildConnectionActive() and iRC:GetConnectionRules().guildMapEnabled == true
end

function GuildMap:IsVisible()
    return enabled() and iRC:GetSettings().showGuildMap ~= false
end

local function clearPin(name)
    local pin = GuildMap.pins[name]
    if not pin then return end
    if pinMenu and pinMenu:IsShown() and pinMenu.playerName == pin.playerName then hidePinMenu() end
    pin:Hide()
    pin.playerName, pin.classFile, pin.level = nil, nil, nil
    pin.className, pin.clusterMembers = nil, nil
    if pin.count then pin.count:Hide() end
    if pin.clusterDots then
        for _, dot in ipairs(pin.clusterDots) do
            dot.border:Hide()
            dot.center:Hide()
        end
    end
    GuildMap.pins[name] = nil
    GuildMap.pool[#GuildMap.pool + 1] = pin
end

function GuildMap:Clear()
    for name in pairs(self.pins) do clearPin(name) end
    wipe(self.positions)
end

function GuildMap:Cleanup()
    if not enabled() then self:Clear(); return end
    local now = GetTime()
    local rosterOnline = {}
    if iRC.GetGuildRosterSnapshot then
        for _, member in ipairs(iRC:GetGuildRosterSnapshot()) do
            rosterOnline[iRC:NormalizeName(member.name)] = member.online == true
        end
    end
    for name, position in pairs(self.positions) do
        if now - (position.receivedAt or 0) > POSITION_LIFETIME or rosterOnline[name] == false then
            self.positions[name] = nil
            clearPin(name)
        end
    end
end

local function acquirePin(parent)
    local pin = table.remove(GuildMap.pool)
    if not pin then
        pin = CreateFrame("Frame", nil, parent)
        local size = math.max(5, math.min(15, math.floor(tonumber(iRC:GetSettings().guildMapPinSize) or DEFAULT_PIN_SIZE)))
        pin:SetSize(size, size)
        pin:SetFrameStrata("HIGH")
        pin.border = pin:CreateTexture(nil, "BACKGROUND")
        pin.border:SetAllPoints()
        pin.border:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        pin.border:SetVertexColor(0, 0, 0, 1)
        pin.center = pin:CreateTexture(nil, "ARTWORK")
        pin.center:SetPoint("TOPLEFT", 2, -2)
        pin.center:SetPoint("BOTTOMRIGHT", -2, 2)
        pin.center:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        pin.clusterDots = {}
        for index = 1, 3 do
            local border = pin:CreateTexture(nil, "BACKGROUND")
            border:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
            border:SetVertexColor(0, 0, 0, 1)
            border:Hide()
            local center = pin:CreateTexture(nil, "ARTWORK")
            center:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
            center:Hide()
            pin.clusterDots[index] = { border = border, center = center }
        end
        pin.count = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        local fontFile, fontSize = pin.count:GetFont()
        if fontFile and fontSize then pin.count:SetFont(fontFile, math.max(9, fontSize), "THICKOUTLINE") end
        pin.count:SetTextColor(1, 0.82, 0, 1)
        pin.count:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", 4, -3)
        pin.count:Hide()
        pin:EnableMouse(true)
        pin:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.clusterMembers and #self.clusterMembers > 1 then
                GameTooltip:AddLine("Nearby guild members (" .. tostring(#self.clusterMembers) .. ")", 1, 0.82, 0)
                local visibleCount = math.min(#self.clusterMembers, MAX_CLUSTER_TOOLTIP_MEMBERS)
                for index = 1, visibleCount do
                    local member = self.clusterMembers[index]
                    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.classFile or ""]
                    local details = "Level " .. tostring(member.level or 0) .. " " .. tostring(member.className or member.classFile or "Unknown")
                    if color then
                        GameTooltip:AddDoubleLine(iRC:FormatPlayerName(member.playerName or "Unknown"), details, color.r, color.g, color.b, 0.65, 0.65, 0.65)
                    else
                        GameTooltip:AddDoubleLine(iRC:FormatPlayerName(member.playerName or "Unknown"), details, 1, 1, 1, 0.65, 0.65, 0.65)
                    end
                end
                local remaining = #self.clusterMembers - visibleCount
                if remaining > 0 then
                    GameTooltip:AddLine("+ " .. tostring(remaining) .. " more nearby", 0.72, 0.72, 0.72)
                end
                GameTooltip:Show()
                return
            end
            local shortName = iRC:FormatPlayerName(self.playerName or "Unknown")
            local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[self.classFile or ""]
            if color then GameTooltip:AddLine(shortName, color.r, color.g, color.b) else GameTooltip:AddLine(shortName) end
            GameTooltip:AddLine("Level " .. tostring(self.level or 0) .. " " .. tostring(self.className or self.classFile or "Unknown"), 0.65, 0.65, 0.65)
            GameTooltip:Show()
        end)
        pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
        pin:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" then
                GameTooltip:Hide()
                showPinMenu(self)
            end
        end)
    end
    pin:SetParent(parent)
    local size = math.max(5, math.min(15, math.floor(tonumber(iRC:GetSettings().guildMapPinSize) or DEFAULT_PIN_SIZE)))
    pin:SetSize(size, size)
    pin:Show()
    return pin
end

local function memberDetails(name, position)
    local profile = iRC:FindConnectionProfile(name)
    local classFile = profile and profile.class or ""
    return {
        key = name,
        playerName = position.name or name,
        classFile = classFile,
        level = profile and profile.level or 0,
        className = classFile ~= "" and classFile:sub(1, 1) .. classFile:sub(2):lower() or "Unknown",
    }
end

local function configureSinglePin(pin, member, size)
    pin:SetSize(size, size)
    pin.border:Show()
    pin.center:Show()
    pin.center:ClearAllPoints()
    local inset = math.min(2, math.max(1, math.floor((size - 1) / 2)))
    pin.center:SetPoint("TOPLEFT", inset, -inset)
    pin.center:SetPoint("BOTTOMRIGHT", -inset, inset)
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.classFile or ""]
    pin.center:SetVertexColor(color and color.r or 1, color and color.g or 1, color and color.b or 1, 1)
    pin.playerName, pin.classFile, pin.level = member.playerName, member.classFile, member.level
    pin.className, pin.clusterMembers = member.className, { member }
    pin.count:Hide()
    for _, dot in ipairs(pin.clusterDots) do
        dot.border:Hide()
        dot.center:Hide()
    end
end

local function configureClusterPin(pin, members, size)
    local width, height = math.ceil(size * 1.75), math.ceil(size * 1.55)
    pin:SetSize(width, height)
    pin.border:Hide()
    pin.center:Hide()
    pin.playerName, pin.classFile, pin.level, pin.className = nil, nil, nil, nil
    pin.clusterMembers = members
    local offsets = {
        { 0, math.floor(size * 0.28) },
        { -math.floor(size * 0.38), -math.floor(size * 0.27) },
        { math.floor(size * 0.38), -math.floor(size * 0.27) },
    }
    for index, dot in ipairs(pin.clusterDots) do
        local member = members[index]
        if member then
            dot.border:ClearAllPoints()
            dot.border:SetSize(size, size)
            dot.border:SetPoint("CENTER", pin, "CENTER", offsets[index][1], offsets[index][2])
            dot.border:Show()
            dot.center:ClearAllPoints()
            local innerSize = math.max(1, size - 4)
            dot.center:SetSize(innerSize, innerSize)
            dot.center:SetPoint("CENTER", dot.border, "CENTER")
            local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.classFile or ""]
            dot.center:SetVertexColor(color and color.r or 1, color and color.g or 1, color and color.b or 1, 1)
            dot.center:Show()
        else
            dot.border:Hide()
            dot.center:Hide()
        end
    end
    pin.count:SetText(tostring(#members))
    pin.count:Show()
end

local function mapPosition(mapId, x, y, displayedMapId)
    if mapId == displayedMapId then return x, y end
    if not CreateVector2D or not C_Map or not C_Map.GetWorldPosFromMapPos or not C_Map.GetMapPosFromWorldPos then return nil end
    local ok, convertedX, convertedY = pcall(function()
        local continent, world = C_Map.GetWorldPosFromMapPos(mapId, CreateVector2D(x, y))
        if not continent or not world then return nil end
        local _, position = C_Map.GetMapPosFromWorldPos(continent, world, displayedMapId)
        if not position then return nil end
        return position:GetXY()
    end)
    if not ok or not convertedX or not convertedY or convertedX < 0 or convertedX > 1 or convertedY < 0 or convertedY > 1 then return nil end
    return convertedX, convertedY
end

local function groupedMembers()
    local members = {}
    local prefix, count = IsInRaid() and "raid" or "party", IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
    for index = 1, count do
        local name = GetUnitName(prefix .. index, true)
        if name then members[iRC:NormalizeName(name)] = true end
    end
    return members
end

function GuildMap:UpdatePins(cachedOnly)
    -- Cached map positions are safe local data and must redraw immediately
    -- when the displayed map changes, including during startup/combat traffic
    -- throttling. Native roster cleanup remains deferred until it is safe.
    if not cachedOnly and iRC:DeferLowTraffic("ui:guild-map", function() GuildMap:UpdatePins() end) then return end
    if not cachedOnly then self:Cleanup() end
    if not WorldMapFrame or not WorldMapFrame:IsShown() or not self:IsVisible() then
        for name in pairs(self.pins) do clearPin(name) end
        return
    end
    local mapId = WorldMapFrame:GetMapID()
    local child = WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
    if not mapId or not child or child:GetWidth() <= 0 or child:GetHeight() <= 0 then return end
    local shown = {}
    local grouped
    if cachedOnly then
        grouped = lastGroupedMembers
    else
        grouped = groupedMembers()
        lastGroupedMembers = grouped
    end
    local visible = {}
    for name, position in pairs(self.positions) do
        -- Blizzard already draws party and raid members. Suppress our guild
        -- pin so one character cannot appear at both a cached and live spot.
        local x, y
        if not grouped[name] then x, y = mapPosition(position.mapId, position.x, position.y, mapId) end
        if x and y then
            visible[#visible + 1] = { x = x, y = y, px = x * child:GetWidth(), py = y * child:GetHeight(), member = memberDetails(name, position) }
        end
    end
    table.sort(visible, function(a, b) return a.member.key < b.member.key end)
    local size = math.max(5, math.min(15, math.floor(tonumber(iRC:GetSettings().guildMapPinSize) or DEFAULT_PIN_SIZE)))
    local distance = math.max(CLUSTER_MINIMUM_DISTANCE, size * 1.75)
    local distanceSquared = distance * distance
    local clusters = {}
    local clusterGrid = {}
    local function gridKey(cellX, cellY)
        return tostring(cellX) .. ":" .. tostring(cellY)
    end
    for _, entry in ipairs(visible) do
        local cellX, cellY = math.floor(entry.px / distance), math.floor(entry.py / distance)
        local closest, closestDistance
        for offsetX = -1, 1 do
            for offsetY = -1, 1 do
                local candidates = clusterGrid[gridKey(cellX + offsetX, cellY + offsetY)]
                for _, cluster in ipairs(candidates or {}) do
                    local dx, dy = entry.px - cluster.anchorX, entry.py - cluster.anchorY
                    local squared = dx * dx + dy * dy
                    if squared <= distanceSquared and (not closestDistance or squared < closestDistance) then
                        closest, closestDistance = cluster, squared
                    end
                end
            end
        end
        if closest then
            closest.entries[#closest.entries + 1] = entry
        else
            local cluster = { entries = { entry }, anchorX = entry.px, anchorY = entry.py }
            clusters[#clusters + 1] = cluster
            local key = gridKey(cellX, cellY)
            clusterGrid[key] = clusterGrid[key] or {}
            clusterGrid[key][#clusterGrid[key] + 1] = cluster
        end
    end
    for _, cluster in ipairs(clusters) do
        table.sort(cluster.entries, function(a, b) return a.member.key < b.member.key end)
        local members, keys, xTotal, yTotal = {}, {}, 0, 0
        for _, entry in ipairs(cluster.entries) do
            members[#members + 1], keys[#keys + 1] = entry.member, entry.member.key
            xTotal, yTotal = xTotal + entry.px, yTotal + entry.py
        end
        local key = #members == 1 and keys[1] or "cluster:" .. table.concat(keys, ",")
        shown[key] = true
        local pin = self.pins[key] or acquirePin(child)
        self.pins[key] = pin
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", child, "TOPLEFT", xTotal / #members, -(yTotal / #members))
        if #members == 1 then configureSinglePin(pin, members[1], size) else configureClusterPin(pin, members, size) end
    end
    for name in pairs(self.pins) do if not shown[name] then clearPin(name) end end
end

function GuildMap:BroadcastPosition(force)
    -- Forever can protect map/unit position data during combat. Resume one
    -- current position broadcast after combat instead of touching secret data.
    if iRC:DeferLowTraffic("traffic:guild-map-position", function() GuildMap:BroadcastPosition(force) end) then return false end
    if not enabled() or iRC:GetSettings().shareGuildMapPosition == false or not C_Map then return false end
    local _, instanceType = GetInstanceInfo()
    if instanceType and instanceType ~= "none" then return false end
    local mapId = C_Map.GetBestMapForUnit("player")
    local position = mapId and C_Map.GetPlayerMapPosition(mapId, "player")
    if not position then return false end
    local x, y = position:GetXY()
    if not x or not y or (x == 0 and y == 0) then return false end
    local xWire, yWire = math.floor(x * 10000 + 0.5), math.floor(y * 10000 + 0.5)
    local now = GetTime and GetTime() or 0
    local unchanged = lastSentMapId == mapId and lastSentXWire == xWire and lastSentYWire == yWire
    if not force and unchanged and now - (lastPositionSentAt or 0) < POSITION_HEARTBEAT then return false end
    local message = table.concat({ "MAP_POS", POSITION_VERSION, tostring(mapId), tostring(xWire), tostring(yWire) }, "\t")
    local sent = iRC:SendAddonTraffic(iRC.Prefix, message, "GUILD")
    if sent then
        lastSentMapId, lastSentXWire, lastSentYWire = mapId, xWire, yWire
        lastPositionSentAt = now
    end
    return sent
end

function GuildMap:SchedulePosition(maximumDelay, minimumDelay, force)
    if positionSendPending then return false end
    if not C_Timer or not C_Timer.After then return self:BroadcastPosition() end
    positionSendPending = true
    minimumDelay = math.max(0, tonumber(minimumDelay) or 0)
    maximumDelay = math.max(minimumDelay, tonumber(maximumDelay) or 3)
    C_Timer.After(minimumDelay + math.random() * (maximumDelay - minimumDelay), function()
        positionSendPending = false
        GuildMap:BroadcastPosition(force)
    end)
    return true
end

local function scheduleNextPosition()
    if not C_Timer or not C_Timer.After then return end
    C_Timer.After(POSITION_UPDATE_INTERVAL, function()
        GuildMap:BroadcastPosition()
        GuildMap:Cleanup()
        scheduleNextPosition()
    end)
end

local function initializeMap()
    if mapInitialized or not WorldMapFrame or not WorldMapFrame.ScrollContainer
        or type(WorldMapFrame.GetMapID) ~= "function"
        or type(WorldMapFrame.HookScript) ~= "function"
        or type(WorldMapFrame.ScrollContainer.HookScript) ~= "function" then return end
    mapInitialized = true
    local function addLabelOutline(label)
        local fontFile, fontSize = label:GetFont()
        if fontFile and fontSize then label:SetFont(fontFile, fontSize, "OUTLINE") end
    end
    -- Forever's WorldMapFrame is a MapCanvas and must be allowed to finish
    -- building its own children without addon-owned controls being attached to
    -- it. Keep iRC's settings in an independent overlay anchored to the map.
    mapControls = CreateFrame("Frame", "iRCGuildMapControls", UIParent)
    mapControls:SetSize(230, 52)
    mapControls:SetPoint("TOPRIGHT", WorldMapFrame.ScrollContainer, "TOPRIGHT", -12, -12)
    mapControls:SetFrameStrata("FULLSCREEN_DIALOG")
    mapControls:SetFrameLevel((WorldMapFrame:GetFrameLevel() or 0) + 30)
    mapControls:SetClampedToScreen(true)
    mapControls:Hide()

    local toggle = CreateFrame("CheckButton", "iRCGuildMapToggle", mapControls, "UICheckButtonTemplate")
    toggle:SetSize(22, 22)
    toggle:SetPoint("TOPRIGHT", mapControls, "TOPRIGHT", 0, 0)
    toggle.label = toggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toggle.label:SetPoint("RIGHT", toggle, "LEFT", -2, 0)
    toggle.label:SetText("iRC: Share my Pos.")
    addLabelOutline(toggle.label)
    toggle:SetScript("OnClick", function(self)
        iRC:GetSettings().shareGuildMapPosition = self:GetChecked() and true or false
        if self:GetChecked() then GuildMap:SchedulePosition(0.5, 0, true) end
        if iRC.RefreshOptionsIfShown then iRC:RefreshOptionsIfShown() end
    end)
    local showToggle = CreateFrame("CheckButton", "iRCGuildMapShowToggle", mapControls, "UICheckButtonTemplate")
    showToggle:SetSize(22, 22)
    showToggle:SetPoint("TOPRIGHT", toggle, "BOTTOMRIGHT", 0, -2)
    showToggle.label = showToggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    showToggle.label:SetPoint("RIGHT", showToggle, "LEFT", -2, 0)
    showToggle.label:SetText("iRC: Show Guild Members")
    addLabelOutline(showToggle.label)
    showToggle:SetScript("OnClick", function(self)
        GuildMap:SetShown(self:GetChecked() and true or false)
        if iRC.RefreshOptionsIfShown then iRC:RefreshOptionsIfShown() end
    end)
    local function updateToggle()
        local visible = enabled() and WorldMapFrame:IsShown()
        mapControls:SetShown(visible)
        toggle:SetShown(visible)
        toggle:SetChecked(iRC:GetSettings().shareGuildMapPosition ~= false)
        showToggle:SetShown(visible)
        showToggle:SetChecked(iRC:GetSettings().showGuildMap ~= false)
    end
    GuildMap.UpdateToggle = updateToggle
    WorldMapFrame.ScrollContainer:HookScript("OnMouseWheel", function() GuildMap:UpdatePins(true) end)
    WorldMapFrame:HookScript("OnUpdate", function(self)
        local displayedMapId = self:GetMapID()
        if displayedMapId ~= lastDisplayedMapId then
            lastDisplayedMapId = displayedMapId
            GuildMap:UpdatePins(true)
        end
    end)
    WorldMapFrame:HookScript("OnShow", function()
        updateToggle()
        -- Incoming positions update pins immediately. This slower ticker is
        -- only needed to expire stale pins while the map remains open.
        if not mapTicker and C_Timer and C_Timer.NewTicker then mapTicker = C_Timer.NewTicker(15, function() GuildMap:UpdatePins() end) end
        lastDisplayedMapId = WorldMapFrame:GetMapID()
        GuildMap:UpdatePins(true)
        GuildMap:UpdatePins()
        GuildMap:SchedulePosition(0.5, 0, true)
    end)
    WorldMapFrame:HookScript("OnHide", function()
        hidePinMenu()
        if mapControls then mapControls:Hide() end
        if mapTicker then mapTicker:Cancel(); mapTicker = nil end
        for name in pairs(GuildMap.pins) do clearPin(name) end
    end)
    updateToggle()
    -- When initialization was deferred from the first OnShow, the normal
    -- OnShow hook above was not installed in time for that same opening.
    if WorldMapFrame:IsShown() then
        if not mapTicker and C_Timer and C_Timer.NewTicker then mapTicker = C_Timer.NewTicker(15, function() GuildMap:UpdatePins() end) end
        lastDisplayedMapId = WorldMapFrame:GetMapID()
        GuildMap:UpdatePins(true)
        GuildMap:UpdatePins()
        GuildMap:SchedulePosition(0.5, 0, true)
    end
end

local function scheduleMapInitialization()
    if mapInitialized or mapInitializationPending then return end
    mapInitializationPending = true
    local function finish()
        mapInitializationPending = false
        initializeMap()
    end
    -- Forever loads the map canvas lazily. Waiting one frame prevents iRC from
    -- touching WorldMapFrame while Blizzard is still applying its mixins.
    if C_Timer and C_Timer.After then
        C_Timer.After(0, finish)
    else
        finish()
    end
end

local function armMapInitialization()
    if mapInitialized or mapInitializationArmed or not WorldMapFrame
        or type(WorldMapFrame.HookScript) ~= "function" then return end
    mapInitializationArmed = true
    -- Do not build iRC's map controls during PLAYER_LOGIN on a UI reload.
    -- At that point Forever has created WorldMapFrame but may not have
    -- completed its internal map-canvas state. OnShow runs only after
    -- Blizzard has safely finished opening the map.
    WorldMapFrame:HookScript("OnShow", function()
        scheduleMapInitialization()
    end)
end

function GuildMap:SetShown(enabledValue)
    iRC:GetSettings().showGuildMap = enabledValue and true or false
    if self.UpdateToggle then self.UpdateToggle() end
    self:UpdatePins(true)
end

function GuildMap:SetPinSize(value)
    value = math.max(5, math.min(15, math.floor(tonumber(value) or DEFAULT_PIN_SIZE)))
    iRC:GetSettings().guildMapPinSize = value
    self:UpdatePins(true)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        if initialized then return end
        initialized = true
        if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then armMapInitialization() end
        GuildMap:SchedulePosition(1.5, 0.5, true)
        scheduleNextPosition()
    elseif event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == "Blizzard_WorldMap" then armMapInitialization() end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        -- If the map is open, swap to already cached locations immediately;
        -- the outgoing live-position update remains separately throttled.
        GuildMap:UpdatePins(true)
        GuildMap:SchedulePosition(0.5, 0, true)
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- Remove newly grouped members immediately, even if the full map
        -- refresh is deferred by combat low-traffic mode.
        if iRC:IsForeverClient() and ((InCombatLockdown and InCombatLockdown())
            or (UnitAffectingCombat and UnitAffectingCombat("player"))) then
            GuildMap:UpdatePins()
            return
        end
        for name in pairs(groupedMembers()) do clearPin(name) end
        GuildMap:UpdatePins()
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, _, sender = ...
        if iRC:HasSecretValues(prefix, message, sender) then return end
        if prefix ~= iRC.Prefix or not enabled() or not iRC:IsGuildMemberName(sender)
            or iRC:NormalizeName(sender) == iRC:NormalizeName(iRC:GetPlayerName()) then return end
        local version, mapId, xWire, yWire = tostring(message or ""):match("^MAP_POS\t([^\t]+)\t(%d+)\t(%d+)\t(%d+)$")
        mapId, xWire, yWire = tonumber(mapId), tonumber(xWire), tonumber(yWire)
        if version ~= POSITION_VERSION or not mapId or not xWire or not yWire or xWire > 10000 or yWire > 10000 then return end
        GuildMap.positions[iRC:NormalizeName(sender)] = {
            name = sender, mapId = mapId, x = xWire / 10000, y = yWire / 10000, receivedAt = GetTime(),
        }
        GuildMap:UpdatePins()
    end
end)
