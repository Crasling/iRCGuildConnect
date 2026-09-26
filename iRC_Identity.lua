local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local Identity = {}
iRC.Identity = Identity
local warnedTogether = {}
local rosterRetryScheduled
local lastHistoryRequestAt = 0
local IDENTITY_WIRE_VERSION = "1"
local initializedGuildLogStores = setmetatable({}, { __mode = "k" })
local SYNCED_EVENT_TYPES = {
    JOIN = true, REJOIN = true, LEAVE = true, PROMOTE = true, DEMOTE = true,
    LEVEL = true, NAME = true, NOTE = true, OFFICER_NOTE = true, RETURN = true,
}

local function cleanWireText(value, limit)
    return tostring(value or ""):gsub("[%c]", " "):gsub("%s+", " "):sub(1, limit or 80)
end

local function eventFingerprint(eventType, name, text, occurredAt)
    local value = table.concat({ tostring(eventType), iRC:NormalizeName(name), tostring(text), math.floor((tonumber(occurredAt) or 0) / 5) }, "|")
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
        store.guildIdentityGroups = type(store.guildIdentityGroups) == "table" and store.guildIdentityGroups or {}
        store.missingCounts = type(store.missingCounts) == "table" and store.missingCounts or {}
    end
    return store
end

local function characterKey(name)
    return iRC:NormalizeName(name)
end

function Identity:GetStore()
    return guildStore(true)
end

function Identity:RegisterCharacter(name)
    local store = guildStore(true)
    local key = characterKey(name)
    if not store or not key or key == "" then return false end
    store.characters[key] = iRC:FormatPlayerName(name)
    if not store.main or not store.characters[store.main] then store.main = key end
    self:BroadcastPersonalIdentity()
    return true
end

function Identity:RemoveCharacter(name)
    local store, key = guildStore(false), characterKey(name)
    if not store or not key or not store.characters[key] then return false end
    store.characters[key] = nil
    store.personalBanks[key] = nil
    if store.main == key then
        store.main = next(store.characters)
    end
    self:BroadcastPersonalIdentity()
    return true
end

function Identity:IsPersonalBank(name)
    local store, key = guildStore(false), characterKey(name)
    if store and key and store.characters[key] ~= nil and store.personalBanks[key] == true then return true end
    for _, group in pairs(store and store.guildIdentityGroups or {}) do
        if group.characters and group.characters[key] and group.personalBanks and group.personalBanks[key] then return true end
    end
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
                if candidate ~= key then store.main = candidate; break end
            end
        end
    else
        store.personalBanks[key] = nil
    end
    self:BroadcastPersonalIdentity()
    return true
end

function Identity:IsPersonalCharacter(name)
    local store, key = guildStore(false), characterKey(name)
    return store and key and store.characters[key] ~= nil or false
end

function Identity:SetMain(name)
    local store, key = guildStore(true), characterKey(name)
    if not store or not key or not store.characters[key] then return false end
    store.main = key
    store.personalBanks[key] = nil
    self:BroadcastPersonalIdentity()
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
        if store.main == key then return "Main" end
        if store.personalBanks[key] then return "Personal Bank Alt of " .. (store.characters[store.main] or "unknown") end
        return "Alt of " .. (store.characters[store.main] or "unknown")
    end
    for _, group in pairs(store.guildIdentityGroups or {}) do
        if group.characters and group.characters[key] then
            if group.main == key then return "Main" end
            if group.personalBanks and group.personalBanks[key] then
                return "Personal Bank Alt of " .. (group.characters[group.main] or "unknown")
            end
            return "Alt of " .. (group.characters[group.main] or "unknown")
        end
    end
end

