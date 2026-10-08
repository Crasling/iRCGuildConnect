local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local Identity = {}
iRC.Identity = Identity
local warnedTogether = {}
local rosterRetryScheduled
local lastHistoryRequestAt = 0
local historyResponseAt = {}
local historyResponseQueue, historyResponseHead, historyResponseTail = {}, 1, 0
local historyResponseScheduled = false
local IDENTITY_WIRE_VERSION = "2"
local LINK_REQUEST_LIFETIME = 7 * 86400
local MAX_LINK_REQUESTS = 50
local MAX_GUILD_LOG_ENTRIES = 500
local MAX_SHARED_HISTORY = 50
local HISTORY_REQUEST_COOLDOWN = 60
local HISTORY_RESPONSE_COOLDOWN = 60
local MAX_HISTORY_RESPONSE_WORK = 200
local initializedGuildLogStores = setmetatable({}, { __mode = "k" })
local shownLinkRequests = {}
local lastLinkRelayAt = 0
local SYNCED_EVENT_TYPES = {
    JOIN = true, REJOIN = true, LEAVE = true, PROMOTE = true, DEMOTE = true,
    LEVEL = true, NAME = true, NOTE = true, OFFICER_NOTE = true, RETURN = true,
}

local function cleanWireText(value, limit)
    return tostring(value or ""):gsub("[%c]", " "):gsub("%s+", " "):sub(1, limit or 80)
end

local function eventFingerprint(eventType, name, text, occurredAt)
    -- Several clients can observe one roster event at slightly different
    -- times. Five-second buckets give those observations the same stable ID.
    local timeBucket = math.floor((tonumber(occurredAt) or 0) / 5)
    local value = table.concat({
        tostring(eventType),
        iRC:NormalizeName(name),
        tostring(text),
        timeBucket,
    }, "|")
    local hash = 5381
    for index = 1, #value do hash = (hash * 33 + value:byte(index)) % 4294967291 end
    return string.format("%08x", hash)
end

local function guildStore(create)
    local guildKey = iRC:GetGuildKey()
    if not guildKey then return nil end
    iRCDB = type(iRCDB) == "table" and iRCDB or {}
    iRCDB.identityGuilds = type(iRCDB.identityGuilds) == "table" and iRCDB.identityGuilds or {}
    local store = iRCDB.identityGuilds[guildKey]
    if not store and create then
        store = { characters = {}, personalBanks = {}, formerMembers = {}, roster = {}, guildLog = {}, memberHistory = {} }
        iRCDB.identityGuilds[guildKey] = store
    end
    if store then
        -- SavedVariables can contain partially written or older records. Make
        -- each collection safe before any caller reads or modifies the store.
        store.characters = type(store.characters) == "table" and store.characters or {}
        store.personalBanks = type(store.personalBanks) == "table" and store.personalBanks or {}
        store.formerMembers = type(store.formerMembers) == "table" and store.formerMembers or {}
        store.roster = type(store.roster) == "table" and store.roster or {}
        store.guildLog = type(store.guildLog) == "table" and store.guildLog or {}
        store.guildLogIds = type(store.guildLogIds) == "table" and store.guildLogIds or {}
        if not initializedGuildLogStores[store] then
            for _, record in ipairs(store.guildLog) do
                record.id = record.id or eventFingerprint(record.eventType, record.name, record.text, record.occurredAt)
                store.guildLogIds[record.id] = true
            end
            initializedGuildLogStores[store] = true
        end
        store.memberHistory = type(store.memberHistory) == "table" and store.memberHistory or {}
        store.identityAssignments = type(store.identityAssignments) == "table" and store.identityAssignments or {}
        store.identityLinkRequests = type(store.identityLinkRequests) == "table" and store.identityLinkRequests or {}
        store.identityMemberUpdatedAt = type(store.identityMemberUpdatedAt) == "table" and store.identityMemberUpdatedAt or {}
        store.confirmedCharacters = type(store.confirmedCharacters) == "table" and store.confirmedCharacters or {}
        store.excludedCharacters = type(store.excludedCharacters) == "table" and store.excludedCharacters or {}
        store.missingCounts = type(store.missingCounts) == "table" and store.missingCounts or {}
    end
    return store
end

local function characterKey(name)
    return iRC:NormalizeName(name)
end

local function refreshCurrentRoleState(name)
    if characterKey(name) ~= characterKey(iRC:GetPlayerName()) then return end
    -- Identity roles affect progression enforcement immediately. Refresh the
    -- local restrictions and publish the resulting Guild-Found state through
    -- the normal throttled traffic path without waiting for another game event.
    if iRC.Enforcement and iRC.Enforcement.Refresh then
        iRC.Enforcement:Refresh()
    elseif iRC.RaceLockedSync and iRC.RaceLockedSync.RefreshMoneyMonitoring then
        iRC.RaceLockedSync:RefreshMoneyMonitoring()
    end
    if iRC.RaceLockedSync and iRC.RaceLockedSync.Broadcast then
        iRC.RaceLockedSync:Broadcast()
    end
end

local function trimGuildLog(store)
    while #store.guildLog > MAX_GUILD_LOG_ENTRIES do
        local removed = table.remove(store.guildLog, 1)
        if removed and removed.id then store.guildLogIds[removed.id] = nil end
    end
end

function Identity:GetStore()
    return guildStore(true)
end

