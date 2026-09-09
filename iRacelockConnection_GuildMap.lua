local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local GuildMap = { positions = {}, pins = {}, pool = {} }
iRC.GuildMap = GuildMap

local POSITION_VERSION = "1"
local POSITION_LIFETIME = 30
local initialized, mapInitialized, positionSendPending
local mapTicker

local function enabled()
    return iRC:IsGuildConnectionActive() and iRC:GetConnectionRules().guildMapEnabled == true
end

function GuildMap:IsVisible()
    return enabled() and iRC:GetSettings().showGuildMap ~= false
end

local function clearPin(name)
    local pin = GuildMap.pins[name]
    if not pin then return end
    pin:Hide()
    pin.playerName, pin.classFile, pin.level = nil, nil, nil
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
    for name, position in pairs(self.positions) do
        if now - (position.receivedAt or 0) > POSITION_LIFETIME then
            self.positions[name] = nil
            clearPin(name)
        end
    end
end

local function acquirePin(parent)
    local pin = table.remove(GuildMap.pool)
    if not pin then
        pin = CreateFrame("Frame", nil, parent)
        pin:SetSize(12, 12)
        pin:SetFrameStrata("HIGH")
        pin.border = pin:CreateTexture(nil, "BACKGROUND")
        pin.border:SetAllPoints()
        pin.border:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        pin.border:SetVertexColor(0, 0, 0, 0.85)
        pin.center = pin:CreateTexture(nil, "ARTWORK")
        pin.center:SetPoint("TOPLEFT", 1, -1)
        pin.center:SetPoint("BOTTOMRIGHT", -1, 1)
        pin.center:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        pin:EnableMouse(true)
        pin:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local shortName = tostring(self.playerName or "Unknown"):match("^[^-]+") or "Unknown"
            local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[self.classFile or ""]
            if color then GameTooltip:AddLine(shortName, color.r, color.g, color.b) else GameTooltip:AddLine(shortName) end
            GameTooltip:AddLine("Level " .. tostring(self.level or 0) .. " " .. tostring(self.className or self.classFile or "Unknown"), 0.65, 0.65, 0.65)
            GameTooltip:Show()
        end)
        pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    pin:SetParent(parent)
    pin:Show()
    return pin
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

function GuildMap:UpdatePins()
    self:Cleanup()
    if not WorldMapFrame or not WorldMapFrame:IsShown() or not self:IsVisible() then
        for name in pairs(self.pins) do clearPin(name) end
        return
    end
    local mapId = WorldMapFrame:GetMapID()
    local child = WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
    if not mapId or not child or child:GetWidth() <= 0 or child:GetHeight() <= 0 then return end
    local shown = {}
    for name, position in pairs(self.positions) do
        local x, y = mapPosition(position.mapId, position.x, position.y, mapId)
        if x and y then
            shown[name] = true
            local pin = self.pins[name] or acquirePin(child)
            self.pins[name] = pin
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", child, "TOPLEFT", x * child:GetWidth(), -y * child:GetHeight())
            local profile = iRC:FindConnectionProfile(name)
            local classFile = profile and profile.class or ""
            local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
            pin.center:SetVertexColor(color and color.r or 1, color and color.g or 1, color and color.b or 1, 1)
            pin.playerName, pin.classFile, pin.level = position.name or name, classFile, profile and profile.level or 0
            pin.className = classFile ~= "" and classFile:sub(1, 1) .. classFile:sub(2):lower() or "Unknown"
        end
    end
    for name in pairs(self.pins) do if not shown[name] then clearPin(name) end end
end

