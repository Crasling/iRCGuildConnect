local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

-- Friend discovery is requested by a layer lookup, never by a background
-- ticker. WoW checks the trusted friend's GUID before any caller may whisper.
local Peers = {}
iRC.LayerPeers = Peers

local MAX_CANDIDATES, MAX_PENDING = 3, 3
local TRUST_LIFETIME, OBSERVATION_LIFETIME = 30, 30
local RESULT_LIFETIME, REQUEST_TIMEOUT, TIMEOUT_COOLDOWN = 3, 2, 5
local trustedFriends, observations, results, pending, retryAt = {}, {}, {}, {}, {}
local pendingCount, responseEventReady = 0, false

local function secret(value)
    return iRC:IsSecretValue(value)
end

local function now()
    local value = GetTime and GetTime() or 0
    return not secret(value) and type(value) == "number" and value or 0
end

local function finiteNumber(value)
    return not secret(value) and type(value) == "number"
        and value == value and value > -math.huge and value < math.huge
end

local function nameKey(name)
    if secret(name) or type(name) ~= "string" or name == "" or #name > 128 then return nil end
    if iRC.IsForeverClient and iRC:IsForeverClient() then
        local key = iRC:NormalizeName(name)
        return key ~= "" and key or nil
    end
    -- A realm suffix identifies another player and must not be discarded.
    return name:match("^%s*(.-)%s*$"):lower()
end

local function validGuid(guid)
    return not secret(guid) and type(guid) == "string" and #guid <= 80
        and guid:match("^Player%-%w[%w%-]*$") ~= nil
end

local function call(callback, ...)
    if secret(callback) or type(callback) ~= "function" then return nil, false end
    local ok, value = pcall(callback, ...)
    if not ok or secret(value) then return nil, false end
    return value, true
end

local function notify(callback, allowed)
    if type(callback) == "function" then
        local ok, err = pcall(callback, allowed == true)
        if not ok and type(geterrorhandler) == "function" then
            local handler = geterrorhandler()
            if type(handler) == "function" then pcall(handler, err) end
        end
    end
end

local function combatBlocked()
    local blocked, readable = call(iRC.IsCombatTrafficBlocked, iRC)
    return not readable or blocked ~= false
end

local function trusted(key, guid, at)
    local friend = key and trustedFriends[key]
    return friend ~= nil and friend.guid == guid and at >= friend.checkedAt
        and at - friend.checkedAt <= TRUST_LIFETIME
end

local function finish(check, allowed, cacheLifetime)
    if pending[check.guid] ~= check then return end
    pending[check.guid], pendingCount = nil, math.max(0, pendingCount - 1)
    local at = now()
    for _, request in ipairs(check.callbacks) do
        local stillTrusted = trusted(request.key, check.guid, at) == true
        local accepted = allowed == true and stillTrusted
        if stillTrusted and cacheLifetime then
            results[request.key] = { guid = check.guid, allowed = accepted, expiresAt = at + cacheLifetime }
        end
        notify(request.callback, accepted)
    end
end

