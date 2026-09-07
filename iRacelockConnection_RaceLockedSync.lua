local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local Sync = {}
iRC.RaceLockedSync = Sync
local IRC_ROSTER = "iRCGFRoster"
local lastBroadcast, pendingRelays = {}, {}
local moneyReady = false

local function shortName(name)
    return type(name) == "string" and name:match("^([^-]+)") or nil
end

local function number(value, maximum)
    value = tonumber(value)
    if not value or value ~= value or value < 0 or value > maximum or value % 1 ~= 0 then return nil end
    return value
end

local function wireBool(value)
    if value == true then return "1" end
    if value == false then return "0" end
    return "-"
end

local function readBool(value)
    if value == "1" then return true end
    if value == "0" then return false end
end

local function validBool(value)
    return value == "1" or value == "0" or value == "-"
end

local function connection()
    if not iRC:IsGuildConnectionActive() then return nil end
    local db = iRC:GetConnection()
    db.guildFoundRoster = db.guildFoundRoster or {}
    if not db.legacyRaceLockedRosterCleared then
        for key, entry in pairs(db.guildFoundRoster) do
            local source = type(entry) == "table" and tostring(entry.source or "") or ""
            local overrideSource = type(entry) == "table" and tostring(entry.overrideSource or "") or ""
            if source:find("^RaceLocked") or overrideSource:find("^RaceLocked") then db.guildFoundRoster[key] = nil end
        end
        db.legacyRaceLockedRosterCleared = true
    end
    db.raceDeaths = db.raceDeaths or {}
    db.deathReports = db.deathReports or {}
    return db
end

local function refresh()
    if iRC.ConnectionDashboard then iRC.ConnectionDashboard:RefreshIfShown() end
    if iRC.MainUI then iRC.MainUI:RefreshIfShown() end
end

local function send(prefix, payload, target)
    if not connection() or #payload > 255 then return false end
    local api = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
    if not api then return false end
    api(prefix, payload, target and "WHISPER" or "GUILD", target)
    iRC:DebugMsg(iRC:Text(prefix == IRC_ROSTER and "IRC_GF_SYNC_SENT" or "RL_SYNC_SENT", prefix), 3)
    return true
end

local function entryFor(name)
    local db = connection()
    if not db or not iRC:IsGuildMemberName(name) then return nil end
    local key = iRC:NormalizeName(name)
    local entry = db.guildFoundRoster[key]
    if not entry then
        entry = { name = shortName(name) }
        db.guildFoundRoster[key] = entry
    end
    return entry
end

function Sync:GetStatus(name, snapshot)
    local db = snapshot
    if db == nil then db = connection() end
    local entry = db and db.active == true and db.guildFoundRoster and db.guildFoundRoster[iRC:NormalizeName(name)]
    if not entry then return nil end
    if iRC:NormalizeName(name) == iRC:NormalizeName(iRC:GetPlayerName()) then
        entry.verified, entry.clean, entry.tamperAt = self:GetLocalRawStatus()
    end
    return {
        -- Reported client state is authoritative. GM decisions are retained as
        -- separate audit metadata and never replace an actual response.
        verified = entry.verified, clean = entry.clean, source = entry.source,
        lastSeen = entry.lastSeen, gmTimestamp = entry.gmTimestamp,
        overrideSource = entry.overrideSource, directOverride = entry.directOverride,
        tamperAt = entry.tamperAt, rawVerified = entry.verified, rawClean = entry.clean,
        gmVerified = entry.gmVerified, gmClean = entry.gmClean,
    }
end

local function localHistory()
    iRCCharDB = iRCCharDB or {}
    iRCCharDB.guildFoundHistory = iRCCharDB.guildFoundHistory or {}
    return iRCCharDB.guildFoundHistory
end

function Sync:ObserveSelfFound()
    local history = localHistory()
    if iRC:GetSelfFoundState() then
        if (UnitLevel("player") or 0) >= 60 then history.maxLevelSelfFound = true end
        history.moneyDiscrepancyAt = nil
    end
end

function Sync:ValidateMoney()
    if moneyReady then return end
    local current = GetMoney and GetMoney()
    if not current then return end
    local history = localHistory()
    if history.money ~= nil and history.money ~= current and not iRC:GetSelfFoundState() then
        history.moneyDiscrepancyAt = time()
        iRC:Print(iRC:Text("RL_MONEY_DISCREPANCY"))
    end
    history.money = current
    moneyReady = true
    self:ObserveSelfFound()
end

function Sync:GetLocalRawStatus()
    self:ObserveSelfFound()
    local history = localHistory()
    local verified = history.maxLevelSelfFound == true
    local clean, tamperAt = history.moneyDiscrepancyAt == nil, history.moneyDiscrepancyAt or 0
    return verified, clean, tamperAt