function GuildMap:BroadcastPosition()
    if not enabled() or iRC:GetSettings().shareGuildMapPosition == false or not C_Map then return false end
    local _, instanceType = GetInstanceInfo()
    if instanceType and instanceType ~= "none" then return false end
    local mapId = C_Map.GetBestMapForUnit("player")
    local position = mapId and C_Map.GetPlayerMapPosition(mapId, "player")
    if not position then return false end
    local x, y = position:GetXY()
    if not x or not y or (x == 0 and y == 0) then return false end
    local xWire, yWire = math.floor(x * 10000 + 0.5), math.floor(y * 10000 + 0.5)
    local message = table.concat({ "MAP_POS", POSITION_VERSION, tostring(mapId), tostring(xWire), tostring(yWire) }, "\t")
    return iRC:SendAddonTraffic(iRC.Prefix, message, "GUILD")
end

function GuildMap:SchedulePosition(maximumDelay, minimumDelay)
    if positionSendPending then return false end
    if not C_Timer or not C_Timer.After then return self:BroadcastPosition() end
    positionSendPending = true
    minimumDelay = math.max(0, tonumber(minimumDelay) or 0)
    maximumDelay = math.max(minimumDelay, tonumber(maximumDelay) or 3)
    C_Timer.After(minimumDelay + math.random() * (maximumDelay - minimumDelay), function()
        positionSendPending = false
        GuildMap:BroadcastPosition()
    end)
    return true
end

local function scheduleNextPosition()
    if not C_Timer or not C_Timer.After then return end
    C_Timer.After(10 + math.random() * 5, function()
        GuildMap:BroadcastPosition()
        GuildMap:Cleanup()
        scheduleNextPosition()
    end)
end

local function initializeMap()
    if mapInitialized or not WorldMapFrame or not WorldMapFrame.ScrollContainer then return end
    mapInitialized = true
    local toggle = CreateFrame("CheckButton", "iRCGuildMapToggle", WorldMapFrame, "UICheckButtonTemplate")
    toggle:SetSize(22, 22)
    -- Keep this below Blizzard's top-right controls. The map canvas renders
    -- above ordinary children, so retain WorldMapFrame as the anchor and put
    -- the control explicitly above the ScrollContainer.
    toggle:SetPoint("TOPRIGHT", WorldMapFrame, "TOPRIGHT", -60, -82)
    toggle:SetFrameLevel((WorldMapFrame.ScrollContainer:GetFrameLevel() or 0) + 20)
    toggle.label = toggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toggle.label:SetPoint("RIGHT", toggle, "LEFT", -2, 0)
    toggle.label:SetText("iRC: Share my Pos.")
    toggle:SetScript("OnClick", function(self)
        iRC:GetSettings().shareGuildMapPosition = self:GetChecked() and true or false
        if self:GetChecked() then GuildMap:SchedulePosition(1) end
        if iRC.RefreshOptionsIfShown then iRC:RefreshOptionsIfShown() end
    end)
    local function updateToggle()
        toggle:SetShown(enabled())
        toggle:SetChecked(iRC:GetSettings().shareGuildMapPosition ~= false)
    end
    GuildMap.UpdateToggle = updateToggle
    if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", function() GuildMap:UpdatePins() end) end
    WorldMapFrame.ScrollContainer:HookScript("OnMouseWheel", function() GuildMap:UpdatePins() end)
    WorldMapFrame:HookScript("OnShow", function()
        updateToggle()
        if not mapTicker and C_Timer and C_Timer.NewTicker then mapTicker = C_Timer.NewTicker(0.5, function() GuildMap:UpdatePins() end) end
        GuildMap:UpdatePins()
    end)
    WorldMapFrame:HookScript("OnHide", function()
        if mapTicker then mapTicker:Cancel(); mapTicker = nil end
        for name in pairs(GuildMap.pins) do clearPin(name) end
    end)
    updateToggle()
end

function GuildMap:SetShown(enabledValue)
    iRC:GetSettings().showGuildMap = enabledValue and true or false
    if self.UpdateToggle then self.UpdateToggle() end
    self:UpdatePins()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        if initialized then return end
        initialized = true
        initializeMap()
        GuildMap:SchedulePosition(8, 3)
        scheduleNextPosition()
    elseif event == "ADDON_LOADED" then
        initializeMap()
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        GuildMap:SchedulePosition(3)
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, _, sender = ...
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
