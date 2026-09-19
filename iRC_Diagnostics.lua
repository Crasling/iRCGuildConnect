local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local Diagnostics = {}
iRC.Diagnostics = Diagnostics

local MAX_LOG_ENTRIES = 500
local MAX_ARGUMENTS = 8
local MAX_ARGUMENT_LENGTH = 255
local SLOW_OPERATION_MS = 25

Diagnostics.enabled = false
Diagnostics.logging = false
Diagnostics.log = nil
Diagnostics.suppressed = nil
Diagnostics.slowOperations = {}

local eventNames = {
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_GUILD_UPDATE",
    "GUILD_ROSTER_UPDATE", "GROUP_ROSTER_UPDATE", "CHAT_MSG_ADDON", "CHAT_MSG_CHANNEL",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LEVEL_UP", "PLAYER_DEAD",
    "PLAYER_ALIVE", "PLAYER_UNGHOST", "UNIT_AURA", "PLAYER_MONEY", "PLAYER_LOGOUT",
    "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "MAIL_SEND_INFO_UPDATE",
    "MAIL_SEND_SUCCESS", "MERCHANT_SHOW", "MERCHANT_CLOSED", "TRADE_SHOW", "TRADE_UPDATE",
    "TRADE_CLOSED", "AUCTION_HOUSE_SHOW", "LOOT_OPENED", "LOOT_CLOSED", "QUEST_TURNED_IN",
    "TIME_PLAYED_MSG", "ZONE_CHANGED_NEW_AREA", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
    "NAME_PLATE_UNIT_ADDED", "GET_ITEM_INFO_RECEIVED", "GLOBAL_MOUSE_DOWN",
}
Diagnostics.eventNames = eventNames

local noisyEvents = { UNIT_AURA = true, GLOBAL_MOUSE_DOWN = true, UPDATE_MOUSEOVER_UNIT = true }
local captureFrame = CreateFrame("Frame")

local function Header()
    return string.format("%s v%s // Client %s // Build %s // TOC %s // Locale %s // Project %s",
        tostring(iRC.Title), tostring(iRC.Version), tostring(iRC.GameVersion), tostring(iRC.GameBuild),
        tostring(iRC.GameTocVersion), tostring(GetLocale and GetLocale() or "?"), tostring(WOW_PROJECT_ID))
end

local function CountEntries(value)
    local count = 0
    if type(value) == "table" then for _ in pairs(value) do count = count + 1 end end
    return count
end

local function SafeText(value)
    local text = tostring(value)
    if #text > MAX_ARGUMENT_LENGTH then text = text:sub(1, MAX_ARGUMENT_LENGTH) .. "..." end
    return text:gsub("|", "||"):gsub("[\r\n]", " ")
end