end

local function storeSelf(name, verified, clean, tamperAt, source)
    local entry = entryFor(name)
    if not entry then return end
    entry.verified, entry.clean, entry.tamperAt = verified, clean, tamperAt
    entry.source, entry.lastSeen = source, time()
end

local function storeOverride(name, verified, clean, stamp, source, direct)
    local entry = entryFor(name)
    if not entry or not stamp or stamp < 1 or stamp > time() + 300 then return false end
    local previous = entry.gmTimestamp or 0
    if stamp < previous then return false end
    if stamp == previous then
        if entry.gmVerified ~= verified or entry.gmClean ~= clean then return false end
        if direct then entry.directOverride, entry.overrideSource = true, source end
        return true
    end
    entry.gmVerified, entry.gmClean, entry.gmTimestamp = verified, clean, stamp
    entry.overrideSource, entry.directOverride = source, direct == true
    return true
end

local function overridePayload(marker, entry)
    return marker .. entry.name .. "," .. wireBool(entry.gmVerified) .. "," .. wireBool(entry.gmClean) .. "," .. tostring(entry.gmTimestamp)
end

local function queueRelay(name)
    local db, entry = connection(), entryFor(name)
    if not db or not entry or not entry.gmTimestamp then return end
    local key, guildKey = iRC:NormalizeName(name), db.key
    if pendingRelays[key] then return end
    local token = {}
    pendingRelays[key] = token
    C_Timer.After(1.5 + math.random() * 2, function()
        if pendingRelays[key] ~= token then return end
        pendingRelays[key] = nil
        local current = connection()
        if not current or current.key ~= guildKey then return end
        local row = current.guildFoundRoster[key]
        if row and row.gmTimestamp then send(IRC_ROSTER, overridePayload("O:", row)) end
    end)
end

function Sync:SetOverride(name, verified, clean)
    if not iRC:IsGuildMaster() or not connection() or not iRC:IsGuildMemberName(name) then return false end
    local memberLevel
    if GetNumGuildMembers and GetGuildRosterInfo then
        for index = 1, GetNumGuildMembers(true) do
            local memberName, _, _, level = GetGuildRosterInfo(index)
            if iRC:NormalizeName(memberName) == iRC:NormalizeName(name) then
                memberLevel = tonumber(level) or 0
                break
            end
        end
    end
    if not memberLevel or memberLevel < 60 then
        iRC:Print(iRC:Text("RL_OVERRIDE_LEVEL_60_ONLY"))
        return false
    end
    if verified ~= nil and type(verified) ~= "boolean" or clean ~= nil and type(clean) ~= "boolean" then return false end
    local entry = entryFor(name)
    local stamp = math.max(time(), (entry.gmTimestamp or 0) + 1)
    if not storeOverride(name, verified, clean, stamp, "iRC", true) then return false end
    send(IRC_ROSTER, overridePayload("G:", entry))
    iRC:Print(iRC:Text("RL_OVERRIDE_SAVED", entry.name))
    refresh()
    return true
end

