local _, private = ...
local iRC = private.iRC
local Feedback = {}
iRC.AdminFeedback = Feedback

-- Personal contact history belongs to this account, not a guild report.
-- Keep realms and server rulesets separate, while sharing it between admins.
local function getHistory(create)
    if not iRC:IsTestAdmin() then return nil end
    local scope = iRC:GetGuildDirectoryScope()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName and GetRealmName()
    if iRC:IsSecretValue(scope) or type(scope) ~= "string" or scope == ""
        or iRC:IsSecretValue(realm) or type(realm) ~= "string" or realm == "" then return nil end
    local root = iRCDB and iRCDB.adminFeedbackHistory
    if not root and create then
        root = {}
        iRCDB = iRCDB or {}
        iRCDB.adminFeedbackHistory = root
    end
    if not root then return nil end
    local key = realm:lower() .. ":" .. scope
    if not root[key] and create then root[key] = {} end
    return root[key]
end

function Feedback:GetEntry(name)
    if iRC:IsSecretValue(name) or type(name) ~= "string" then return nil end
    local history = getHistory(false)
    return history and history[iRC:FormatPlayerName(name):lower()] or nil
end

function Feedback:GetHistory()
    local rows = {}
    for _, entry in pairs(getHistory(false) or {}) do rows[#rows + 1] = entry end
    table.sort(rows, function(a, b)
        if a.lastSent ~= b.lastSent then return a.lastSent > b.lastSent end
        return a.name:lower() < b.name:lower()
    end)
    return rows
end

function Feedback:RecordSent(message, target)
    if not iRC:IsTestAdmin() or iRC:IsSecretValue(message) or iRC:IsSecretValue(target)
        or type(message) ~= "string" or type(target) ~= "string"
        or target == "" or #target > 128 or target:find("[%c|]") then return false end
    local expected = iRC.L.TEST_ADMIN_ONLINE_WHISPER_MESSAGE
    if message ~= expected then
        if not iRC.Roleplay or not iRC.Roleplay.TransformChatText
            or message ~= iRC.Roleplay:TransformChatText(expected) then return false end
    end
    local history = getHistory(true)
    if not history then return false end
    local key, timestamp = iRC:FormatPlayerName(target):lower(), time()
    if key == "" then return false end
    local entry = history[key]
    if not entry then
        entry = { name = iRC:FormatPlayerName(target), sends = {} }
        history[key] = entry
    end
    entry.sends[#entry.sends + 1] = { timestamp = timestamp, sender = iRC:GetPlayerName() }
    entry.lastSent, entry.count = timestamp, #entry.sends
    return true
end

-- Preparing or cancelling the draft never counts as sending it. This event
-- records the outgoing feedback whisper after chat reports it as sent.
local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
events:SetScript("OnEvent", function(_, _, message, target)
    Feedback:RecordSent(message, target)
end)