function Identity:RegisterCharacter(name, requestedRole, automatic)
    local store = guildStore(true)
    local key = characterKey(name)
    if not store or not key or key == "" then return false end
    local currentKey = characterKey(iRC:GetPlayerName())
    if automatic and key == currentKey and store.excludedCharacters[key] then
        self:BroadcastIdentityRemoval()
        return false
    end
    if not automatic then store.excludedCharacters[key] = nil end
    local canAutoConfirm = true
    if key == currentKey and store.main and store.main ~= key then
        local savedMainName = store.characters[store.main]
        if not savedMainName or not iRC:IsGuildMemberName(savedMainName) then
            -- Account-wide data proves the account relationship, but identity
            -- groups are guild-scoped. Do not inherit a Main outside this guild.
            canAutoConfirm = false
        end
    end
    store.characters[key] = iRC:FormatPlayerName(name)
    if key == currentKey then store.confirmedCharacters[key] = canAutoConfirm and true or nil end
    if not store.main or not store.characters[store.main] then store.main = key end
    if key ~= currentKey then
        -- Adding an Alt or changing its role must be confirmed by that
        -- character before the new identity is trusted guild-wide.
        store.confirmedCharacters[key] = nil
        self:RequestCharacterLink(name, store.characters[store.main], requestedRole)
    end
    self:BroadcastPersonalIdentity()
    if store.confirmedCharacters[key] == true then refreshCurrentRoleState(name) end
    return true
end

function Identity:RemoveCharacter(name)
    local store, key = guildStore(false), characterKey(name)
    if not store or not key or not store.characters[key] then return false end
    local mainName = store.main and store.characters[store.main]
    if key == characterKey(iRC:GetPlayerName()) then
        self:BroadcastIdentityRemoval()
    elseif mainName then
        self:RequestCharacterLink(name, mainName, "REMOVE")
    end
    store.characters[key] = nil
    store.personalBanks[key] = nil
    store.confirmedCharacters[key] = nil
    store.excludedCharacters[key] = true
    if store.main == key then
        store.main = next(store.characters)
    end
    self:BroadcastPersonalIdentity()
    refreshCurrentRoleState(name)
    return true
end

function Identity:IsPersonalBank(name)
    local store, key = guildStore(false), characterKey(name)
    local assignment = store and store.identityAssignments[key]
    if assignment and assignment.role == "BANK" then return true end
    if store and key and store.characters[key] ~= nil and store.personalBanks[key] == true
        and store.confirmedCharacters[key] == true then return true end
    return false
end

function Identity:SetPersonalBank(name, enabled)
    local store, key = guildStore(true), characterKey(name)
    if not store or not key or not store.characters[key] then return false end
    if enabled then
        store.personalBanks[key] = true
        if store.main == key then
            store.main = nil
            for candidate in pairs(store.characters) do
                if candidate ~= key then
                    store.main = candidate
                    break
                end
            end
        end
    else
        store.personalBanks[key] = nil
    end
    self:BroadcastPersonalIdentity()
    if store.confirmedCharacters[key] == true then refreshCurrentRoleState(name) end
    return true
end

function Identity:IsPersonalCharacter(name)
    local store, key = guildStore(false), characterKey(name)
    return store and key and store.characters[key] ~= nil or false
end

function Identity:IsAlt(name)
    local store, key = guildStore(false), characterKey(name)
    if not store or not key then return false end
    if store.characters[key] then return store.main ~= key end
    local assignment = store.identityAssignments[key]
    return assignment ~= nil and assignment.mainKey ~= key
        and (assignment.role == "ALT" or assignment.role == "BANK")
end

function Identity:SetMain(name)
    local store, key = guildStore(true), characterKey(name)
    if not store or not key or not store.characters[key] then return false end
    store.main = key
    store.personalBanks[key] = nil
    self:BroadcastPersonalIdentity()
    if store.confirmedCharacters[key] == true then refreshCurrentRoleState(name) end
    return true
end

function Identity:GetMainName()
    local store = guildStore(false)
    return store and store.main and store.characters[store.main] or nil
end

