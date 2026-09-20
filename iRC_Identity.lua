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
    iRCAccountDB = type(iRCAccountDB) == "table" and iRCAccountDB or {}
    iRCAccountDB.identityGuilds = type(iRCAccountDB.identityGuilds) == "table" and iRCAccountDB.identityGuilds or {}
    local store = iRCAccountDB.identityGuilds[guildKey]
    if not store and create then
        store = { characters = {}, formerMembers = {}, roster = {} }
        iRCAccountDB.identityGuilds[guildKey] = store
    end
    if store then
        store.characters = type(store.characters) == "table" and store.characters or {}
        store.formerMembers = type(store.formerMembers) == "table" and store.formerMembers or {}
        store.roster = type(store.roster) == "table" and store.roster or {}
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
    if store.main == key then
        store.main = next(store.characters)
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
    return true
end

function Identity:GetMainName()
    local store = guildStore(false)
    return store and store.main and store.characters[store.main] or nil
end

function Identity:GetCharacters()
    local store, result = guildStore(false), {}
    for key, name in pairs(store and store.characters or {}) do result[#result + 1] = { key = key, name = name } end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

function Identity:GetIdentityLabel(name)
    local store, key = guildStore(false), characterKey(name)
    if not store or not key or not store.characters[key] then return nil end
    if store.main == key then return "Main" end
    return "Alt of " .. (store.characters[store.main] or "unknown")
end

function Identity:GetFormerMembers()
    local store, result = guildStore(false), {}
    for _, record in pairs(store and store.formerMembers or {}) do result[#result + 1] = record end
    table.sort(result, function(a, b) return (a.departedAt or 0) > (b.departedAt or 0) end)
    return result
end

function Identity:ScanRoster()
    local store = guildStore(true)
    local roster = iRC:GetGuildRosterSnapshot()
    if not store or #roster < 1 then return end
    local current, onlinePersonal, retryMissing = {}, {}, false
    for _, member in ipairs(roster) do
        local key = characterKey(member.name)
        current[key] = {
            name = iRC:FormatPlayerName(member.name), rankIndex = member.rankIndex,
            level = member.level, className = member.className, guid = member.guid,
        }
        store.missingCounts[key] = nil
        if store.characters[key] and member.online then onlinePersonal[#onlinePersonal + 1] = key end
        local former = store.formerMembers[key]
        if former and former.currentMember ~= true then
            former.currentMember = true
            former.rejoinedAt = time()
            former.rejoinCount = (former.rejoinCount or 0) + 1
        end
    end
    if store.rosterReady then
        for key, previous in pairs(store.roster) do
            if not current[key] then
                store.missingCounts[key] = (store.missingCounts[key] or 0) + 1
                if store.missingCounts[key] >= 2 then
                    local record = store.formerMembers[key] or {}
                    record.name, record.lastRankIndex, record.level, record.className = previous.name, previous.rankIndex, previous.level, previous.className
                    record.departedAt, record.departureType, record.currentMember = time(), "Left or removed", false
                    record.identity = self:GetIdentityLabel(previous.name)
                    store.formerMembers[key] = record
                    store.missingCounts[key] = nil
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
