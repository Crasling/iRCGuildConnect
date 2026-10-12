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
local LOCAL_LAYER_LIFETIME = 300
local LAYER_PANEL_WIDTH = 126
local LAYER_PANEL_HEIGHT = 42
local initialized, mapInitialized, mapInitializationArmed, mapInitializationPending, positionSendPending
local mapTicker
local layerPanelTicker
local pinMenu
local mapControls
local layerPanel
local lastSentMapId, lastSentXWire, lastSentYWire, lastPositionSentAt
local lastDisplayedMapId
local lastGroupedMembers = {}
local localLayer
local knownLayerIds = {}
local layerUsers = {}
local lastLayerBroadcastSignature
local lastLayerBroadcastAt = 0

local function parseWorldLayerGuid(guid)
    if iRC:IsSecretValue(guid) or type(guid) ~= "string" or guid == "" then return nil end
    local unitType, _, serverId, instanceId, zoneUID = strsplit("-", guid)
    -- Player-controlled pets can retain an owner-specific GUID context and are
    -- not reliable evidence of the shard occupied by the player.
    if unitType ~= "Creature" and unitType ~= "Vehicle" then return nil end
    serverId, instanceId, zoneUID = tonumber(serverId), tonumber(instanceId), tonumber(zoneUID)
    if not serverId or not instanceId or not zoneUID or zoneUID <= 0 then return nil end
    return zoneUID, serverId, instanceId, unitType
end

local function currentPlayerMapId()
    if not C_Map or type(C_Map.GetBestMapForUnit) ~= "function" then return nil end
    local mapId = C_Map.GetBestMapForUnit("player")
    if iRC:IsSecretValue(mapId) or type(mapId) ~= "number" then return nil end
    return mapId
end