function Identity:GetLinkedCharacters(name)
    local store, key, result = guildStore(false), characterKey(name), {}
    if not store or not key then return result end
    local characters = store.characters[key] and store.characters or nil
    if not characters then
        for _, group in pairs(store.guildIdentityGroups or {}) do
            if group.characters and group.characters[key] then characters = group.characters; break end
        end
    end
    for _, characterName in pairs(characters or {}) do result[#result + 1] = characterName end
    table.sort(result)
    return result
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
    while #log > 500 do
        local removed = table.remove(log, 1)
        if removed and removed.id then store.guildLogIds[removed.id] = nil end
    end
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
    if not iRC:IsGuildConnectionActive() or time() - lastHistoryRequestAt < 60 then return false end
    lastHistoryRequestAt = time()
    return iRC:SendAddonTraffic(iRC.Prefix, table.concat({ "IDENT_REQUEST", IDENTITY_WIRE_VERSION }, "\t"), "GUILD")
end

function Identity:BroadcastPersonalIdentity(targetName, preserveTimestamp)
    local store = guildStore(false)
    if not store or not store.main or not store.characters[store.main] or not iRC:IsGuildConnectionActive() then return false end
    local ownKey = characterKey(iRC:GetPlayerName())
    if not store.characters[ownKey] then return false end
    local names, banks = {}, {}
    for key, name in pairs(store.characters) do
        names[#names + 1] = cleanWireText(name, 80)
        if store.personalBanks[key] then banks[#banks + 1] = cleanWireText(name, 80) end
    end
    table.sort(names); table.sort(banks)
    if #names > 10 then return false end
    if not preserveTimestamp or not tonumber(store.identityUpdatedAt) then
        store.identityUpdatedAt = math.max(time(), (tonumber(store.identityUpdatedAt) or 0) + 1)
    end
    local payload = table.concat({ "IDENT_GROUP", IDENTITY_WIRE_VERSION, tostring(store.identityUpdatedAt),
        cleanWireText(store.characters[store.main], 80), table.concat(names, ","), table.concat(banks, ",") }, "\t")
    return iRC:SendAddonTraffic(iRC.Prefix, payload, targetName and "WHISPER" or "GUILD", targetName)
end

function Identity:ReceiveSync(parts, sender)
    if parts[2] ~= IDENTITY_WIRE_VERSION then return false end
    local senderRank = iRC:GetGuildMemberRankIndex(sender)
    if parts[1] == "IDENT_GROUP" then
        local timestamp, mainName = tonumber(parts[3]), cleanWireText(parts[4], 80)
        local names, banks, includesSender = {}, {}, false
        for name in tostring(parts[5] or ""):gmatch("[^,]+") do
            name = cleanWireText(name, 80)
            local key = characterKey(name)
            if key and key ~= "" and iRC:IsGuildMemberName(name) then
                names[key] = iRC:FormatPlayerName(name)
                if key == characterKey(sender) then includesSender = true end
            end
        end
        for name in tostring(parts[6] or ""):gmatch("[^,]+") do banks[characterKey(name)] = true end
        local mainKey, now = characterKey(mainName), time()
        if not timestamp or timestamp > now + 300 or timestamp < now - 180 * 86400 or not includesSender
            or not mainKey or not names[mainKey] then return false end
        for key in pairs(banks) do if not names[key] then banks[key] = nil end end
        local store = guildStore(true)
        local current = store.guildIdentityGroups[mainKey]
        if current and (tonumber(current.updatedAt) or 0) >= timestamp then return false end
        for groupKey, group in pairs(store.guildIdentityGroups) do
            if groupKey ~= mainKey and (tonumber(group.updatedAt) or 0) <= timestamp then
                for key in pairs(names) do
                    if group.characters and group.characters[key] then store.guildIdentityGroups[groupKey] = nil; break end
                end
            end
        end
        store.guildIdentityGroups[mainKey] = { main = mainKey, characters = names, personalBanks = banks,
            updatedAt = math.floor(timestamp), source = iRC:FormatPlayerName(sender) }
        if iRC.MainUI then iRC.MainUI:RefreshIfShown() end
        if iRC.ConnectionDashboard then iRC.ConnectionDashboard:RefreshIfShown() end
        return true
    end
    if parts[1] == "IDENT_REQUEST" then
        if senderRank == nil then return false end
        C_Timer.After(math.random() * 3, function() Identity:BroadcastPersonalIdentity(sender, true) end)
        if not iRC:IsRulesetBroadcaster() then return false end
        local records = self:GetGuildLog()
        for index = 1, math.min(#records, 50) do
            local record = records[index]
            C_Timer.After((index - 1) * 0.10, function() Identity:BroadcastGuildLog(record, sender) end)
        end
        return true
    end
    if senderRank == nil or senderRank > iRC:GetGuildRankPermission("rosterHistory") then return false end
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
    while #store.guildLog > 500 do
        local removed = table.remove(store.guildLog, 1)
        if removed and removed.id then store.guildLogIds[removed.id] = nil end
    end
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

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:SetScript("OnEvent", function(_, event)
    if not C_Timer or not C_Timer.After then return end
    C_Timer.After(event == "PLAYER_LOGIN" and 5 or 1, function()
        if event == "PLAYER_LOGIN" then
            Identity:RegisterCharacter(iRC:GetPlayerName())
            C_Timer.After(8, function()
                Identity:BroadcastPersonalIdentity(nil, true)
                Identity:RequestGuildHistory()
            end)
        end
        Identity:ScanRoster()
    end)
end)