local function Append(category, ...)
    if not Diagnostics.enabled or not Diagnostics.logging then return end
    if noisyEvents[category] then
        Diagnostics.suppressed[category] = (Diagnostics.suppressed[category] or 0) + 1
        return
    end
    local parts = {}
    for index = 1, math.min(select("#", ...), MAX_ARGUMENTS) do
        parts[#parts + 1] = SafeText(select(index, ...))
    end
    local log = Diagnostics.log
    log[#log + 1] = string.format("%.3f %s(%s)", GetTime(), category, table.concat(parts, ", "))
    if #log > MAX_LOG_ENTRIES then table.remove(log, 1) end
end

captureFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, message, distribution, sender = ...
        if prefix == iRC.Prefix or prefix == "iRCGridV1" or prefix == "iRCIconV1"
            or prefix == "iRCGFRoster" or prefix == "RLAddon" then
            Append("IRC_RECEIVE", prefix, type(message) == "string" and (message:match("^([A-Z][A-Z0-9_]*)") or "other") or "?",
                type(message) == "string" and #message or 0, distribution, sender)
        end
        return
    end
    Append(event, ...)
end)

function Diagnostics:SetEnabled(enabled)
    self.enabled = enabled == true
    if not self.enabled then self:DiscardLog() end
end

function Diagnostics:StartLog()
    if not self.enabled then return false end
    self.log, self.suppressed, self.logging = {}, {}, true
    wipe(self.slowOperations)
    captureFrame:UnregisterAllEvents()
    for _, event in ipairs(eventNames) do
        local valid = not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid(event)
        if valid then pcall(captureFrame.RegisterEvent, captureFrame, event) end
    end
    return true
end

function Diagnostics:StopLog()
    self.logging = false
    captureFrame:UnregisterAllEvents()
end

function Diagnostics:DiscardLog()
    self:StopLog()
    self.log, self.suppressed = nil, nil
    wipe(self.slowOperations)
end

function Diagnostics:Trace(category, ...)
    Append("IRC_" .. tostring(category or "TRACE"), ...)
end

function Diagnostics:RecordSlowOperation(label, elapsed)
    if not self.enabled or elapsed < SLOW_OPERATION_MS then return end
    local rows = self.slowOperations
    rows[#rows + 1] = { at = GetTime(), label = tostring(label), ms = elapsed }
    if #rows > 100 then table.remove(rows, 1) end
    self:Trace("SLOW", label, string.format("%.2fms", elapsed))
end

function Diagnostics:BuildLogReport()
    local lines = { Header(), "", "-- Event and sync trace --" }
    for _, entry in ipairs(self.log or {}) do lines[#lines + 1] = entry end
    if not self.log or #self.log == 0 then lines[#lines + 1] = "(no events captured)" end
    local rows = {}
    for event, count in pairs(self.suppressed or {}) do rows[#rows + 1] = { event = event, count = count } end
    table.sort(rows, function(a, b) return a.count > b.count end)
    if #rows > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "-- Suppressed high-frequency events --"
        for _, row in ipairs(rows) do lines[#lines + 1] = string.format("%s x%d", row.event, row.count) end
    end
    return table.concat(lines, "\n")
end

function Diagnostics:BuildEventReport()
    local lines, failures = { Header(), "" }, 0
    local probe = CreateFrame("Frame")
    for _, event in ipairs(eventNames) do
        local validity = "n/a"
        if C_EventUtils and C_EventUtils.IsEventValid then validity = C_EventUtils.IsEventValid(event) and "valid" or "INVALID" end
        local ok = pcall(probe.RegisterEvent, probe, event)
        if ok then probe:UnregisterEvent(event) else failures = failures + 1 end
        lines[#lines + 1] = string.format("[%s] %s (IsEventValid: %s)", ok and "PASS" or "FAIL", event, validity)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = failures == 0 and "All iRC events register on this client."
        or string.format("%d event(s) failed to register.", failures)
    return table.concat(lines, "\n")
end

local apiChecks = {
    { "C_AddOns.GetAddOnInfo", function() return C_AddOns and type(C_AddOns.GetAddOnInfo) == "function" end },
    { "C_ChatInfo.SendAddonMessage", function() return C_ChatInfo and type(C_ChatInfo.SendAddonMessage) == "function" end },
    { "C_ChatInfo.RegisterAddonMessagePrefix", function() return C_ChatInfo and type(C_ChatInfo.RegisterAddonMessagePrefix) == "function" end },
    { "C_EventUtils.IsEventValid", function() return C_EventUtils and type(C_EventUtils.IsEventValid) == "function" end },
    { "C_GuildInfo.GuildRoster", function() return C_GuildInfo and type(C_GuildInfo.GuildRoster) == "function" end },
    { "C_Map.GetBestMapForUnit", function() return C_Map and type(C_Map.GetBestMapForUnit) == "function" end },
    { "C_Map.GetPlayerMapPosition", function() return C_Map and type(C_Map.GetPlayerMapPosition) == "function" end },
    { "C_Container.GetContainerNumSlots", function() return C_Container and type(C_Container.GetContainerNumSlots) == "function" end },
    { "C_Container.GetContainerItemInfo", function() return C_Container and type(C_Container.GetContainerItemInfo) == "function" end },
    { "C_Item.GetItemInfo", function() return C_Item and type(C_Item.GetItemInfo) == "function" end },
    { "C_GameRules.IsGameRuleActive", function() return C_GameRules and type(C_GameRules.IsGameRuleActive) == "function" end },
    { "Settings.RegisterCanvasLayoutCategory", function() return Settings and type(Settings.RegisterCanvasLayoutCategory) == "function" end },
    { "debugprofilestop", function() return type(debugprofilestop) == "function" end },
    { "GetGuildRosterInfo", function() return type(GetGuildRosterInfo) == "function" end },
    { "GetNumGuildMembers", function() return type(GetNumGuildMembers) == "function" end },
    { "UnitName", function() return type(UnitName) == "function" end },
}

function Diagnostics:BuildApiReport()
    local lines = { Header(), "" }
    for _, check in ipairs(apiChecks) do
        local ok, result = pcall(check[2])
        lines[#lines + 1] = string.format("[%s] %s", ok and result and "PASS" or "FAIL", check[1])
    end
    return table.concat(lines, "\n")
end

function Diagnostics:BuildHealthReport()
    local connection = iRC:GetConnection()
    local incoming, outgoing = iRC:GetTrafficBytesLastMinute()
    local queue = iRC.GetPerformanceQueueStatus and iRC:GetPerformanceQueueStatus() or {}
    local lines = { Header(), "", "-- Identity --",
        "Player: " .. tostring(iRC:GetPlayerName()),
        "Guild key: " .. tostring(iRC:GetGuildKey()),
        "Connection active: " .. tostring(iRC:IsGuildConnectionActive()),
        "Guild Master: " .. tostring(iRC:IsGuildMaster()),
        "Hardcore ruleset: " .. tostring(iRC:IsOfficialHardcoreRealm()),
        "", "-- Traffic --",
        string.format("Last 60 seconds: %d incoming / %d outgoing bytes", incoming, outgoing),
        string.format("Queues: %d incoming / %d outgoing", queue.incoming or 0, queue.outgoing or 0),
    }
    if connection then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "-- Ruleset --"
        lines[#lines + 1] = "Guild: " .. tostring(connection.guildName)
        lines[#lines + 1] = "Timestamp: " .. tostring(connection.rulesTimestampHex)
        lines[#lines + 1] = "Fingerprint: " .. tostring(connection.receivedRulesChecksum)
        lines[#lines + 1] = "Created by: " .. tostring(connection.rulesTimestampSource)
        lines[#lines + 1] = "Relayed by: " .. tostring(connection.rulesRelayedBy)
        lines[#lines + 1] = "Received at: " .. tostring(connection.rulesReceivedAt)
        lines[#lines + 1] = "Profiles: " .. CountEntries(connection.members)
        lines[#lines + 1] = "Compatibility profiles: " .. CountEntries(connection.compatibilityMembers)
    end
    return table.concat(lines, "\n")
end

function Diagnostics:BuildMemberReport(name)
    name = tostring(name or ""):match("^%s*(.-)%s*$")
    local lines = { Header(), "", "-- Member diagnosis --" }
    if name == "" then lines[#lines + 1] = "Enter a guild member name first."; return table.concat(lines, "\n") end
    local profile = iRC:FindConnectionProfile(name)
    local verification = iRC.GetMemberVerification and iRC:GetMemberVerification(name, true, profile) or nil
    local found = iRC.RaceLockedSync and iRC.RaceLockedSync:GetStatus(name) or nil
    lines[#lines + 1] = "Name: " .. name
    lines[#lines + 1] = "Normalized: " .. tostring(iRC:NormalizeName(name))
    lines[#lines + 1] = "Guild roster match: " .. tostring(iRC:IsGuildMemberName(name))
    lines[#lines + 1] = "Profile found: " .. tostring(profile ~= nil)
    lines[#lines + 1] = "Addon version: " .. tostring(profile and profile.addonVersion)
    lines[#lines + 1] = "Last response: " .. tostring(profile and profile.lastSeen)
    lines[#lines + 1] = "Verification: " .. tostring(verification and verification.state) .. " / " .. tostring(verification and verification.label)
    lines[#lines + 1] = "Self-Found: " .. tostring(profile and profile.selfFound)
    lines[#lines + 1] = "Guild-Found verified: " .. tostring(found and found.verified)
    lines[#lines + 1] = "Gold clean: " .. tostring(found and found.clean)
    lines[#lines + 1] = "Status source: " .. tostring(found and (found.source or found.gmSource))
    return table.concat(lines, "\n")
end

function Diagnostics:BuildCacheReport()
    local connections = iRCDB and iRCDB.connections or {}
    local servers = iRCDB and iRCDB.globalRaceGrid and iRCDB.globalRaceGrid.servers or {}
    local reports, samples, profiles, banks, professions = 0, 0, 0, 0, 0
    for _, server in pairs(servers or {}) do
        reports = reports + CountEntries(server.guildReports)
        for _, guildSamples in pairs(server.guildActivity or {}) do samples = samples + CountEntries(guildSamples) end
    end
    for _, connection in pairs(connections or {}) do
        profiles = profiles + CountEntries(connection.members)
        banks = banks + CountEntries(connection.guildBankSnapshots)
        professions = professions + CountEntries(connection.professions or connection.memberProfessions)
    end
    return table.concat({ Header(), "", "-- Local cache inventory --",
        "Connections: " .. CountEntries(connections), "Guild reports: " .. reports,
        "Guild activity samples: " .. samples, "Member profiles: " .. profiles,
        "Guild-bank snapshots: " .. banks, "Profession records: " .. professions,
        "No private item, incident, note, or member contents are included in this report.", }, "\n")
end

function Diagnostics:BuildPerformanceReport()
    local lines = { Header(), "", "-- Traffic hotspots (60 seconds) --" }
    for index, row in ipairs(iRC:GetTrafficHotspots()) do
        if index > 10 then break end
        lines[#lines + 1] = string.format("%s: %d B (%d in / %d out)", row.label, row.bytes, row.incoming, row.outgoing)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "-- Function hotspots (60 seconds) --"
    for index, row in ipairs(iRC:GetFunctionHotspots()) do
        if index > 10 then break end
        lines[#lines + 1] = string.format("%s: %.2f ms / %d calls / avg %.3f ms / peak %.3f ms",
            row.label, row.ms, row.calls, row.calls > 0 and row.ms / row.calls or 0, row.peak or 0)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "-- Slow operations (25 ms+) --"
    for index = math.max(1, #self.slowOperations - 19), #self.slowOperations do
        local row = self.slowOperations[index]
        if row then lines[#lines + 1] = string.format("%.3f %s %.2f ms", row.at, row.label, row.ms) end
    end
    return table.concat(lines, "\n")
end

function Diagnostics:BuildAddOnReport()
    local lines = { Header(), "" }
    local count = C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns() or 0
    for index = 1, count do
        local name, _, _, loadable = C_AddOns.GetAddOnInfo(index)
        local loaded = C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(index)
        if loaded or name == iRC.Name then
            lines[#lines + 1] = string.format("%s v%s [%s]", tostring(name),
                tostring(C_AddOns.GetAddOnMetadata(name, "Version") or "?"),
                loaded and "loaded" or (loadable and "available" or "not loadable"))
        end
    end
    return table.concat(lines, "\n")
end

function Diagnostics:BuildBugReport(memberName)
    return table.concat({ self:BuildHealthReport(), "", self:BuildMemberReport(memberName), "",
        self:BuildCacheReport(), "", self:BuildPerformanceReport(), "", self:BuildApiReport(), "",
        self:BuildEventReport(), "", self:BuildAddOnReport(), "", self:BuildLogReport() }, "\n")
end

function Diagnostics:GetTaintLogState()
    return GetCVar and (tonumber(GetCVar("taintLog")) or 0) or 0
end

function Diagnostics:SetTaintLog(enabled)
    if SetCVar then SetCVar("taintLog", enabled and 2 or 0) end
end