local function getLayerNumber(zoneUID, serverId, instanceId)
    local scope = tostring(serverId or 0) .. ":" .. tostring(instanceId or 0)
    local ids = knownLayerIds[scope]
    if not ids then
        ids = {}
        knownLayerIds[scope] = ids
    end
    ids[zoneUID] = true
    local sorted = {}
    for knownId in pairs(ids) do sorted[#sorted + 1] = knownId end
    table.sort(sorted)
    for index, knownId in ipairs(sorted) do
        if knownId == zoneUID then return math.max(1, math.min(99, index)) end
    end
    return 1
end

function GuildMap:GetLayerRegistryWire(serverId, instanceId)
    local ids = knownLayerIds[tostring(serverId or 0) .. ":" .. tostring(instanceId or 0)] or {}
    local sorted = {}
    for zoneUID in pairs(ids) do sorted[#sorted + 1] = zoneUID end
    table.sort(sorted)
    local wire = {}
    for index = 1, math.min(99, #sorted) do wire[index] = tostring(sorted[index]) end
    return table.concat(wire, ",")
end

function GuildMap:BroadcastLocalLayer(force)
    local layer = self:GetLocalLayer()
    if not layer or iRC:GetSettings().showLayerPanel == false
        or not iRC.RaceGrid or not iRC.RaceGrid.BroadcastLayerState then return false end
    if (InCombatLockdown and InCombatLockdown())
        or (UnitAffectingCombat and UnitAffectingCombat("player")) then return false end
    local registry = self:GetLayerRegistryWire(layer.serverId, layer.instanceId)
    local signature = tostring(layer.serverId) .. ":" .. tostring(layer.instanceId) .. ":"
        .. tostring(layer.zoneUID) .. ":" .. registry
    local now = GetTime and GetTime() or 0
    if not force and signature == lastLayerBroadcastSignature
        and now - lastLayerBroadcastAt < 60 then return false end
    layer.registryWire = registry
    if not iRC.RaceGrid:BroadcastLayerState(layer) then return false end
    lastLayerBroadcastSignature = signature
    lastLayerBroadcastAt = now
    return true
end

local function saveLayerPanelPosition()
    if not layerPanel then return end
    local point, _, relativePoint, x, y = layerPanel:GetPoint(1)
    local settings = iRC:GetSettings()
    settings.layerPanelPoint = point or "TOP"
    settings.layerPanelRelativePoint = relativePoint or point or "TOP"
    settings.layerPanelX = math.floor((tonumber(x) or 0) + 0.5)
    settings.layerPanelY = math.floor((tonumber(y) or -90) + 0.5)
end

local function initializeLayerPanel()
    if layerPanel then return end
    local settings = iRC:GetSettings()
    layerPanel = CreateFrame("Frame", "iRCLocalLayerPanel", UIParent, "BackdropTemplate")
    layerPanel:SetSize(LAYER_PANEL_WIDTH, LAYER_PANEL_HEIGHT)
    layerPanel:SetScale(1)
    layerPanel:SetFrameStrata("MEDIUM")
    layerPanel:SetFrameLevel(60)
    layerPanel:SetClampedToScreen(true)
    layerPanel:SetMovable(true)
    layerPanel:EnableMouse(true)
    layerPanel:RegisterForDrag("LeftButton")
    layerPanel:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    layerPanel:SetBackdropColor(0.018, 0.016, 0.012, 0.94)
    layerPanel:SetBackdropBorderColor(0.78, 0.48, 0.12, 1)
    layerPanel.title = layerPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    layerPanel.title:SetPoint("LEFT", layerPanel, "LEFT", 12, 0)
    layerPanel.title:SetText("LAYER")
    layerPanel.title:SetTextColor(1, 0.67, 0.15)
    local titleFont = GameFontNormal and GameFontNormal:GetFont()
    if titleFont then layerPanel.title:SetFont(titleFont, 14, "OUTLINE") end
    layerPanel.value = layerPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    layerPanel.value:SetPoint("RIGHT", layerPanel, "RIGHT", -17, 0)
    layerPanel.value:SetText("--")
    layerPanel.value:SetTextColor(0.72, 0.72, 0.72)
    local valueFont = GameFontNormalLarge and GameFontNormalLarge:GetFont()
    if valueFont then layerPanel.value:SetFont(valueFont, 25, "OUTLINE") end

    local resize
    local function applyPanelScale(scale)
        scale = math.max(0.75, math.min(2.5, tonumber(scale) or 1))
        layerPanel.displayScale = scale
        layerPanel:SetSize(LAYER_PANEL_WIDTH * scale, LAYER_PANEL_HEIGHT * scale)
        layerPanel.title:ClearAllPoints()
        layerPanel.title:SetPoint("LEFT", layerPanel, "LEFT", 12 * scale, 0)
        if titleFont then layerPanel.title:SetFont(titleFont, 14 * scale, "OUTLINE") end
        layerPanel.value:ClearAllPoints()
        layerPanel.value:SetPoint("RIGHT", layerPanel, "RIGHT", -17 * scale, 0)
        if valueFont then layerPanel.value:SetFont(valueFont, 25 * scale, "OUTLINE") end
        if resize then
            resize:SetSize(18 * scale, 18 * scale)
            resize:ClearAllPoints()
            resize:SetPoint("BOTTOMRIGHT", layerPanel, "BOTTOMRIGHT", -2 * scale, 2 * scale)
        end
    end

    resize = CreateFrame("Button", nil, layerPanel)
    resize:SetSize(18, 18)
    resize:SetPoint("BOTTOMRIGHT", layerPanel, "BOTTOMRIGHT", -2, 2)
    resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resize:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resize:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or settings.layerPanelLocked == true then return end
        -- Resizing around TOPLEFT keeps the opposite corner stationary. The
        -- frame itself stays at scale 1 so WoW cannot scale its anchor offsets.
        local left, top = layerPanel:GetLeft(), layerPanel:GetTop()
        if left and top then
            layerPanel:ClearAllPoints()
            layerPanel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
        local x, y = GetCursorPosition()
        self.dragging, self.startX, self.startY = true, x, y
        self.startScale = layerPanel.displayScale or 1
    end)
    resize:SetScript("OnUpdate", function(self)
        if not self.dragging then return end
        local x, y = GetCursorPosition()
        local parentScale = UIParent:GetEffectiveScale() or 1
        local deltaX = (x - self.startX) / parentScale
        local deltaY = (self.startY - y) / parentScale
        local scaleDelta = (deltaX * LAYER_PANEL_WIDTH + deltaY * LAYER_PANEL_HEIGHT)
            / (LAYER_PANEL_WIDTH * LAYER_PANEL_WIDTH + LAYER_PANEL_HEIGHT * LAYER_PANEL_HEIGHT)
        applyPanelScale(self.startScale + scaleDelta)
    end)
    resize:SetScript("OnMouseUp", function(self)
        if not self.dragging then return end
        self.dragging = nil
        settings.layerPanelScale = math.floor((layerPanel.displayScale or 1) * 20 + 0.5) / 20
        applyPanelScale(settings.layerPanelScale)
        saveLayerPanelPosition()
    end)
    applyPanelScale(settings.layerPanelScale)
    layerPanel.resizeHandle = resize
    local function updateLockState()
        local locked = settings.layerPanelLocked == true
        resize:SetShown(not locked)
        if locked then resize.dragging = nil end
    end
    layerPanel:SetScript("OnDragStart", function(self)
        if settings.layerPanelLocked ~= true then self:StartMoving() end
    end)
    layerPanel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveLayerPanelPosition()
    end)
    layerPanel:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("iRC Current Layer")
        local layer = GuildMap:GetLocalLayer()
        if layer then
            GameTooltip:AddLine("Layer " .. tostring(layer.number), 0.30, 1, 0.35)
            GameTooltip:AddLine("Raw zone ID: " .. tostring(layer.zoneUID), 0.68, 0.68, 0.68)
            GameTooltip:AddLine("Detected from " .. tostring(layer.source or "nearby NPC") .. ".", 0.68, 0.68, 0.68)
        else
            GameTooltip:AddLine("Waiting for a nearby NPC observation.", 0.72, 0.72, 0.72, true)
        end
        GameTooltip:AddLine(" ")
        if settings.layerPanelLocked == true then
            GameTooltip:AddLine("Panel locked. Right-click to unlock it.", 1, 0.82, 0.35, true)
        else
            GameTooltip:AddLine("Drag the panel to move it or drag the corner to resize it.", 1, 0.82, 0.35, true)
            GameTooltip:AddLine("Right-click to lock the panel.", 1, 0.82, 0.35, true)
        end
        GameTooltip:AddLine("Visibility is controlled in Personal Settings.", 0.72, 0.72, 0.72, true)
        GameTooltip:Show()
    end)
    layerPanel:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    layerPanel:SetScript("OnMouseUp", function(_, button)
        if button ~= "RightButton" then return end
        settings.layerPanelLocked = settings.layerPanelLocked ~= true
        updateLockState()
        iRC:Print(settings.layerPanelLocked and "Layer panel locked." or "Layer panel unlocked.")
        if GameTooltip then GameTooltip:Hide() end
    end)
    updateLockState()
    layerPanel:ClearAllPoints()
    layerPanel:SetPoint(settings.layerPanelPoint or "TOP", UIParent,
        settings.layerPanelRelativePoint or settings.layerPanelPoint or "TOP",
        tonumber(settings.layerPanelX) or 0, tonumber(settings.layerPanelY) or -90)