function Peers:GetCandidates(mapId, maximum)
    if not finiteNumber(mapId) or mapId <= 0 or combatBlocked() then return {} end
    if maximum ~= nil and not finiteNumber(maximum) then return {} end
    maximum = math.max(0, math.min(MAX_CANDIDATES, math.floor(maximum or MAX_CANDIDATES)))
    if maximum == 0 then return {} end
    local api = C_FriendList
    if secret(api) or type(api) ~= "table" then return {} end
    local count, readable = call(api.GetNumFriends)
    if not readable or not finiteNumber(count) or count < 0 then return {} end

    local zoneName
    if type(C_Map) == "table" and not secret(C_Map) then
        local info, found = call(C_Map.GetMapInfo, mapId)
        if found and type(info) == "table" and not secret(info.name) and type(info.name) == "string" then zoneName = info.name end
    end
    local ownKey = iRC.GetPlayerName and nameKey(iRC:GetPlayerName())
    local at, nextTrusted, candidates, seenGuids = now(), {}, {}, {}
    for index = 1, math.min(500, math.floor(count)) do
        local info, found = call(api.GetFriendInfoByIndex, index)
        if found and type(info) == "table" and not secret(info.connected) and info.connected == true
            and validGuid(info.guid) then
            local key = nameKey(info.name)
            if key and key ~= ownKey then
                nextTrusted[key] = { name = info.name, guid = info.guid, checkedAt = at }
                local grouped = iRC.GuildMap and iRC.GuildMap.IsLayerGroupMember
                    and iRC.GuildMap:IsLayerGroupMember(info.name)
                local guildMember = iRC.RaceGrid and iRC.RaceGrid.IsOwnGuildMember
                    and iRC.RaceGrid:IsOwnGuildMember(info.name)
                if not grouped and not guildMember and not seenGuids[info.guid] then
                    seenGuids[info.guid] = true
                    local observation = observations[key]
                    local recentlyObserved = observation and at >= observation.at
                        and at - observation.at <= OBSERVATION_LIFETIME and observation.mapId == mapId
                    local sameZone = zoneName and not secret(info.area) and info.area == zoneName
                    candidates[#candidates + 1] = { name = info.name, guid = info.guid,
                        priority = recentlyObserved and 0 or sameZone and 1 or 2, key = key }
                end
            end
        end
    end
    trustedFriends = nextTrusted
    for key in pairs(observations) do
        local observation = observations[key]
        if not nextTrusted[key] or at - observation.at > OBSERVATION_LIFETIME then observations[key] = nil end
    end
    for key, result in pairs(results) do
        if result.expiresAt <= at or not trusted(key, result.guid, at) then results[key] = nil end
    end
    for guid, expiresAt in pairs(retryAt) do if expiresAt <= at then retryAt[guid] = nil end end
    table.sort(candidates, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return a.key < b.key
    end)
    local chosen = {}
    for index = 1, math.min(maximum, #candidates) do
        chosen[index] = { name = candidates[index].name, guid = candidates[index].guid }
    end
    return chosen
end

function Peers:Observe(name, guid, serverId, mapId)
    local key, at = nameKey(name), now()
    if not key or not validGuid(guid) or not finiteNumber(serverId) or serverId < 0
        or not finiteNumber(mapId) or mapId <= 0 or not trusted(key, guid, at)
        or type(iRC.IsRecentAddonPeer) ~= "function" or not iRC:IsRecentAddonPeer(name) then return false end
    -- Received payloads can prioritize a friend, but cannot establish the
    -- friend's name/GUID association. Only the native friend list does that.
    observations[key] = { at = at, mapId = mapId, serverId = serverId }
    return true
end

function Peers:IsReady(name)
    local key, at = nameKey(name), now()
    local result = key and results[key]
    return result ~= nil and result.allowed == true and result.expiresAt > at
        and trusted(key, result.guid, at) == true
end

function Peers:IsKnownFriend(name)
    local key = nameKey(name)
    local friend = key and trustedFriends[key]
    if friend and now() - friend.checkedAt <= TRUST_LIFETIME then return true end
    if not key or combatBlocked() or secret(C_FriendList) or type(C_FriendList) ~= "table" then return false end
    local info, found = call(C_FriendList.GetFriendInfo, name)
    if found and type(info) == "table" and not secret(info.connected) and info.connected == true
        and nameKey(info.name) == key and validGuid(info.guid) then
        trustedFriends[key] = { name = info.name, guid = info.guid, checkedAt = now() }
        return true
    end
    return false
end

function Peers:Preflight(name, guid, callback)
    local key, at = nameKey(name), now()
    if not key or not validGuid(guid) or not trusted(key, guid, at) or combatBlocked() then
        notify(callback, false); return false
    end
    local result = results[key]
    if result and result.guid == guid and result.expiresAt > at then
        notify(callback, result.allowed); return result.allowed == true
    end
    local check = pending[guid]
    if check then
        if #check.callbacks >= 16 then notify(callback, false); return false end
        check.callbacks[#check.callbacks + 1] = { key = key, callback = callback }
        return true
    end
    local api = C_ChatInfo
    if not responseEventReady or secret(api) or type(api) ~= "table"
        or secret(api.RequestCanLocalWhisperTarget) or type(api.RequestCanLocalWhisperTarget) ~= "function"
        or not C_Timer or type(C_Timer.After) ~= "function" or pendingCount >= MAX_PENDING
        or retryAt[guid] and retryAt[guid] > at then
        notify(callback, false); return false
    end
    check = { guid = guid, callbacks = { { key = key, callback = callback } }, startedAt = at }
    pending[guid], pendingCount = check, pendingCount + 1
    local ok = pcall(api.RequestCanLocalWhisperTarget, guid)
    if not ok then finish(check, false, RESULT_LIFETIME); return false end
    if pending[guid] == check then
        C_Timer.After(REQUEST_TIMEOUT, function()
            if pending[guid] ~= check then return end
            retryAt[guid] = now() + TIMEOUT_COOLDOWN
            finish(check, false)
        end)
    end
    return true
end

local frame = CreateFrame("Frame")
local valid = true
if C_EventUtils and type(C_EventUtils.IsEventValid) == "function" then
    local value, readable = call(C_EventUtils.IsEventValid, "CAN_LOCAL_WHISPER_TARGET_RESPONSE")
    valid = readable and value == true
end
if valid then
    local ok, registered = pcall(frame.RegisterEvent, frame, "CAN_LOCAL_WHISPER_TARGET_RESPONSE")
    responseEventReady = ok and registered ~= false
end
frame:RegisterEvent("FRIENDLIST_UPDATE")
frame:SetScript("OnEvent", function(_, event, guid, status)
    if event == "FRIENDLIST_UPDATE" then
        trustedFriends, observations, results, retryAt = {}, {}, {}, {}
        local abandoned = pending
        pending, pendingCount = {}, 0
        for _, check in pairs(abandoned) do
            for _, request in ipairs(check.callbacks) do notify(request.callback, false) end
        end
        return
    end
    if event ~= "CAN_LOCAL_WHISPER_TARGET_RESPONSE" or not validGuid(guid) or secret(status) then return end
    local check = pending[guid]
    if not check then return end
    local values = Enum and Enum.ChatWhisperTargetStatus or {}
    if status == (values.CanWhisper or 0) or status == (values.CanWhisperGuild or 1) then
        finish(check, true, RESULT_LIFETIME)
    else
        finish(check, false, RESULT_LIFETIME)
    end
end)