function Sync:DescribeStatus(name, compact, status)
    if status == nil then status = self:GetStatus(name) end
    if not status then return iRC:Text("RL_STATUS_UNKNOWN") end
    local verified = status.verified == nil and "RL_STATUS_UNKNOWN" or (status.verified and "RL_VERIFIED" or "RL_UNVERIFIED")
    local clean = status.clean == nil and "RL_STATUS_UNKNOWN" or (status.clean and "RL_CLEAN" or "RL_FLAGGED")
    local text = iRC:Text(verified) .. " / " .. iRC:Text(clean)
    if not compact then
        local details = {}
        if status.source and status.source ~= "" then details[#details + 1] = iRC:Text("RL_REPORT_SOURCE", status.source) end
        if status.lastSeen and status.lastSeen > 0 then details[#details + 1] = iRC:Text("RL_LAST_REPORT", date("%Y-%m-%d %H:%M", status.lastSeen)) end
        if status.tamperAt and status.tamperAt > 0 then details[#details + 1] = iRC:Text("RL_DISCREPANCY_SEEN", date("%Y-%m-%d %H:%M", status.tamperAt)) end
        if status.gmTimestamp then
            details[#details + 1] = iRC:Text(status.directOverride and "RL_GM_DIRECT" or "RL_GM_RELAY")
            details[#details + 1] = iRC:Text("RL_DECISION_TIME", date("%Y-%m-%d %H:%M", status.gmTimestamp))
        end
        if #details > 0 then text = text .. "\n" .. table.concat(details, "\n") end
    end
    return text
end

function Sync:ReceiveRoster(message, sender)
    if not connection() or not iRC:IsGuildMemberName(sender) or type(message) ~= "string" or #message > 255 then return end
    local marker, payload = message:sub(1, 2), message:sub(3)
    local fields = {}
    for value in (payload .. ","):gmatch("(.-),") do fields[#fields + 1] = value end
    if marker == "S:" then
        local name = fields[1]
        if iRC:NormalizeName(name) ~= iRC:NormalizeName(sender) then return end
        if (fields[2] ~= "0" and fields[2] ~= "1") or (fields[3] ~= "0" and fields[3] ~= "1") then return end
        local tamperAt = number(fields[4], time() + 300)
        if not tamperAt then return end
        storeSelf(name, readBool(fields[2]), readBool(fields[3]), tamperAt, "iRC")
        local stamp = number(fields[7], time() + 300)
        if validBool(fields[5]) and validBool(fields[6]) and stamp and stamp > 0
            and storeOverride(name, readBool(fields[5]), readBool(fields[6]), stamp, "iRC relay", false) then
            pendingRelays[iRC:NormalizeName(name)] = nil
        else
            queueRelay(name)
        end
    elseif marker == "G:" or marker == "O:" then
        local direct = marker == "G:"
        if direct and not iRC:IsGuildMasterName(sender) then return end
        if #fields % 4 ~= 0 then return end
        for index = 1, #fields, 4 do
            local name, stamp = fields[index], number(fields[index + 3], time() + 300)
            if validBool(fields[index + 1]) and validBool(fields[index + 2]) and stamp
                and storeOverride(name, readBool(fields[index + 1]), readBool(fields[index + 2]), stamp,
                    direct and "iRC GM" or "iRC relay", direct) then
                pendingRelays[iRC:NormalizeName(name)] = nil
            end
        end
    else return end
    iRC:DebugMsg(iRC:Text("IRC_GF_SYNC_RECEIVED", IRC_ROSTER, sender), 3)
    refresh()
end

function Sync:RecordDeath(name)
    local db = connection()
    if not db or not iRC:IsGuildMemberName(name) then return false end
    local key, now = iRC:NormalizeName(name), time()
    if db.deathReports[key] and now - db.deathReports[key] < 30 then return false end
    db.deathReports[key] = now
    local race = iRC:GetGuildRace()
    if race == "" then local _, token = UnitRace("player"); race = iRC:NormalizeGuildRace(token) end
    db.raceDeaths[race] = (db.raceDeaths[race] or 0) + 1
    iRC:DebugMsg(iRC:Text("RL_DEATH_RECEIVED", name), 3)
    refresh()
    return true
end

function Sync:Broadcast()
    local db = connection()
    if not db or not moneyReady then return end
    local now = GetTime()
    if lastBroadcast[db.key] and now - lastBroadcast[db.key] < 5 then return end
    lastBroadcast[db.key] = now
    local name = shortName(iRC:GetPlayerName())
    local verified, clean, tamperAt = self:GetLocalRawStatus()
    storeSelf(name, verified, clean, tamperAt, "iRC")
    if (UnitLevel("player") or 0) >= 60 then
        local entry = entryFor(name)
        local msg = "S:" .. name .. "," .. wireBool(verified) .. "," .. wireBool(clean) .. "," .. tostring(tamperAt)
        if entry.gmTimestamp then msg = msg .. "," .. wireBool(entry.gmVerified) .. "," .. wireBool(entry.gmClean) .. "," .. entry.gmTimestamp end
        send(IRC_ROSTER, msg)
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_MONEY")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("PLAYER_DEAD")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= iRC.Name then return end
        local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
        if register then register(IRC_ROSTER) end
    elseif event == "PLAYER_LOGIN" then
        Sync:ValidateMoney()
        C_Timer.After(5, function() Sync:Broadcast() end)
    elseif event == "PLAYER_MONEY" or event == "PLAYER_LOGOUT" then
        if moneyReady and GetMoney then localHistory().money = GetMoney() end
    elseif event == "UNIT_AURA" or event == "PLAYER_LEVEL_UP" then
        if event == "UNIT_AURA" and ... ~= "player" then return end
        Sync:ObserveSelfFound()
    elseif event == "PLAYER_DEAD" then
        Sync:RecordDeath(iRC:GetPlayerName())
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        if channel ~= "GUILD" or type(msg) ~= "string" or #msg > 255 then return end
        if iRC:NormalizeName(sender) == iRC:NormalizeName(iRC:GetPlayerName()) then return end
        if prefix == IRC_ROSTER then Sync:ReceiveRoster(msg, sender) end
    end
end)