end

function GuildMap:GetLocalLayer()
    if not localLayer then return nil end
    local now = GetTime and GetTime() or 0
    if now - (localLayer.seenAt or 0) > LOCAL_LAYER_LIFETIME then
        localLayer = nil
        return nil
    end
    local mapId = currentPlayerMapId()
    if mapId and localLayer.mapId ~= mapId then return nil end
    return localLayer
end

function GuildMap:UpdateLocalLayerDisplay()
    local layer = self:GetLocalLayer()
    if mapControls and mapControls.layerLabel then
        if layer then
            mapControls.layerLabel:SetText("Layer " .. tostring(layer.number) .. "  |cff888888(ID "
                .. tostring(layer.zoneUID) .. ", " .. tostring(layer.source or "observed") .. ")|r")
            mapControls.layerLabel:SetTextColor(0.30, 1, 0.35, 1)
        else
            mapControls.layerLabel:SetText("Current layer: waiting for a nearby NPC")
            mapControls.layerLabel:SetTextColor(0.72, 0.72, 0.72, 1)
        end
    end
    if layerPanel then
        layerPanel.value:SetText(layer and tostring(layer.number) or "--")
        layerPanel.value:SetTextColor(layer and 0.30 or 0.72, layer and 1 or 0.72,
            layer and 0.35 or 0.72)
        layerPanel:SetShown(iRC:GetSettings().showLayerPanel ~= false)
    end