function Identity:GetCharacters()
    local store, result = guildStore(false), {}
    for key, name in pairs(store and store.characters or {}) do
        result[#result + 1] = { key = key, name = name, personalBank = store.personalBanks[key] == true }
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

function Identity:GetIdentityLabel(name)
    local store, key = guildStore(false), characterKey(name)
    if not store or not key then return nil end
    if store.characters[key] then
        if store.confirmedCharacters[key] ~= true then
            return (store.personalBanks[key] and "Pending Personal Bank Alt of " or "Pending Alt of ")
                .. (store.characters[store.main] or "unknown")
        end
        if store.main == key then return "Main" end
        if store.personalBanks[key] then return "Personal Bank Alt of " .. (store.characters[store.main] or "unknown") end
        return "Alt of " .. (store.characters[store.main] or "unknown")
    end
    local assignment = store.identityAssignments[key]
    if assignment then
        if assignment.mainKey == key then return "Main" end
        if assignment.role == "BANK" then return "Personal Bank Alt of " .. assignment.mainName end
        return "Alt of " .. assignment.mainName
    end
    for _, linked in pairs(store.identityAssignments) do
        if linked.mainKey == key then return "Main" end
    end
end

function Identity:GetManagedAssignment(name)
    local store, key = guildStore(false), characterKey(name)
    return store and key and store.identityAssignments[key] or nil
end

function Identity:GetLinkedCharacters(name)
    local store, key, result = guildStore(false), characterKey(name), {}
    if not store or not key then return result end
    local characters = store.characters[key] and store.characters or nil
    if not characters then
        local assignment = store.identityAssignments[key]
        local mainKey = assignment and assignment.mainKey or key
        characters = {}
        for assignedKey, linked in pairs(store.identityAssignments) do
            if linked.mainKey == mainKey then
                characters[assignedKey] = linked.name
                characters[mainKey] = linked.mainName
            end
        end
    end
    for _, characterName in pairs(characters or {}) do result[#result + 1] = characterName end
    table.sort(result)
    return result
end

local function applyManagedAssignment(store, memberName, mainName, role, updatedAt, source)
    local memberKey = characterKey(memberName)
    if not store or not memberKey then return false end
    local current = store.identityAssignments[memberKey]
    if current and (tonumber(current.updatedAt) or 0) >= updatedAt then return false end
    if role == "REMOVE" then
        store.identityAssignments[memberKey] = nil
    else
        local mainKey = characterKey(mainName)
        if not mainKey or mainKey == memberKey then return false end
        store.identityAssignments[memberKey] = {
            name = iRC:FormatPlayerName(memberName), mainKey = mainKey,
            mainName = iRC:FormatPlayerName(mainName), role = role,
            updatedAt = updatedAt, source = iRC:FormatPlayerName(source), managed = true,
        }
    end
    for id, request in pairs(store.identityLinkRequests) do
        if characterKey(request.target) == memberKey then store.identityLinkRequests[id] = nil end
    end
    if iRC.MainUI then iRC.MainUI:RefreshIfShown() end
    if iRC.ConnectionDashboard then iRC.ConnectionDashboard:RefreshIfShown() end
    return true
end

function Identity:AssignGuildCharacter(memberName, mainName, role)
    if not iRC:IsGuildConnectionActive() or not iRC:HasGuildPermission("identity") then return false end
    role = role == "BANK" and "BANK" or (role == "REMOVE" and "REMOVE" or "ALT")
    memberName = iRC:FormatPlayerName(memberName)
    mainName = role == "REMOVE" and "" or iRC:FormatPlayerName(mainName)
    if not iRC:IsGuildMemberName(memberName)
        or role ~= "REMOVE" and (not iRC:IsGuildMemberName(mainName)
            or characterKey(memberName) == characterKey(mainName)) then return false end
    local store = guildStore(true)
    local memberKey = characterKey(memberName)
    local updatedAt = math.max(time(), (tonumber(store.identityMemberUpdatedAt[memberKey]) or 0) + 1)
    store.identityMemberUpdatedAt[memberKey] = updatedAt
    local applied = applyManagedAssignment(store, memberName, mainName, role, updatedAt, iRC:GetPlayerName())
    if not applied and role ~= "REMOVE" then return false end
    local payload = table.concat({ "IDENT_ADMIN_MEMBER", IDENTITY_WIRE_VERSION, tostring(updatedAt),
        cleanWireText(memberName, 80), cleanWireText(mainName, 80), role }, "\t")
    iRC:SendAddonTraffic(iRC.Prefix, payload, "GUILD")
    return true
end

function Identity:GetFormerMembers()
    local store, result = guildStore(false), {}
    for _, record in pairs(store and store.formerMembers or {}) do result[#result + 1] = record end
    table.sort(result, function(a, b) return (a.departedAt or 0) > (b.departedAt or 0) end)
    return result
end

local function addGuildLog(store, eventType, name, text, classFile)
    local log = store and store.guildLog
    if not log then return end
    local record = {
        occurredAt = time(),
        eventType = eventType,
        name = iRC:FormatPlayerName(name or ""),
        text = text,
        classFile = classFile,
    }
    record.id = eventFingerprint(record.eventType, record.name, record.text, record.occurredAt)
    log[#log + 1] = record
    store.guildLogIds[record.id] = true
    trimGuildLog(store)
    if Identity.BroadcastGuildLog then Identity:BroadcastGuildLog(record) end
end

function Identity:GetGuildLog()
    local store, result = guildStore(false), {}
    for index = #(store and store.guildLog or {}), 1, -1 do
        result[#result + 1] = store.guildLog[index]
    end
    return result
end

function Identity:GetMemberHistory(name)
    local store, key = guildStore(false), characterKey(name)
    return store and key and store.memberHistory[key] or nil
end

function Identity:GetMemberActivity(name, limit)
    local key, result = characterKey(name), {}
    if not key then return result end
    for _, record in ipairs(self:GetGuildLog()) do
        if characterKey(record.name) == key then
            result[#result + 1] = record
            if #result >= (tonumber(limit) or 8) then break end
        end
    end
    return result
end

function Identity:BroadcastGuildLog(record, targetName)
    if not record or not iRC:IsGuildConnectionActive() or not iRC:HasGuildPermission("rosterHistory") then return false end
    local payload = table.concat({
        "IDENT_EVENT", IDENTITY_WIRE_VERSION,
        cleanWireText(record.id or eventFingerprint(record.eventType, record.name, record.text, record.occurredAt), 12),
        tostring(math.floor(tonumber(record.occurredAt) or time())),
        cleanWireText(record.eventType, 18), cleanWireText(record.name, 80), cleanWireText(record.classFile, 12),
        cleanWireText(record.text, 100),
    }, "\t")
    return iRC:SendAddonTraffic(iRC.Prefix, payload, targetName and "WHISPER" or "GUILD", targetName)
end

function Identity:RequestGuildHistory()
    if not iRC:IsGuildConnectionActive()
        or time() - lastHistoryRequestAt < HISTORY_REQUEST_COOLDOWN then
        return false
    end
    lastHistoryRequestAt = time()
    return iRC:SendAddonTraffic(iRC.Prefix, table.concat({ "IDENT_REQUEST", IDENTITY_WIRE_VERSION }, "\t"), "GUILD")
end

local function processHistoryResponse()
    local work = historyResponseQueue[historyResponseHead]
    historyResponseQueue[historyResponseHead] = nil
    historyResponseHead = historyResponseHead + 1
    -- A delayed response is no longer useful after its requester leaves the
    -- guild, and skipping it also avoids needless whisper traffic.
    if work and iRC:IsGuildMemberName(work.target) then
        Identity:BroadcastGuildLog(work.record, work.target)
    end
    if historyResponseHead <= historyResponseTail and C_Timer and C_Timer.After then
        C_Timer.After(0.10, processHistoryResponse)
    else
        historyResponseQueue, historyResponseHead, historyResponseTail = {}, 1, 0
        historyResponseScheduled = false
    end
end

local function queueHistoryResponse(record, target)
    if historyResponseTail - historyResponseHead + 1 >= MAX_HISTORY_RESPONSE_WORK then return false end
    historyResponseTail = historyResponseTail + 1
    historyResponseQueue[historyResponseTail] = { record = record, target = target }
    if not historyResponseScheduled then
        historyResponseScheduled = true
        if C_Timer and C_Timer.After then C_Timer.After(0.10, processHistoryResponse) else processHistoryResponse() end
    end
    return true
end

local function linkRequestId(requester, target, mainName, role, createdAt)
    return eventFingerprint("LINK", requester .. ">" .. target, mainName .. ">" .. role, createdAt)
end

function Identity:RequestCharacterLink(targetName, mainName, role)
    local store = guildStore(true)
    local requester = iRC:FormatPlayerName(iRC:GetPlayerName())
    targetName, mainName = iRC:FormatPlayerName(targetName), iRC:FormatPlayerName(mainName)
    if not store or characterKey(targetName) == characterKey(requester)
        or not iRC:IsGuildMemberName(targetName) or not iRC:IsGuildMemberName(mainName) then return false end
    role = role == "BANK" and "BANK" or (role == "REMOVE" and "REMOVE" or "ALT")
    local createdAt, expiresAt = time(), time() + LINK_REQUEST_LIFETIME
    local id = linkRequestId(requester, targetName, mainName, role, createdAt)
    store.identityLinkRequests[id] = { id = id, requester = requester, target = targetName,
        mainName = mainName, role = role, createdAt = createdAt, expiresAt = expiresAt }
    local payload = table.concat({ "IDENT_LINK_REQUEST", IDENTITY_WIRE_VERSION, id, createdAt, expiresAt,
        cleanWireText(requester, 80), cleanWireText(targetName, 80), cleanWireText(mainName, 80), role }, "\t")
    return iRC:SendAddonTraffic(iRC.Prefix, payload, "GUILD")
end

function Identity:ConfirmCurrentCharacterForMain(mainName)
    local store = guildStore(true)
    local currentName, currentKey = iRC:FormatPlayerName(iRC:GetPlayerName()), characterKey(iRC:GetPlayerName())
    mainName = iRC:FormatPlayerName(mainName)
    local mainKey = characterKey(mainName)
    if not store or not currentKey or not mainKey or not iRC:IsGuildMemberName(mainName) then return false end
    store.characters[currentKey] = currentName
    store.characters[mainKey] = mainName
    store.excludedCharacters[currentKey] = nil
    store.confirmedCharacters[currentKey] = true
    store.main = mainKey
    store.personalBanks[currentKey] = nil
    return self:BroadcastPersonalIdentity()
end

function Identity:AcceptLinkRequest(request)
    if not request or characterKey(request.target) ~= characterKey(iRC:GetPlayerName()) then return false end
    local store = guildStore(true)
    store.identityLinkRequests[request.id] = nil
    if request.role == "REMOVE" then
        local currentKey = characterKey(iRC:GetPlayerName())
        local removed = self:BroadcastIdentityRemoval()
        store.characters[currentKey], store.personalBanks[currentKey], store.confirmedCharacters[currentKey] = nil, nil, nil
        store.excludedCharacters[currentKey] = true
        return removed
    end
    local accepted = self:ConfirmCurrentCharacterForMain(request.mainName)
    if accepted and request.role == "BANK" then
        local store, currentKey = guildStore(true), characterKey(iRC:GetPlayerName())
        store.personalBanks[currentKey] = true
        accepted = self:BroadcastPersonalIdentity()
        refreshCurrentRoleState(iRC:GetPlayerName())
    end
    return accepted
end

function Identity:DeclineLinkRequest(request)
    if not request or characterKey(request.target) ~= characterKey(iRC:GetPlayerName()) then return false end
    local store = guildStore(true)
    store.identityLinkRequests[request.id] = nil
    return iRC:SendAddonTraffic(iRC.Prefix, table.concat({ "IDENT_LINK_DECLINE", IDENTITY_WIRE_VERSION,
        cleanWireText(request.id, 12), cleanWireText(request.target, 80) }, "\t"), "GUILD")
end

local function showLinkRequest(request)
    if characterKey(request.target) ~= characterKey(iRC:GetPlayerName()) then return end
    if shownLinkRequests[request.id] then return end
    shownLinkRequests[request.id] = true
    if StaticPopupDialogs and StaticPopup_Show then
        StaticPopupDialogs.IRC_IDENTITY_LINK_REQUEST = StaticPopupDialogs.IRC_IDENTITY_LINK_REQUEST or {
            text = "%s sent this character identity request: %s. Accept?",
            button1 = ACCEPT or "Accept", button2 = DECLINE or "Decline", timeout = 0, whileDead = true, hideOnEscape = true,
            preferredIndex = 3,
            OnAccept = function(_, data) Identity:AcceptLinkRequest(data) end,
            OnCancel = function(_, data) Identity:DeclineLinkRequest(data) end,
        }
        local destination = request.role == "REMOVE" and ("an unlink request from " .. request.mainName)
            or request.mainName .. (request.role == "BANK" and " as a Personal Bank Alt" or " as an Alt")
        StaticPopup_Show("IRC_IDENTITY_LINK_REQUEST", request.requester, destination, request)
    else
        iRC:Print(request.requester .. " requested an Alt link to " .. request.mainName
            .. ". Right-click that Main in Guild Members and choose Set as my Main to confirm it.")
    end
end

function Identity:RelayPendingLinkRequests()
    local store, now = guildStore(false), time()
    if not store then return end
    local kept, expiredOwnTargets = 0, {}
    for id, request in pairs(store.identityLinkRequests) do
        local expired = (tonumber(request.expiresAt) or 0) <= now or kept >= MAX_LINK_REQUESTS
        if expired then
            local targetKey = characterKey(request.target)
            if characterKey(request.requester) == characterKey(iRC:GetPlayerName()) then expiredOwnTargets[targetKey] = true end
            store.identityLinkRequests[id] = nil
        else
            kept = kept + 1
        end
    end
    for targetKey in pairs(expiredOwnTargets) do
        local stillPending = false
        for _, request in pairs(store.identityLinkRequests) do
            if characterKey(request.target) == targetKey then stillPending = true; break end
        end
        if not stillPending and store.confirmedCharacters[targetKey] ~= true then
            store.characters[targetKey], store.personalBanks[targetKey] = nil, nil
        end
    end
    -- One elected guild client performs asynchronous delivery. Every client
    -- may cache requests, so relay ownership can safely change later.
    if not iRC:IsRulesetBroadcaster() then return end
    local online = {}
    for _, member in ipairs(iRC:GetGuildRosterSnapshot()) do
        if member.online then online[characterKey(member.name)] = true end
    end
    for id, request in pairs(store.identityLinkRequests) do
        if online[characterKey(request.target)] then
            local payload = table.concat({ "IDENT_LINK_REQUEST", IDENTITY_WIRE_VERSION, id,
                request.createdAt, request.expiresAt, cleanWireText(request.requester, 80),
                    cleanWireText(request.target, 80), cleanWireText(request.mainName, 80), request.role or "ALT" }, "\t")
            iRC:SendAddonTraffic(iRC.Prefix, payload, "WHISPER", request.target)
        end
    end
end

function Identity:BroadcastIdentityRemoval(targetName)
    local store = guildStore(true)
    if not store or not iRC:IsGuildConnectionActive() then return false end
    local ownName, ownKey = iRC:FormatPlayerName(iRC:GetPlayerName()), characterKey(iRC:GetPlayerName())
    for id, request in pairs(store.identityLinkRequests) do
        if characterKey(request.target) == ownKey then store.identityLinkRequests[id] = nil end
    end
    local updatedAt = math.max(time(), (tonumber(store.identityMemberUpdatedAt[ownKey]) or 0) + 1)
    store.identityMemberUpdatedAt[ownKey] = updatedAt
    local payload = table.concat({ "IDENT_MEMBER", IDENTITY_WIRE_VERSION, tostring(updatedAt),
        cleanWireText(ownName, 80), "", "REMOVE" }, "\t")
    return iRC:SendAddonTraffic(iRC.Prefix, payload, targetName and "WHISPER" or "GUILD", targetName)
end

function Identity:BroadcastPersonalIdentity(targetName, preserveTimestamp)
    local store = guildStore(false)
    if not store or not store.main or not store.characters[store.main] or not iRC:IsGuildConnectionActive() then return false end
    local ownName, ownKey = iRC:FormatPlayerName(iRC:GetPlayerName()), characterKey(iRC:GetPlayerName())
    if not store.characters[ownKey] then return false end
    if ownKey ~= store.main and not iRC:IsGuildMemberName(store.characters[store.main]) then return false end
    for id, request in pairs(store.identityLinkRequests) do
        if characterKey(request.target) == ownKey then store.identityLinkRequests[id] = nil end
    end
    local updatedAt = math.max(time(), (tonumber(store.identityMemberUpdatedAt[ownKey]) or 0) + 1)
    store.identityMemberUpdatedAt[ownKey] = updatedAt
    local role = ownKey == store.main and "MAIN" or (store.personalBanks[ownKey] and "BANK" or "ALT")
    local payload = table.concat({ "IDENT_MEMBER", IDENTITY_WIRE_VERSION, tostring(updatedAt),
        cleanWireText(ownName, 80), cleanWireText(store.characters[store.main], 80), role }, "\t")
    return iRC:SendAddonTraffic(iRC.Prefix, payload, targetName and "WHISPER" or "GUILD", targetName)
end

function Identity:ReceiveSync(parts, sender)
    if parts[2] ~= IDENTITY_WIRE_VERSION then return false end
    local senderRank = iRC:GetGuildMemberRankIndex(sender)
    if parts[1] == "IDENT_ADMIN_MEMBER" then
        local timestamp = tonumber(parts[3])
        local memberName, mainName, role = cleanWireText(parts[4], 80), cleanWireText(parts[5], 80), parts[6]
        local now = time()
        local senderAuthorized = iRC:GuildMemberHasPermission(sender, "identity")
        if not senderAuthorized or not timestamp
            or timestamp > now + 300 or timestamp < now - 180 * 86400
            or (role ~= "ALT" and role ~= "BANK" and role ~= "REMOVE")
            or not iRC:IsGuildMemberName(memberName)
            or role ~= "REMOVE" and (not iRC:IsGuildMemberName(mainName)
                or characterKey(memberName) == characterKey(mainName)) then return false end
        local store = guildStore(true)
        store.identityMemberUpdatedAt[characterKey(memberName)] = timestamp
        return applyManagedAssignment(store, memberName, mainName, role, timestamp, sender)
    end
    if parts[1] == "IDENT_MEMBER" then
        local timestamp = tonumber(parts[3])
        local memberName, mainName, role = cleanWireText(parts[4], 80), cleanWireText(parts[5], 80), parts[6]
        local memberKey, mainKey, now = characterKey(memberName), characterKey(mainName), time()
        -- The addon-message sender is the proof of ownership. No Main, officer,
        -- or relay client may assign a different character to an identity group.
        if senderRank == nil or memberKey ~= characterKey(sender) or not timestamp
            or timestamp > now + 300 or timestamp < now - 180 * 86400
            or (role ~= "MAIN" and role ~= "ALT" and role ~= "BANK" and role ~= "REMOVE")
            or (role ~= "REMOVE" and (not mainKey or not iRC:IsGuildMemberName(mainName)))
            or (role == "MAIN" and memberKey ~= mainKey) then return false end
        local store = guildStore(true)
        local current = store.identityAssignments[memberKey]
        if current and (tonumber(current.updatedAt) or 0) >= timestamp then return false end
        if role == "REMOVE" then
            store.identityAssignments[memberKey] = nil
            for id, request in pairs(store.identityLinkRequests) do
                if characterKey(request.target) == memberKey then store.identityLinkRequests[id] = nil end
            end
            if iRC.MainUI then iRC.MainUI:RefreshIfShown() end
            if iRC.ConnectionDashboard then iRC.ConnectionDashboard:RefreshIfShown() end
            return true
        end
        store.identityAssignments[memberKey] = { name = iRC:FormatPlayerName(memberName), mainKey = mainKey,
            mainName = iRC:FormatPlayerName(mainName), role = role, updatedAt = math.floor(timestamp),
            source = iRC:FormatPlayerName(sender) }
        if store.characters[memberKey] and store.main == mainKey then store.confirmedCharacters[memberKey] = true end
        for id, request in pairs(store.identityLinkRequests) do
            if characterKey(request.target) == memberKey then store.identityLinkRequests[id] = nil end
        end
        if iRC.MainUI then iRC.MainUI:RefreshIfShown() end
        if iRC.ConnectionDashboard then iRC.ConnectionDashboard:RefreshIfShown() end
        return true
    end
    if parts[1] == "IDENT_LINK_REQUEST" then
        local id, createdAt, expiresAt = cleanWireText(parts[3], 12), tonumber(parts[4]), tonumber(parts[5])
        local requester, target, mainName = cleanWireText(parts[6], 80), cleanWireText(parts[7], 80), cleanWireText(parts[8], 80)
        local role = parts[9] == "BANK" and "BANK" or (parts[9] == "REMOVE" and "REMOVE" or "ALT")
        local now = time()
        if id == "" or id ~= linkRequestId(requester, target, mainName, role, createdAt)
            or not createdAt or not expiresAt or expiresAt <= now or expiresAt > createdAt + LINK_REQUEST_LIFETIME
            or createdAt > now + 300 or not iRC:IsGuildMemberName(requester)
            or not iRC:IsGuildMemberName(target) or not iRC:IsGuildMemberName(mainName) then return false end
        local store = guildStore(true)
        local requestCount = 0
        for _ in pairs(store.identityLinkRequests) do requestCount = requestCount + 1 end
        if not store.identityLinkRequests[id] and requestCount >= MAX_LINK_REQUESTS then return false end
        local request = { id = id, requester = iRC:FormatPlayerName(requester), target = iRC:FormatPlayerName(target),
            mainName = iRC:FormatPlayerName(mainName), role = role,
            createdAt = math.floor(createdAt), expiresAt = math.floor(expiresAt) }
        store.identityLinkRequests[id] = request
        showLinkRequest(request)
        return true
    end
    if parts[1] == "IDENT_LINK_DECLINE" then
        local id, target = cleanWireText(parts[3], 12), cleanWireText(parts[4], 80)
        if characterKey(sender) ~= characterKey(target) then return false end
        local store = guildStore(true)
        local request = store.identityLinkRequests[id]
        local targetKey = characterKey(target)
        if request and characterKey(request.requester) == characterKey(iRC:GetPlayerName())
            and store.confirmedCharacters[targetKey] ~= true then
            store.characters[targetKey], store.personalBanks[targetKey] = nil, nil
        end
        for requestId, pending in pairs(store.identityLinkRequests) do
            if characterKey(pending.target) == targetKey then store.identityLinkRequests[requestId] = nil end
        end
        return true
    end
    if parts[1] == "IDENT_REQUEST" then
        if senderRank == nil then return false end
        C_Timer.After(math.random() * 3, function() Identity:BroadcastPersonalIdentity(sender, true) end)
        if not iRC:IsRulesetBroadcaster() then return false end
        local senderKey, now = characterKey(sender), time()
        for key, respondedAt in pairs(historyResponseAt) do
            if now - respondedAt >= HISTORY_RESPONSE_COOLDOWN then historyResponseAt[key] = nil end
        end
        if historyResponseAt[senderKey] and now - historyResponseAt[senderKey] < HISTORY_RESPONSE_COOLDOWN then return true end
        historyResponseAt[senderKey] = now
        local records = self:GetGuildLog()
        -- A shared bounded worker prevents several simultaneous catch-up
        -- requests from creating hundreds of independent timer callbacks.
        for index = 1, math.min(#records, MAX_SHARED_HISTORY) do
            if not queueHistoryResponse(records[index], sender) then break end
        end
        return true
    end
    if not iRC:GuildMemberHasPermission(sender, "rosterHistory") then return false end
    if parts[1] ~= "IDENT_EVENT" then return false end
    local id, occurredAt = cleanWireText(parts[3], 12), tonumber(parts[4])
    local eventType, name = cleanWireText(parts[5], 18), cleanWireText(parts[6], 80)
    local classFile, text = cleanWireText(parts[7], 12), cleanWireText(parts[8], 100)
    local now = time()
    if id == "" or not occurredAt or occurredAt > now + 300 or occurredAt < now - 180 * 86400
        or not SYNCED_EVENT_TYPES[eventType] or name == ""
        or not iRC:IsGuildMemberName(name) and eventType ~= "LEAVE" then return false end
    local store = guildStore(true)
    if not store or store.guildLogIds[id] then return false end
    -- Different clients can observe the same roster change a few seconds apart.
    -- Treat that as one event even when their timestamp-based IDs differ.
    for _, existing in ipairs(store.guildLog) do
        if existing.eventType == eventType and characterKey(existing.name) == characterKey(name)
            and tostring(existing.text or "") == text
            and math.abs((tonumber(existing.occurredAt) or 0) - occurredAt) <= 10 then
            store.guildLogIds[id] = true
            return false
        end
    end
    local record = { id = id, occurredAt = math.floor(occurredAt), eventType = eventType,
        name = iRC:FormatPlayerName(name), classFile = classFile ~= "" and classFile or nil, text = text }
    store.guildLog[#store.guildLog + 1] = record
    store.guildLogIds[id] = true
    table.sort(store.guildLog, function(a, b) return (tonumber(a.occurredAt) or 0) < (tonumber(b.occurredAt) or 0) end)
    trimGuildLog(store)
    local key = characterKey(name)
    local history = store.memberHistory[key] or { firstSeenAt = occurredAt, rankHistory = {} }
    store.memberHistory[key] = history
    history.name, history.classFile = record.name, record.classFile or history.classFile
    history.firstSeenAt = math.min(tonumber(history.firstSeenAt) or occurredAt, occurredAt)
    if eventType == "JOIN" then history.joinedAt = occurredAt
    elseif eventType == "REJOIN" then history.rejoinedAt, history.departedAt = occurredAt, nil
    elseif eventType == "LEAVE" then history.departedAt = occurredAt
    elseif eventType == "PROMOTE" or eventType == "DEMOTE" then
        local fromRank, toRank = text:match(" from (.-) to (.-)%.$")
        if fromRank and toRank then
            history.rankHistory[#history.rankHistory + 1] = { changedAt = occurredAt, fromRank = fromRank, toRank = toRank }
            while #history.rankHistory > 30 do table.remove(history.rankHistory, 1) end
        end
    end
    if iRC.MainUI then iRC.MainUI:RefreshIfShown() end
    return true
end

function Identity:ScanRoster()
    local store = guildStore(true)
    local roster = iRC:GetGuildRosterSnapshot()
    if not store or #roster < 1 then return end
    local current, currentByGUID, previousByGUID, onlinePersonal, retryMissing = {}, {}, {}, {}, false
    for key, member in pairs(store.roster) do
        if member.guid then previousByGUID[member.guid] = { key = key, member = member } end
    end
    for _, member in ipairs(roster) do
        local key = characterKey(member.name)
        local history = store.memberHistory[key]
        if not history then
            history = { firstSeenAt = time(), rankHistory = {} }
            store.memberHistory[key] = history
        end
        history.rankHistory = type(history.rankHistory) == "table" and history.rankHistory or {}
        history.name = iRC:FormatPlayerName(member.name)
        history.classFile = member.classFile
        history.lastSeenAt = time()
        current[key] = {
            name = iRC:FormatPlayerName(member.name), rankIndex = member.rankIndex,
            rankName = member.rankName, level = member.level, className = member.className,
            classFile = member.classFile, guid = member.guid,
            publicNote = member.publicNote, officerNote = member.officerNote,
            online = member.online == true, lastOnlineDays = member.lastOnlineDays,
        }
        if member.guid then currentByGUID[member.guid] = key end
        store.missingCounts[key] = nil
        if store.characters[key] and member.online then onlinePersonal[#onlinePersonal + 1] = key end
        local former = store.formerMembers[key]
        if former and former.currentMember ~= true then
            former.currentMember = true
            former.rejoinedAt = time()
            former.rejoinCount = (former.rejoinCount or 0) + 1
            history.rejoinedAt = former.rejoinedAt
            history.departedAt = nil
            addGuildLog(store, "REJOIN", member.name, iRC:FormatPlayerName(member.name) .. " rejoined the guild.", member.classFile)
        elseif store.rosterReady and not store.roster[key] then
            local renamed = member.guid and previousByGUID[member.guid]
            if renamed and renamed.key ~= key then
                local oldHistory = store.memberHistory[renamed.key]
                if oldHistory then
                    store.memberHistory[key] = oldHistory
                    store.memberHistory[renamed.key] = nil
                    history = oldHistory
                    history.name = iRC:FormatPlayerName(member.name)
                    history.classFile = member.classFile
                end
                if store.characters[renamed.key] then
                    store.characters[renamed.key] = nil
                    store.characters[key] = iRC:FormatPlayerName(member.name)
                    if store.personalBanks[renamed.key] then
                        store.personalBanks[renamed.key] = nil
                        store.personalBanks[key] = true
                    end
                    if store.main == renamed.key then store.main = key end
                end
                if store.formerMembers[renamed.key] and not store.formerMembers[key] then
                    store.formerMembers[key] = store.formerMembers[renamed.key]
                    store.formerMembers[renamed.key] = nil
                    store.formerMembers[key].name = iRC:FormatPlayerName(member.name)
                end
                for _, logRecord in ipairs(store.guildLog) do
                    if characterKey(logRecord.name) == renamed.key then
                        logRecord.name = iRC:FormatPlayerName(member.name)
                        if not logRecord.classFile then logRecord.classFile = member.classFile end
                    end
                end
                store.missingCounts[renamed.key] = nil
                addGuildLog(store, "NAME", member.name, renamed.member.name .. " is now known as " .. iRC:FormatPlayerName(member.name) .. ".", member.classFile)
            else
                history.joinedAt = time()
                addGuildLog(store, "JOIN", member.name, iRC:FormatPlayerName(member.name) .. " joined the guild.", member.classFile)
            end
        elseif store.rosterReady then
            local previous = store.roster[key]
            if previous.online == false and member.online == true
                and (tonumber(previous.lastOnlineDays) or 0) >= 30 then
                addGuildLog(store, "RETURN", member.name, iRC:FormatPlayerName(member.name)
                    .. " returned after being inactive for " .. math.floor(previous.lastOnlineDays) .. " days.", member.classFile)
            end
            if previous.rankIndex ~= member.rankIndex then
                local promoted = (tonumber(member.rankIndex) or 99) < (tonumber(previous.rankIndex) or 99)
                local oldRank = previous.rankName or ("rank " .. tostring(previous.rankIndex))
                local newRank = member.rankName or ("rank " .. tostring(member.rankIndex))
                addGuildLog(store, promoted and "PROMOTE" or "DEMOTE", member.name,
                    iRC:FormatPlayerName(member.name) .. " was " .. (promoted and "promoted" or "demoted") .. " from " .. oldRank .. " to " .. newRank .. ".", member.classFile)
                history.rankHistory[#history.rankHistory + 1] = {
                    changedAt = time(), fromRank = oldRank, toRank = newRank,
                    fromRankIndex = previous.rankIndex, toRankIndex = member.rankIndex,
                }
                while #history.rankHistory > 30 do table.remove(history.rankHistory, 1) end
            end
            if tonumber(previous.level) ~= tonumber(member.level) then
                addGuildLog(store, "LEVEL", member.name, iRC:FormatPlayerName(member.name) .. " changed from level "
                    .. tostring(previous.level or "?") .. " to level " .. tostring(member.level or "?") .. ".", member.classFile)
            end
            if previous.publicNote ~= nil and tostring(previous.publicNote) ~= tostring(member.publicNote or "") then
                addGuildLog(store, "NOTE", member.name, iRC:FormatPlayerName(member.name) .. " had their public note changed.", member.classFile)
            end
            if previous.officerNote ~= nil and tostring(previous.officerNote) ~= tostring(member.officerNote or "") then
                addGuildLog(store, "OFFICER_NOTE", member.name, iRC:FormatPlayerName(member.name) .. " had their officer note changed.", member.classFile)
            end
        end
    end
    if store.rosterReady then
        for key, previous in pairs(store.roster) do
            if not current[key] and not (previous.guid and currentByGUID[previous.guid]) then
                store.missingCounts[key] = (store.missingCounts[key] or 0) + 1
                if store.missingCounts[key] >= 2 then
                    local record = store.formerMembers[key] or {}
                    record.name, record.lastRankIndex, record.level, record.className = previous.name, previous.rankIndex, previous.level, previous.className
                    record.departedAt, record.departureType, record.currentMember = time(), "Left or removed", false
                    record.identity = self:GetIdentityLabel(previous.name)
                    store.formerMembers[key] = record
                    store.missingCounts[key] = nil
                    addGuildLog(store, "LEAVE", previous.name, previous.name .. " left or was removed from the guild.", previous.classFile)
                    local history = store.memberHistory[key]
                    if history then history.departedAt = record.departedAt end
                else
                    current[key] = previous
                    retryMissing = true
                end
            end
        end
    end
    store.roster, store.rosterReady = current, true

    local active = {}
    if #onlinePersonal > 1 then
        table.sort(onlinePersonal)
        local warningKey = table.concat(onlinePersonal, ":")
        active[warningKey] = true
        if not warnedTogether[warningKey] then
            warnedTogether[warningKey] = true
            local names = {}
            for _, key in ipairs(onlinePersonal) do names[#names + 1] = store.characters[key] end
            iRC:Print("Personal character warning: " .. table.concat(names, " and ") .. " are online at the same time. Check your main/alt links.")
        end
    end
    for key in pairs(warnedTogether) do if not active[key] then warnedTogether[key] = nil end end
    if retryMissing and not rosterRetryScheduled and C_Timer and C_Timer.After then
        rosterRetryScheduled = true
        C_Timer.After(3, function()
            rosterRetryScheduled = nil
            Identity:ScanRoster()
        end)
    end
end

function Identity:HandleRosterUpdate()
    local store, currentKey = guildStore(false), characterKey(iRC:GetPlayerName())
    if store and store.characters[currentKey] and store.confirmedCharacters[currentKey] ~= true then
        self:RegisterCharacter(iRC:GetPlayerName(), nil, true)
    end
    self:ScanRoster()
    if time() - lastLinkRelayAt >= 30 then
        lastLinkRelayAt = time()
        self:RelayPendingLinkRequests()
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event)
    if not C_Timer or not C_Timer.After then return end
    C_Timer.After(event == "PLAYER_LOGIN" and 5 or 1, function()
        if event == "PLAYER_LOGIN" then
            Identity:RegisterCharacter(iRC:GetPlayerName(), nil, true)
            C_Timer.After(8, function()
                Identity:BroadcastPersonalIdentity(nil, true)
                Identity:RequestGuildHistory()
                Identity:RelayPendingLinkRequests()
            end)
        end
        Identity:ScanRoster()
        if time() - lastLinkRelayAt >= 30 then
            lastLinkRelayAt = time()
            Identity:RelayPendingLinkRequests()
        end
    end)
end)
