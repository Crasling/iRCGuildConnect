local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local Compatibility = {}
iRC.Compatibility = Compatibility

-- Compatibility is deliberately limited to RaceLocked presence. iRC answers
-- RLAddon probes with its current Self-Found state and accepts fresh RLAddon
-- replies as proof that a guild member is using RaceLocked instead of iRC.
local PREFIX = "RLAddon"
local SOURCE = "RaceLockedForkEU"

local function registerPrefix(prefix)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then return C_ChatInfo.RegisterAddonMessagePrefix(prefix) end
    if RegisterAddonMessagePrefix then return RegisterAddonMessagePrefix(prefix) end
end

local function send(message)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then return C_ChatInfo.SendAddonMessage(PREFIX, message, "GUILD") end
    if SendAddonMessage then return SendAddonMessage(PREFIX, message, "GUILD") end
end

function Compatibility:StoreSelfFound(name, selfFound, source)
    if not name or not iRC:IsGuildConnectionActive() then return end
    local connection = iRC:GetConnection()
    connection.compatibilityMembers = connection.compatibilityMembers or {}
    local key = iRC:NormalizeName(name)
    local member = connection.compatibilityMembers[key] or { name = name }
    member.name = member.name or name
    member.selfFound = selfFound == true
    member.selfFoundLastSeen = time()
    member.presence = { source = source or SOURCE, lastSeen = member.selfFoundLastSeen }
    member.guildFound = nil
    connection.compatibilityMembers[key] = member
    if iRC.ConnectionDashboard then iRC.ConnectionDashboard:RefreshIfShown() end
end

function iRC:GetCompatibilityMember(name)
    if not self:IsGuildConnectionActive() then return nil end
    local connection = self:GetConnection()
    return connection and connection.compatibilityMembers and connection.compatibilityMembers[self:NormalizeName(name)] or nil
end

function Compatibility:BroadcastSelfFound(messageType)
    if not iRC:IsGuildConnectionActive() then return false end
    local sent = send((messageType or "PING") .. "," .. (iRC:GetSelfFoundState() and "1" or "0"))
    self:StoreSelfFound(iRC:GetPlayerName(), iRC:GetSelfFoundState(), "iRC")
    return sent ~= false
end

function Compatibility:BroadcastAll()
    return self:BroadcastSelfFound("PING")
end

function Compatibility:RequestPresenceCheck()
    if not iRC:IsGuildConnectionActive() then return false end
    if not ((C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage) then return false end
    return self:BroadcastSelfFound("PING")
end

local function handleSelfFound(message, sender)
    if iRC:NormalizeName(sender) == iRC:NormalizeName(iRC:GetPlayerName()) then return end
    if not iRC:IsGuildMemberName(sender) then return end
    local messageType, value = tostring(message or ""):match("^([^,]+),([01])$")
    if messageType ~= "PING" and messageType ~= "PONG" then return end
    Compatibility:StoreSelfFound(sender, value == "1", SOURCE)
    if messageType == "PING" then Compatibility:BroadcastSelfFound("PONG") end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... == iRC.Name then registerPrefix(PREFIX) end
    elseif event == "PLAYER_LOGIN" then
        if C_Timer and C_Timer.After then C_Timer.After(6, function() Compatibility:BroadcastAll() end) end
        if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(60, function() Compatibility:BroadcastAll() end) end
    elseif event == "CHAT_MSG_ADDON" then
        if not iRC:IsGuildConnectionActive() then return end
        local prefix, message, _, sender = ...
        if prefix == PREFIX then handleSelfFound(message, sender) end
    end
end)