end

function GuildMap:ObserveLocalLayer(unit, source)
    if type(unit) ~= "string" or not UnitGUID then return false end
    if iRC:GetSettings().showLayerPanel == false then return false end
    if iRC.IsForeverClient and not iRC:IsForeverClient() then return false end
    local guid = UnitGUID(unit)
    local zoneUID, serverId, instanceId, unitType = parseWorldLayerGuid(guid)
    if not zoneUID then return false end
    local mapId = currentPlayerMapId()
    if not mapId then return false end
    local changed = not localLayer or localLayer.zoneUID ~= zoneUID
        or localLayer.serverId ~= serverId or localLayer.instanceId ~= instanceId
        or localLayer.mapId ~= mapId
    localLayer = {
        zoneUID = zoneUID,
        number = getLayerNumber(zoneUID, serverId, instanceId),
        serverId = serverId,
        instanceId = instanceId,
        unitType = unitType,
        mapId = mapId,
        source = source or unit,
        seenAt = GetTime and GetTime() or 0,
    }
    if changed then
        iRC:DebugMsg("Local layer detected: zoneUID=" .. tostring(zoneUID)
            .. ", map=" .. tostring(mapId) .. ", source=" .. tostring(localLayer.source), 3)
        self:BroadcastLocalLayer(true)
    end
    self:UpdateLocalLayerDisplay()
    return true
end

function GuildMap:ClearLocalLayer()
    localLayer = nil
    self:UpdateLocalLayerDisplay()
end

function GuildMap:SetLayerPanelShown(enabledValue)
    iRC:GetSettings().showLayerPanel = enabledValue and true or false
    initializeLayerPanel()
    if enabledValue then
        self:ObserveLocalLayer("target", "target")
        self:ObserveLocalLayer("mouseover", "mouseover")
    end
    self:UpdateLocalLayerDisplay()
end

function GuildMap:ReceiveLayerState(parts, sender)
    if iRC:GetSettings().showLayerPanel == false then return false end
    if type(parts) ~= "table" or tostring(parts[2] or "") ~= "1" then return false end
    local zoneUID = tonumber(parts[3])
    local serverId = tonumber(parts[4])
    local instanceId = tonumber(parts[5])
    local mapId = tonumber(parts[6])
    if not zoneUID or zoneUID <= 0 or not serverId or serverId < 0
        or not instanceId or instanceId < 0 or not mapId or mapId <= 0 then return false end
    local scope = tostring(serverId) .. ":" .. tostring(instanceId)
    local ids = knownLayerIds[scope]
    if not ids then ids = {}; knownLayerIds[scope] = ids end
    local registryChanged = ids[zoneUID] ~= true
    ids[zoneUID] = true
    for rawId in tostring(parts[8] or ""):gmatch("%d+") do
        local knownId = tonumber(rawId)
        if knownId and knownId > 0 and not ids[knownId] then
            ids[knownId] = true
            registryChanged = true
        end
    end
    local number = getLayerNumber(zoneUID, serverId, instanceId)
    local senderKey = iRC:NormalizeName(sender)
    if senderKey ~= "" then
        layerUsers[senderKey] = {
            name = sender, zoneUID = zoneUID, number = number,
            serverId = serverId, instanceId = instanceId, mapId = mapId,
            seenAt = GetTime and GetTime() or 0,
        }
    end
    if localLayer and localLayer.serverId == serverId and localLayer.instanceId == instanceId then
        localLayer.number = getLayerNumber(localLayer.zoneUID, serverId, instanceId)
        self:UpdateLocalLayerDisplay()
        if registryChanged and C_Timer and C_Timer.After then
            C_Timer.After(1 + math.random() * 2, function() GuildMap:BroadcastLocalLayer(false) end)
        end
    end
    return true
