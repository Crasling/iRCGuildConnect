local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local Identity = {}
iRC.Identity = Identity
local warnedTogether = {}
local rosterRetryScheduled

local function guildStore(create)
    local guildKey = iRC:GetGuildKey()
    if not guildKey then return nil end
    iRCDB = type(iRCDB) == "table" and iRCDB or {}
    iRCDB.identityGuilds = type(iRCDB.identityGuilds) == "table" and iRCDB.identityGuilds or {}
    local store = iRCDB.identityGuilds[guildKey]
    if not store and create then
        store = { characters = {}, personalBanks = {}, formerMembers = {}, roster = {}, guildLog = {} }
        iRCDB.identityGuilds[guildKey] = store
    end
    if store then
        store.characters = type(store.characters) == "table" and store.characters or {}
        store.personalBanks = type(store.personalBanks) == "table" and store.personalBanks or {}
        store.formerMembers = type(store.formerMembers) == "table" and store.formerMembers or {}
        store.roster = type(store.roster) == "table" and store.roster or {}
        store.guildLog = type(store.guildLog) == "table" and store.guildLog or {}
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
    return true
end

function Identity:IsPersonalBank(name)
    local store, key = guildStore(false), characterKey(name)
    return store and key and store.characters[key] ~= nil and store.personalBanks[key] == true or false
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
    if not store or not key or not store.characters[key] then return nil end
    if store.main == key then return "Main" end
    if store.personalBanks[key] then return "Personal Bank Alt of " .. (store.characters[store.main] or "unknown") end
    return "Alt of " .. (store.characters[store.main] or "unknown")
end

function Identity:GetFormerMembers()
    local store, result = guildStore(false), {}
    for _, record in pairs(store and store.formerMembers or {}) do result[#result + 1] = record end
    table.sort(result, function(a, b) return (a.departedAt or 0) > (b.departedAt or 0) end)
    return result
end

local function addGuildLog(store, eventType, name, text)
    local log = store and store.guildLog
    if not log then return end
    log[#log + 1] = {
        occurredAt = time(),
        eventType = eventType,
        name = iRC:FormatPlayerName(name or ""),
        text = text,
    }
    while #log > 500 do table.remove(log, 1) end
end

function Identity:GetGuildLog()
    local store, result = guildStore(false), {}
    for index = #(store and store.guildLog or {}), 1, -1 do
        result[#result + 1] = store.guildLog[index]
    end
    return result
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
        current[key] = {
            name = iRC:FormatPlayerName(member.name), rankIndex = member.rankIndex,
            rankName = member.rankName, level = member.level, className = member.className, guid = member.guid,
            publicNote = member.publicNote, officerNote = member.officerNote,
        }
        if member.guid then currentByGUID[member.guid] = key end
        store.missingCounts[key] = nil
        if store.characters[key] and member.online then onlinePersonal[#onlinePersonal + 1] = key end
        local former = store.formerMembers[key]
        if former and former.currentMember ~= true then
            former.currentMember = true
            former.rejoinedAt = time()
            former.rejoinCount = (former.rejoinCount or 0) + 1
            addGuildLog(store, "REJOIN", member.name, iRC:FormatPlayerName(member.name) .. " rejoined the guild.")
        elseif store.rosterReady and not store.roster[key] then
            local renamed = member.guid and previousByGUID[member.guid]
            if renamed and renamed.key ~= key then
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
                store.missingCounts[renamed.key] = nil
                addGuildLog(store, "NAME", member.name, renamed.member.name .. " is now known as " .. iRC:FormatPlayerName(member.name) .. ".")
            else
                addGuildLog(store, "JOIN", member.name, iRC:FormatPlayerName(member.name) .. " joined the guild.")
            end
        elseif store.rosterReady then
            local previous = store.roster[key]
            if previous.rankIndex ~= member.rankIndex then
                local promoted = (tonumber(member.rankIndex) or 99) < (tonumber(previous.rankIndex) or 99)
                local oldRank = previous.rankName or ("rank " .. tostring(previous.rankIndex))
                local newRank = member.rankName or ("rank " .. tostring(member.rankIndex))
                addGuildLog(store, promoted and "PROMOTE" or "DEMOTE", member.name,
                    iRC:FormatPlayerName(member.name) .. " was " .. (promoted and "promoted" or "demoted") .. " from " .. oldRank .. " to " .. newRank .. ".")
            end
            if tonumber(previous.level) ~= tonumber(member.level) then
                addGuildLog(store, "LEVEL", member.name, iRC:FormatPlayerName(member.name) .. " changed from level "
                    .. tostring(previous.level or "?") .. " to level " .. tostring(member.level or "?") .. ".")
            end
            if previous.publicNote ~= nil and tostring(previous.publicNote) ~= tostring(member.publicNote or "") then
                addGuildLog(store, "NOTE", member.name, iRC:FormatPlayerName(member.name) .. " had their public note changed.")
            end
            if previous.officerNote ~= nil and tostring(previous.officerNote) ~= tostring(member.officerNote or "") then
                addGuildLog(store, "OFFICER_NOTE", member.name, iRC:FormatPlayerName(member.name) .. " had their officer note changed.")
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
                    addGuildLog(store, "LEAVE", previous.name, previous.name .. " left or was removed from the guild.")
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
        if event == "PLAYER_LOGIN" then Identity:RegisterCharacter(iRC:GetPlayerName()) end
        Identity:ScanRoster()
    end)
end)