end

function GuildMap:GetUserLayer(name)
    local entry = layerUsers[iRC:NormalizeName(name)]
    if not entry then return nil end
    local now = GetTime and GetTime() or 0
    if now - (entry.seenAt or 0) > LOCAL_LAYER_LIFETIME then
        layerUsers[iRC:NormalizeName(name)] = nil
        return nil
    end
    return entry
end

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
    mapControls:SetSize(280, 70)
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
    mapControls.layerLabel = mapControls:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mapControls.layerLabel:SetPoint("TOPRIGHT", showToggle, "BOTTOMRIGHT", 0, -3)
    mapControls.layerLabel:SetWidth(270)
    mapControls.layerLabel:SetJustifyH("RIGHT")
    mapControls.layerLabel:SetWordWrap(false)
    addLabelOutline(mapControls.layerLabel)
    local function updateToggle()
        local visible = enabled() and WorldMapFrame:IsShown()
        mapControls:SetShown(visible)
        toggle:SetShown(visible)
        toggle:SetChecked(iRC:GetSettings().shareGuildMapPosition ~= false)
        showToggle:SetShown(visible)
        showToggle:SetChecked(iRC:GetSettings().showGuildMap ~= false)
        GuildMap:UpdateLocalLayerDisplay()
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
        GuildMap:ObserveLocalLayer("target", "target")
        GuildMap:ObserveLocalLayer("mouseover", "mouseover")
        -- Incoming positions update pins immediately. This slower ticker
        -- expires stale pins and stale local layer observations while open.
        if not mapTicker and C_Timer and C_Timer.NewTicker then
            mapTicker = C_Timer.NewTicker(15, function()
                GuildMap:UpdatePins()
                GuildMap:UpdateLocalLayerDisplay()
            end)
        end
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
        GuildMap:ObserveLocalLayer("target", "target")
        GuildMap:ObserveLocalLayer("mouseover", "mouseover")
        if not mapTicker and C_Timer and C_Timer.NewTicker then
            mapTicker = C_Timer.NewTicker(15, function()
                GuildMap:UpdatePins()
                GuildMap:UpdateLocalLayerDisplay()
            end)
        end
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
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        if initialized then return end
        initialized = true
        initializeLayerPanel()
        GuildMap:UpdateLocalLayerDisplay()
        if not layerPanelTicker and C_Timer and C_Timer.NewTicker then
            layerPanelTicker = C_Timer.NewTicker(15, function()
                GuildMap:UpdateLocalLayerDisplay()
                GuildMap:BroadcastLocalLayer(false)
            end)
        end
        if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then armMapInitialization() end
        GuildMap:SchedulePosition(1.5, 0.5, true)
        scheduleNextPosition()
    elseif event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == "Blizzard_WorldMap" then armMapInitialization() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        GuildMap:ClearLocalLayer()
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        GuildMap:ClearLocalLayer()
        -- If the map is open, swap to already cached locations immediately;
        -- the outgoing live-position update remains separately throttled.
        GuildMap:UpdatePins(true)
        GuildMap:SchedulePosition(0.5, 0, true)
    elseif event == "PLAYER_TARGET_CHANGED" then
        GuildMap:ObserveLocalLayer("target", "target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        GuildMap:ObserveLocalLayer("mouseover", "mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        GuildMap:ObserveLocalLayer(unit, "nameplate")
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
