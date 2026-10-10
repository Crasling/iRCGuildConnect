local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local Recruitment = {}
iRC.Recruitment = Recruitment

local WIRE_VERSION = "2"
local CLASS_ORDER = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
local SCAN_TIMEOUT = 15
local NEXT_SCAN_DELAY = 5
local NEXT_SCAN_SAFETY = 0.25
local MAX_CHAT_MESSAGE_BYTES = 255
local RESERVED_RECRUITMENT_NAME_BYTES = 40
local MAX_RECRUITMENT_WHISPERS = 5
local MAX_RECRUITMENT_MESSAGE_BYTES = MAX_CHAT_MESSAGE_BYTES * MAX_RECRUITMENT_WHISPERS
    + (MAX_RECRUITMENT_WHISPERS - 1) * 2
local WHISPER_SPACING = 0.50
local lastSyncRequestAt = 0
local STATUS_PRIORITY = { CLEAR = 0, CONTACTED = 1, DECLINED = 2, ACCEPTED = 3, BLOCKED = 4, ANTISPAM = 5 }
local VALID_SEARCH_CLASSES = { ALL = true }
for _, classFile in ipairs(CLASS_ORDER) do VALID_SEARCH_CLASSES[classFile] = true end

local function localizedClassName(classFile)
    return LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]
        or classFile:sub(1, 1) .. classFile:sub(2):lower()
end

local function searchClassLabel(classFile)
    return classFile == "ALL" and "All classes" or localizedClassName(classFile)
end

local function searchClassOptions()
    local options = { { value = "ALL", label = "All classes" } }
    for _, classFile in ipairs(CLASS_ORDER) do
        options[#options + 1] = { value = classFile, label = localizedClassName(classFile) }
    end
    table.sort(options, function(a, b)
        if a.value == "ALL" or b.value == "ALL" then
            return a.value == "ALL" and b.value ~= "ALL"
        end
        return a.label < b.label
    end)
    return options
end

local function playerKey(name)
    return iRC:NormalizeName(name)
end

local function clean(value, limit)
    return tostring(value or ""):gsub("[%c]", " "):sub(1, limit)
end

local function truncateUtf8(value, maximumBytes)
    value = tostring(value or "")
    if #value <= maximumBytes then return value end
    local cut, characterStart = maximumBytes, maximumBytes
    while characterStart > 0 do
        local byte = value:byte(characterStart)
        if not byte or byte < 128 or byte >= 192 then break end
        characterStart = characterStart - 1
    end
    local lead = value:byte(characterStart) or 0
    local characterBytes = lead < 128 and 1 or (lead < 224 and 2 or (lead < 240 and 3 or 4))
    if characterStart + characterBytes - 1 > cut then cut = characterStart - 1 end
    return value:sub(1, cut)
end

local function normalizeChatMessage(value)
    local message = tostring(value or ""):gsub("[%c]", " "):match("^%s*(.-)%s*$")
    return truncateUtf8(message, MAX_CHAT_MESSAGE_BYTES)
end

local function truncateRecruitmentTemplate(value)
    value = tostring(value or "")
    local _, placeholders = value:gsub("%%s", "")
    if placeholders == 0 then return truncateUtf8(value, MAX_CHAT_MESSAGE_BYTES) end
    local literalBudget = math.max(0, MAX_CHAT_MESSAGE_BYTES
        - placeholders * RESERVED_RECRUITMENT_NAME_BYTES)
    local parts, startAt = {}, 1
    while true do
        local placeholderAt = value:find("%s", startAt, true)
        local literal = placeholderAt and value:sub(startAt, placeholderAt - 1) or value:sub(startAt)
        literal = truncateUtf8(literal, literalBudget)
        parts[#parts + 1] = literal
        literalBudget = literalBudget - #literal
        if not placeholderAt then break end
        parts[#parts + 1] = "%s"
        startAt = placeholderAt + 2
    end
    return table.concat(parts)
end

local function normalizeRecruitmentWhisper(value)
    local message = tostring(value or ""):gsub("[%c]", " "):match("^%s*(.-)%s*$")
    return truncateRecruitmentTemplate(message)
end

local function getRecruitmentWhispers(value)
    local whispers = {}
    value = tostring(value or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    for line in (value .. "\n"):gmatch("(.-)\n") do
        line = normalizeRecruitmentWhisper(line)
        if line ~= "" then
            whispers[#whispers + 1] = line
            if #whispers >= MAX_RECRUITMENT_WHISPERS then break end
        end
    end
    return whispers
end

local function normalizeRecruitmentMessage(value)
    return table.concat(getRecruitmentWhispers(value), "\n")
end

local function capRecruitmentEditor(value)
    local lines, messageCount = {}, 0
    value = tostring(value or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    local startAt = 1
    while true do
        local newlineAt = value:find("\n", startAt, true)
        local line = newlineAt and value:sub(startAt, newlineAt - 1) or value:sub(startAt)
        line = truncateRecruitmentTemplate(line:gsub("[%c]", " "))
        if line ~= "" then
            messageCount = messageCount + 1
            if messageCount > MAX_RECRUITMENT_WHISPERS then break end
        end
        lines[#lines + 1] = line
        if not newlineAt then break end
        startAt = newlineAt + 1
    end
    return table.concat(lines, "\n")
end

local function limitRecruitmentEditor(value, addVisualSpacing)
    value = capRecruitmentEditor(value)
    if not addVisualSpacing then return value end
    local lines = {}
    for line in (value .. "\n"):gmatch("(.-)\n") do
        if line ~= "" then lines[#lines + 1] = line end
    end
    local limited = table.concat(lines, "\n\n")
    if #lines < MAX_RECRUITMENT_WHISPERS and value:sub(-1) == "\n" then limited = limited .. "\n\n" end
    return limited
end

local function getStore(create)
    local guildKey = iRC:GetGuildKey()
    if not guildKey then return nil end
    iRCDB = type(iRCDB) == "table" and iRCDB or {}
    iRCDB.recruitmentGuilds = type(iRCDB.recruitmentGuilds) == "table" and iRCDB.recruitmentGuilds or {}
    local store = iRCDB.recruitmentGuilds[guildKey]
    if not store and create then
        store = { contacted = {}, blocked = {} }
        iRCDB.recruitmentGuilds[guildKey] = store
    end
    if store then
        store.contacted = type(store.contacted) == "table" and store.contacted or {}
        store.blocked = type(store.blocked) == "table" and store.blocked or {}
    end
    return store
end

local function getSettings()
    iRCCharDB = type(iRCCharDB) == "table" and iRCCharDB or {}
    iRCCharDB.recruitment = type(iRCCharDB.recruitment) == "table" and iRCCharDB.recruitment or {}
    local settings = iRCCharDB.recruitment
    settings.minLevel = math.max(1, math.floor(tonumber(settings.minLevel) or 10))
    settings.maxLevel = math.max(settings.minLevel, math.floor(tonumber(settings.maxLevel) or 15))
    settings.searchClass = VALID_SEARCH_CLASSES[settings.searchClass] and settings.searchClass or "ALL"
    settings.message = normalizeRecruitmentMessage(type(settings.message) == "string" and settings.message
        or "Hi %s, are you looking for a guild? We're a friendly social guild building a community of like-minded players to level, group, and adventure together. Would you like to join us?")
    settings.whispersCollapsed = settings.whispersCollapsed ~= false
    settings.welcomeEnabled = settings.welcomeEnabled == true
    settings.welcomeMessage = normalizeChatMessage(type(settings.welcomeMessage) == "string" and settings.welcomeMessage
        or "Welcome %s to the guild!")
    return settings
end

local function makeButton(parent, width, text)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, 24)
    button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    button:SetBackdropColor(0.075, 0.055, 0.035, 0.98)
    button:SetBackdropBorderColor(0.72, 0.43, 0.08, 1)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.text:SetPoint("CENTER")
    button.text:SetText(text)
    button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    return button
end

local function makeEdit(parent, width, height, multiline)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width, height)
    box:SetAutoFocus(false)
    box:SetMultiLine(multiline == true)
    box:SetFontObject("ChatFontNormal")
    box:SetTextInsets(7, 7, 5, 5)
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    box:SetBackdropColor(0.025, 0.025, 0.025, 0.98)
    box:SetBackdropBorderColor(0.42, 0.31, 0.16, 1)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    if not multiline then box:SetScript("OnEnterPressed", box.ClearFocus) end
    return box
end

local function sendStatus(record, status, target)
    if not record then return false end
    return iRC:SendAddonTraffic(iRC.Prefix, table.concat({ "RECRUIT_STATUS", WIRE_VERSION,
        clean(record.name, 80), status, tostring(math.floor(tonumber(record.timestamp) or time())),
        clean(record.by, 80), clean(record.reason, 60) }, "\t"), target and "WHISPER" or "GUILD", target)
end

function Recruitment:SetStatus(name, status, reason, receivedAt, source, suppressSend)
    local store, key = getStore(true), playerKey(name)
    if not store or key == "" then return false end
    local timestamp = math.floor(tonumber(receivedAt) or time())
    local record = { name = iRC:FormatPlayerName(name), timestamp = timestamp,
        by = iRC:FormatPlayerName(source or iRC:GetPlayerName()), reason = clean(reason, 60) }
    local current = store.contacted[key] or store.blocked[key]
    if receivedAt == nil and current and (tonumber(current.timestamp) or 0) >= timestamp then
        timestamp = (tonumber(current.timestamp) or timestamp) + 1
        record.timestamp = timestamp
    end
    if current and (tonumber(current.timestamp) or 0) > timestamp then return false end
    if current and (tonumber(current.timestamp) or 0) == timestamp then
        local currentPriority = STATUS_PRIORITY[current.status] or 0
        local incomingPriority = STATUS_PRIORITY[status] or 0
        if currentPriority > incomingPriority then return false end
        if currentPriority == incomingPriority
            and playerKey(current.by) <= playerKey(record.by) then return false end
    end
    if status == "BLOCKED" or status == "ANTISPAM" then
        record.status = status
        store.blocked[key], store.contacted[key] = record, nil
    elseif status == "CONTACTED" or status == "ACCEPTED" or status == "DECLINED" then
        record.status = status
        store.contacted[key], store.blocked[key] = record, nil
    elseif status == "CLEAR" then
        store.contacted[key], store.blocked[key] = nil, nil
    else
        return false
    end
    local all = {}
    for key, value in pairs(store.contacted) do all[#all + 1] = { key = key, record = value, list = store.contacted } end
    for key, value in pairs(store.blocked) do all[#all + 1] = { key = key, record = value, list = store.blocked } end
    if #all > 500 then
        table.sort(all, function(a, b) return (tonumber(a.record.timestamp) or 0) < (tonumber(b.record.timestamp) or 0) end)
        for index = 1, #all - 500 do all[index].list[all[index].key] = nil end
    end
    if not suppressSend and iRC:IsGuildConnectionActive() and iRC:HasGuildPermission("recruitment") then
        sendStatus(record, status)
    end
    if status == "ACCEPTED" and iRC.Identity and iRC.Identity.SetGuildJoinInviter then
        iRC.Identity:SetGuildJoinInviter(record.name, record.by)
    end
    if self.panel and self.panel:IsShown() then self:Refresh() end
    return true
end

function Recruitment:GetAcceptedInviter(name)
    local store, key = getStore(false), playerKey(name)
    local record = store and store.contacted and store.contacted[key]
    if not record or record.status ~= "ACCEPTED" or playerKey(record.by) == "" then return nil end
    return iRC:FormatPlayerName(record.by)
end

function Recruitment:ReceiveSync(parts, sender)
    if parts[2] ~= WIRE_VERSION or not iRC:IsGuildConnectionActive()
        or not iRC:GuildMemberHasPermission(sender, "recruitment") then return false end
    if parts[1] == "RECRUIT_REQUEST" then
        -- Only the elected guild broadcaster answers. This prevents every
        -- authorized recruiter from sending the same history at once.
        if not iRC:HasGuildPermission("recruitment") or not iRC:IsRulesetBroadcaster() then return false end
        local records = {}
        local store = getStore(false)
        for _, record in pairs(store and store.contacted or {}) do
            records[#records + 1] = { record = record, status = record.status or "CONTACTED" }
        end
        for _, record in pairs(store and store.blocked or {}) do records[#records + 1] = { record = record, status = record.status or "BLOCKED" } end
        table.sort(records, function(a, b) return (tonumber(a.record.timestamp) or 0) > (tonumber(b.record.timestamp) or 0) end)
        for index = 1, math.min(100, #records) do
            local entry = records[index]
            local responseRecord, responseStatus, responseTarget = entry.record, entry.status, sender
            C_Timer.After((index - 1) * 0.10, function()
                if iRC:IsGuildMemberName(responseTarget) then
                    sendStatus(responseRecord, responseStatus, responseTarget)
                end
            end)
        end
        return true
    end
    if parts[1] ~= "RECRUIT_STATUS" then return false end
    local name, status, timestamp = clean(parts[3], 80), parts[4], tonumber(parts[5])
    local source, reason, now = clean(parts[6], 80), clean(parts[7], 60), time()
    if name == "" or not timestamp or timestamp < now - 180 * 86400 or timestamp > now + 300
        or (status ~= "CONTACTED" and status ~= "ACCEPTED" and status ~= "DECLINED"
            and status ~= "BLOCKED" and status ~= "ANTISPAM" and status ~= "CLEAR") then
        return false
    end
    return self:SetStatus(name, status, reason, timestamp, source ~= "" and source or sender, true)
end

function Recruitment:RequestSync()
    if not iRC:IsGuildConnectionActive() or not iRC:HasGuildPermission("recruitment")
        or time() - lastSyncRequestAt < 60 then return false end
    lastSyncRequestAt = time()
    return iRC:SendAddonTraffic(iRC.Prefix, table.concat({ "RECRUIT_REQUEST", WIRE_VERSION }, "\t"), "GUILD")
end

local function whoInfo(index)
    local values, ok
    if C_FriendList and type(C_FriendList.GetWhoInfo) == "function" then
        values = { pcall(C_FriendList.GetWhoInfo, index) }
        ok = table.remove(values, 1)
    elseif type(GetWhoInfo) == "function" then
        values = { pcall(GetWhoInfo, index) }
        ok = table.remove(values, 1)
    else
        return nil
    end
    if not ok then return nil end
    if type(values[1]) == "table" then
        local info = values[1]
        values = { info.fullName or info.name or info.playerName,
            info.fullGuildName or info.guildName or info.guild, info.level,
            info.raceStr or info.race, info.classStr or info.class,
            info.area or info.zone, info.filename or info.classFileName }
    end
    for valueIndex = 1, 7 do
        if iRC:IsSecretValue(values[valueIndex]) then values[valueIndex] = nil end
    end
    if type(values[1]) ~= "string" or values[1] == "" then return nil end
    return { name = values[1], guild = values[2], level = values[3], race = values[4],
        class = values[5], zone = values[6], classFile = values[7] }
end

local function whoCount()
    if C_FriendList and type(C_FriendList.GetNumWhoResults) == "function" then
        local ok, count = pcall(C_FriendList.GetNumWhoResults)
        if ok and not iRC:IsSecretValue(count) and type(count) == "number" then return count end
    end
    if type(GetNumWhoResults) == "function" then
        local ok, count = pcall(GetNumWhoResults)
        if ok and not iRC:IsSecretValue(count) and type(count) == "number" then return count end
    end
    return 0
end

function Recruitment:CollectWhoResults()
    if not self.scanActive then return end
    local store = getStore(true)
    for index = 1, whoCount() do
        local info = whoInfo(index)
        if info then
            info.guild = tostring(info.guild or ""):match("^%s*(.-)%s*$")
        end
        local key = info and info.name and playerKey(info.name)
        if key and key ~= "" and info.guild == "" and not self.resultByKey[key]
            and not store.contacted[key] and not store.blocked[key] then
            info.name = iRC:FormatPlayerName(info.name)
            self.resultByKey[key] = info
            self.results[#self.results + 1] = info
        end
    end
    table.sort(self.results, function(a, b)
        local aLevel = type(a.level) == "number" and a.level or 0
        local bLevel = type(b.level) == "number" and b.level or 0
        if aLevel ~= bLevel then return aLevel > bLevel end
        return playerKey(a.name) < playerKey(b.name)
    end)
    self:Refresh()
end

function Recruitment:AdvanceScan(ticket)
    if not self.scanActive or self.scanTicket ~= ticket or self.waitingForWho then return false end
    if self.nextScanAllowedAt and GetTime() < self.nextScanAllowedAt then return false end
    self.nextScanAllowedAt = nil
    self.scanIndex = self.scanIndex + 1
    if self.scanIndex > #self.scanClasses then
        self.scanActive = nil
        self.fullScanComplete = true
        self.newScanConfirmUntil = nil
        if self.panel then
            self.panel.status:SetText("Scan complete (" .. #self.scanClasses .. "/" .. #self.scanClasses
                .. "). 0 scans left - " .. tostring(#self.results) .. " available result(s).")
        end
        self:Refresh()
        return true
    end
    local className = self.scanClasses[self.scanIndex]
    self.retryClassName = nil
    local settings = getSettings()
    local query = tostring(settings.minLevel) .. "-" .. tostring(settings.maxLevel) .. " c-\"" .. className .. "\""
    iRC:DebugMsg("Recruitment scan " .. tostring(self.scanIndex) .. "/" .. tostring(#self.scanClasses)
        .. " started: " .. query, 3)
    if self.panel then self.panel.status:SetText("Scanning " .. className .. " (" .. self.scanIndex .. "/" .. #self.scanClasses .. ")...") end
    local whoAttempt = {}
    self.whoAttempt = whoAttempt
    self.waitingForWho = true
    if C_FriendList and type(C_FriendList.SendWho) == "function" then
        -- SendWho is protected in Forever. This must stay on the direct path
        -- from the recruiter's button click; pcall and timer callbacks taint it.
        C_FriendList.SendWho(query)
    elseif type(SendWho) == "function" then
        SendWho(query)
    else
        self.waitingForWho = nil
        self.whoAttempt = nil
        self.scanActive = nil
        iRC:DebugMsg("Recruitment scan stopped: WHO is unavailable.", 1)
        if self.panel then self.panel.status:SetText("WHO scanning is not available on this client.") end
        self:Refresh()
        return false
    end
    -- A throttle system message may be delivered while SendWho is returning.
    -- Do not arm a timeout after that attempt has already been rejected.
    if not self.scanActive or self.scanTicket ~= ticket
        or self.whoAttempt ~= whoAttempt or not self.waitingForWho then return true end
    C_Timer.After(SCAN_TIMEOUT, function()
        if self.scanActive and self.scanTicket == ticket
            and self.whoAttempt == whoAttempt and self.waitingForWho then
            self:FinishCurrentClassScan(true)
        end
    end)
    self:Refresh()
    return true
end

function Recruitment:FinishCurrentClassScan(timedOut, retryDelay)
    if not self.scanActive then return end
    self.waitingForWho = nil
    self.whoAttempt = nil
    if timedOut then
        local failedClass = self.scanClasses[self.scanIndex]
        self.scanIndex = math.max(0, self.scanIndex - 1)
        self.retryClassName = failedClass
        retryDelay = math.max(0, tonumber(retryDelay) or 0)
        iRC:DebugMsg("Recruitment WHO failed for " .. tostring(failedClass)
            .. (retryDelay > 0 and ("; retry allowed in " .. tostring(retryDelay) .. " seconds.")
                or "; retry allowed now."), 2)
        self.nextScanAllowedAt = retryDelay > 0 and (GetTime() + retryDelay) or nil
        if self.panel then
            self.panel.status:SetText(retryDelay > 0
                and ("WHO throttled. Retry " .. tostring(failedClass) .. " in "
                    .. math.ceil(retryDelay) .. " second" .. (retryDelay > 1 and "s" or "") .. ".")
                or ("No WHO response. Click to retry " .. tostring(failedClass) .. "."))
        end
    elseif self.scanIndex >= #self.scanClasses then
        self.retryClassName = nil
        self.scanActive = nil
        self.fullScanComplete = true
        self.newScanConfirmUntil = nil
        self.nextScanAllowedAt = nil
        iRC:DebugMsg("Recruitment scan complete: " .. tostring(#self.results) .. " available result(s).", 3)
        if self.panel then
            self.panel.status:SetText("Scan complete (" .. #self.scanClasses .. "/" .. #self.scanClasses
                .. "). 0 scans left - " .. tostring(#self.results) .. " available result(s).")
        end
    elseif self.panel then
        self.retryClassName = nil
        -- Give the server a small buffer beyond its displayed five-second
        -- WHO throttle so a click at the boundary is not silently discarded.
        self.nextScanAllowedAt = GetTime() + NEXT_SCAN_DELAY + NEXT_SCAN_SAFETY
        local nextClass = self.scanClasses[self.scanIndex + 1]
        local scansLeft = #self.scanClasses - self.scanIndex
        iRC:DebugMsg("Recruitment WHO completed for " .. tostring(self.scanClasses[self.scanIndex])
            .. "; " .. tostring(scansLeft) .. " scan(s) left.", 3)
        self.panel.status:SetText("Next: " .. tostring(nextClass) .. " in " .. NEXT_SCAN_DELAY
            .. "s (" .. scansLeft .. " left).")
    end
    self:Refresh()
end

function Recruitment:CancelScan()
    if not self.scanActive then return false end
    local totalScans = self.scanClasses and #self.scanClasses or 0
    local completedScans = math.max(0, math.min(totalScans,
        (self.scanIndex or 0) - (self.waitingForWho and 1 or 0)))
    self.scanActive = nil
    self.waitingForWho = nil
    self.whoAttempt = nil
    self.nextScanAllowedAt = nil
    self.retryClassName = nil
    self.newScanConfirmUntil = nil
    self.fullScanComplete = true
    -- Invalidate the timeout belonging to the cancelled WHO request.
    self.scanTicket = {}
    iRC:DebugMsg("Recruitment scan cancelled after " .. tostring(completedScans)
        .. "/" .. tostring(totalScans) .. "; collected results preserved.", 2)
    if self.panel then
        self.panel.status:SetText("Scan cancelled after " .. completedScans .. "/" .. totalScans
            .. ". Collected results are preserved.")
    end
    self:Refresh()
    return true
end

function Recruitment:StartScan()
    if not iRC:IsGuildConnectionActive() or not iRC:HasGuildPermission("recruitment") then return false end
    if iRC:IsLowTrafficMode() then
        if self.panel then self.panel.status:SetText("Recruitment scanning is unavailable during combat.") end
        return false
    end
    if self.scanActive then return self:AdvanceScan(self.scanTicket) end
    local confirmedRestart = false
    if self.fullScanComplete then
        local now = GetTime()
        if not self.newScanConfirmUntil or self.newScanConfirmUntil < now then
            self.newScanConfirmUntil = now + 5
            if self.panel then
                self.panel.status:SetText("Starting over clears these results. Click Confirm New Scan within 5 seconds.")
            end
            self:UpdateScanButton()
            return false
        end
        confirmedRestart = true
    end
    local settings = getSettings()
    settings.minLevel = math.max(1, math.floor(tonumber(self.panel.minLevel:GetText()) or settings.minLevel))
    settings.maxLevel = math.max(settings.minLevel, math.floor(tonumber(self.panel.maxLevel:GetText()) or settings.maxLevel))
    self.panel.minLevel:ClearFocus()
    self.panel.maxLevel:ClearFocus()
    settings.message = normalizeRecruitmentMessage(self.panel.message:GetText())
    self.panel.message:SetText(settings.message)
    if settings.message == "" then
        self.panel.status:SetText("Write the recruitment whisper before scanning.")
        return false
    end
    if confirmedRestart then
        self.fullScanComplete = nil
        self.newScanConfirmUntil = nil
    end
    self.results, self.resultByKey = {}, {}
    if self.panel and self.panel.resultsScroll then self:SetResultsScroll(0) end
    self.scanClasses = {}
    if settings.searchClass == "ALL" then
        for _, classFile in ipairs(CLASS_ORDER) do
            self.scanClasses[#self.scanClasses + 1] = localizedClassName(classFile)
        end
        table.sort(self.scanClasses)
    else
        self.scanClasses[1] = localizedClassName(settings.searchClass)
    end
    self.scanIndex, self.scanActive = 0, true
    self.nextScanAllowedAt = nil
    self.retryClassName = nil
    self.scanTicket = {}
    self:Refresh()
    self:AdvanceScan(self.scanTicket)
    return true
end

function Recruitment:Invite(info)
    if not info or info.historyRecord or info.guild ~= "" or not iRC:HasGuildPermission("recruitment") then return false end
    if iRC:IsLowTrafficMode() then
        if self.panel then self.panel.status:SetText("Recruitment invitations are unavailable during combat.") end
        return false
    end
    local settings = getSettings()
    local message = normalizeRecruitmentMessage(settings.message)
    local whispers = getRecruitmentWhispers(message)
    settings.message = message
    if self.panel and self.panel.message and self.panel.message:GetText() ~= message then
        self.panel.message:SetText(message)
    end
    local whispered = false
    if #whispers > 0 and type(SendChatMessage) == "function" then
        local target = info.name
        local displayName = iRC:FormatPlayerName(target)
        for index, whisper in ipairs(whispers) do
            whisper = normalizeChatMessage(whisper:gsub("%%s", function() return displayName end))
            if index == 1 or not (C_Timer and C_Timer.After) then
                SendChatMessage(whisper, "WHISPER", nil, target)
            else
                local queuedWhisper = whisper
                C_Timer.After((index - 1) * WHISPER_SPACING, function()
                    SendChatMessage(queuedWhisper, "WHISPER", nil, target)
                end)
            end
        end
        whispered = true
    end
    local invited = false
    if C_GuildInfo and type(C_GuildInfo.Invite) == "function" then
        C_GuildInfo.Invite(info.name)
        invited = true
    elseif type(GuildInvite) == "function" then
        GuildInvite(info.name)
        invited = true
    end
    if whispered or invited then
        self.pendingInvites = self.pendingInvites or {}
        if invited then
            -- This local record is the authority for the optional welcome.
            -- Shared Contacted history alone must never make another recruiter
            -- send a duplicate welcome for somebody else's invitation.
            self.pendingInvites[playerKey(info.name)] = { name = info.name, at = GetTime() }
        end
        self:SetStatus(info.name, "CONTACTED", whispered and invited and "Whispered and invited"
            or (whispered and "Whispered" or "Invited"))
        info.localStatus = "Contacted"
        self:Refresh()
        return true
    end
    return false
end

function Recruitment:SetView(view)
    if view ~= "pending" and view ~= "contacted" and view ~= "blocked" then view = "search" end
    self.view = view
    if self.panel and self.panel.resultsScroll then self:SetResultsScroll(0) end
    self:Refresh()
end

function Recruitment:UpdateScanButton()
    local panel = self.panel
    if not panel then return end
    local settings = getSettings()
    local scanActive = self.scanActive == true
    panel.minLevel:SetEnabled(not scanActive)
    panel.maxLevel:SetEnabled(not scanActive)
    panel.minLevel:SetAlpha(scanActive and 0.45 or 1)
    panel.maxLevel:SetAlpha(scanActive and 0.45 or 1)
    if panel.cancelScan then
        panel.cancelScan:SetShown(scanActive and (self.view or "search") == "search")
        panel.status:ClearAllPoints()
        panel.status:SetPoint("LEFT", scanActive and panel.cancelScan or panel.scan, "RIGHT", 12, 0)
        panel.status:SetPoint("RIGHT", panel, "RIGHT", -18, 0)
    end
    if panel.searchSelector then
        if panel.searchSelector.RefreshSelection then
            panel.searchSelector:RefreshSelection(settings.searchClass)
        else
            panel.searchSelector.text:SetText(searchClassLabel(settings.searchClass))
        end
        panel.searchSelector:SetEnabled(not self.scanActive)
        panel.searchSelector:SetAlpha(self.scanActive and 0.45 or 1)
        if self.scanActive and panel.searchSelector.menu then panel.searchSelector.menu:Hide() end
    end
    if self.fullScanComplete then
        local confirmRemaining = self.newScanConfirmUntil
            and math.max(0, math.ceil(self.newScanConfirmUntil - GetTime())) or 0
        if self.newScanConfirmUntil and confirmRemaining <= 0 then
            self.newScanConfirmUntil = nil
            confirmRemaining = 0
            panel.status:SetText("Scan results are preserved. Choose a search and start a new scan when ready.")
        end
        local confirming = confirmRemaining > 0
        panel.scan.text:SetText(confirming and ("Confirm New Scan (" .. confirmRemaining .. ")") or "New Scan")
        panel.scan:SetEnabled(true)
        panel.scan:SetAlpha(1)
        panel.scan:SetBackdropColor(confirming and 0.20 or 0.075, confirming and 0.035 or 0.055,
            confirming and 0.025 or 0.035, 0.98)
        panel.scan:SetBackdropBorderColor(confirming and 0.85 or 0.72, confirming and 0.20 or 0.43,
            confirming and 0.12 or 0.08, 1)
        return
    end
    local nextClass = self.scanActive and self.scanClasses and self.scanClasses[self.scanIndex + 1]
    local totalScans = self.scanClasses and #self.scanClasses
        or (settings.searchClass == "ALL" and #CLASS_ORDER or 1)
    local scansLeft = self.scanActive and math.max(0, totalScans - (self.scanIndex or 0)) or totalScans
    local remaining = self.nextScanAllowedAt and math.max(0, math.ceil(self.nextScanAllowedAt - GetTime())) or 0
    if self.nextScanAllowedAt and remaining <= 0 then
        self.nextScanAllowedAt = nil
        if nextClass then
            panel.status:SetText(self.retryClassName
                and ("Ready to retry " .. tostring(nextClass) .. ".")
                or ("Ready: " .. tostring(nextClass) .. " (" .. scansLeft .. " left)."))
        end
    end
    local disabled = self.waitingForWho or remaining > 0
    panel.scan.text:SetText(self.waitingForWho and ("Scanning " .. self.scanIndex .. "/" .. totalScans)
        or (remaining > 0 and (self.retryClassName
            and ("Retry in " .. remaining .. "s - " .. tostring(self.retryClassName))
            or ("Next in " .. math.min(NEXT_SCAN_DELAY, remaining) .. "s - " .. scansLeft .. " left")))
        or (nextClass and ((self.retryClassName and "Retry " or "Scan ")
            .. nextClass .. " - " .. scansLeft .. " left")
            or (settings.searchClass == "ALL" and ("Start Full Scan - " .. totalScans)
                or ("Scan " .. searchClassLabel(settings.searchClass)))))
    panel.scan:SetEnabled(not disabled)
    panel.scan:SetAlpha(disabled and 0.45 or 1)
    panel.scan:SetBackdropColor(0.075, 0.055, 0.035, 0.98)
    panel.scan:SetBackdropBorderColor(0.72, 0.43, 0.08, 1)
end

function Recruitment:RenderVisibleRows()
    local panel = self.panel
    if not panel or not panel.resultsScroll then return end
    local visible = self.visibleEntries or {}
    local first = math.max(1, math.floor((panel.resultsScroll:GetVerticalScroll() or 0) / 51) + 1)
    for slot, row in ipairs(panel.rows) do
        local entryIndex = first + slot - 1
        local info = visible[entryIndex]
        if info then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", panel.resultsContent, "TOPLEFT", 0, -((entryIndex - 1) * 51))
            row:SetPoint("RIGHT", panel.resultsContent, "RIGHT", 0, 0)
            row.info = info
            row.name:SetText(info.name)
            if info.historyRecord then
                local record = info.historyRecord
                row.name:SetTextColor(1, 0.65, 0.12)
                local recordedAt = tonumber(record.timestamp) and date("%Y-%m-%d %H:%M", record.timestamp)
                    or "Unknown time"
                local detail = recordedAt .. "  -  By " .. tostring(record.by or "Unknown")
                if record.reason and record.reason ~= "" then detail = detail .. "  -  " .. record.reason end
                row.detail:SetText(detail)
                row.status:SetText(info.historyStatus)
                if info.historyStatus == "ACCEPTED" then
                    row.status:SetTextColor(0.30, 1, 0.38)
                elseif info.historyStatus == "DECLINED" then
                    row.status:SetTextColor(1, 0.35, 0.25)
                else
                    row.status:SetTextColor(1, 0.72, 0.20)
                end
                row.invite:Hide()
                row.block:Show()
                row.block.text:SetText("Remove")
                row.block:SetEnabled(true)
                row.block:SetAlpha(1)
            else
                local color = info.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[info.classFile]
                row.name:SetTextColor(color and color.r or 1, color and color.g or 0.65, color and color.b or 0.12)
                local guildText = info.guild ~= "" and ("Guild: " .. info.guild) or "Unguilded"
                row.detail:SetText("Level " .. tostring(info.level or "?") .. " " .. tostring(info.class or "")
                    .. "  -  " .. guildText .. (info.zone and info.zone ~= "" and ("  -  " .. info.zone) or ""))
                row.status:SetText(info.localStatus or (info.guild ~= "" and "GUILDED" or "AVAILABLE"))
                if info.localStatus == "Declined" then
                    row.status:SetTextColor(1, 0.35, 0.25)
                elseif info.localStatus == "Contacted" then
                    row.status:SetTextColor(1, 0.72, 0.20)
                else
                    row.status:SetTextColor(0.35, 0.85, 0.45)
                end
                local available = info.guild == "" and not info.localStatus
                row.invite:Show()
                row.invite:SetEnabled(available)
                row.invite:SetAlpha(available and 1 or 0.35)
                local canUndoBlock = info.localStatus == "Blocked" or info.localStatus == "Anti-Spam"
                local canBlock = not info.localStatus
                row.block:Show()
                row.block.text:SetText(canUndoBlock and "Undo" or "Block")
                row.block:SetEnabled(canBlock or canUndoBlock)
                row.block:SetAlpha((canBlock or canUndoBlock) and 1 or 0.35)
            end
            row:Show()
        else
            row.info = nil
            row:Hide()
        end
    end
end

function Recruitment:SetResultsScroll(offset)
    local panel = self.panel
    local scroll = panel and panel.resultsScroll
    if not scroll then return end
    local target = math.max(0, math.min(scroll:GetVerticalScrollRange(), tonumber(offset) or 0))
    scroll:SetVerticalScroll(target)
    local scrollBar = scroll.ScrollBar
    if scrollBar and scrollBar.SetValue and scrollBar.GetValue
        and math.abs((scrollBar:GetValue() or 0) - target) > 0.01 then
        -- SetVerticalScroll moves the content but does not move the template's
        -- thumb. Keep both values synchronized for mouse-wheel scrolling.
        scrollBar:SetValue(target)
    end
    self:RenderVisibleRows()
end

function Recruitment:Refresh()
    local panel = self.panel
    if not panel then return end
    local store = getStore(true)
    local visible = {}
    local view = self.view or "search"
    if view == "pending" then
        for _, record in pairs(store.contacted) do
            if record.status == nil or record.status == "CONTACTED" then
                visible[#visible + 1] = { name = record.name, historyRecord = record, historyStatus = "PENDING" }
            end
        end
    elseif view == "contacted" then
        for _, record in pairs(store.contacted) do
            local status = record.status == "ACCEPTED" and "ACCEPTED"
                or (record.status == "DECLINED" and "DECLINED" or "PENDING")
            visible[#visible + 1] = { name = record.name, historyRecord = record, historyStatus = status }
        end
    elseif view == "blocked" then
        for _, record in pairs(store.blocked) do
            visible[#visible + 1] = { name = record.name, historyRecord = record,
                historyStatus = record.status == "ANTISPAM" and "ANTI-SPAM" or "BLOCKED" }
        end
    else
        for _, info in ipairs(self.results or {}) do
            local record = store.blocked[playerKey(info.name)] or store.contacted[playerKey(info.name)]
            if tostring(info.guild or "") == "" and (not record or info.localStatus) then
                visible[#visible + 1] = info
            end
        end
    end
    if view ~= "search" then
        table.sort(visible, function(a, b)
            local aTime = tonumber(a.historyRecord and a.historyRecord.timestamp) or 0
            local bTime = tonumber(b.historyRecord and b.historyRecord.timestamp) or 0
            if aTime ~= bTime then return aTime > bTime end
            return playerKey(a.name) < playerKey(b.name)
        end)
    end
    local pendingCount, contactedCount, blockedCount = 0, 0, 0
    for _, record in pairs(store.contacted) do
        contactedCount = contactedCount + 1
        if record.status == nil or record.status == "CONTACTED" then pendingCount = pendingCount + 1 end
    end
    for _ in pairs(store.blocked) do blockedCount = blockedCount + 1 end
    panel.viewTabs.search.text:SetText("Search")
    panel.viewTabs.pending.text:SetText("Pending (" .. pendingCount .. ")")
    panel.viewTabs.contacted.text:SetText("Contacted (" .. contactedCount .. ")")
    panel.viewTabs.blocked.text:SetText("Blocked / Anti-Spam (" .. blockedCount .. ")")
    for tabView, button in pairs(panel.viewTabs) do
        local active = tabView == view
        button:SetBackdropColor(active and 0.20 or 0.075, active and 0.11 or 0.055,
            active and 0.025 or 0.035, 0.98)
        button:SetBackdropBorderColor(active and 1 or 0.42, active and 0.58 or 0.31,
            active and 0.08 or 0.16, 1)
        button.text:SetTextColor(active and 1 or 0.78, active and 0.82 or 0.72, active and 0.15 or 0.62)
    end
    local searchView = view == "search"
    panel.levelLabel:SetShown(searchView)
    panel.minLevel:SetShown(searchView)
    panel.levelDash:SetShown(searchView)
    panel.maxLevel:SetShown(searchView)
    panel.scan:SetShown(searchView)
    panel.status:SetShown(searchView)
    panel.messageLabel:SetShown(searchView)
    panel.messageCollapse:SetShown(searchView)
    panel.searchSelector:SetShown(searchView)
    panel.cancelScan:SetShown(searchView and self.scanActive == true)
    if not searchView then panel.searchSelector.menu:Hide() end
    if panel.RefreshWhisperCollapse then panel:RefreshWhisperCollapse(searchView) end
    panel.welcomeToggle:SetShown(searchView)
    panel.welcomeMessage:SetShown(searchView)
    panel.historySummary:SetShown(not searchView)
    panel.historySummary:SetText(view == "pending"
        and "Shared invitations that have not yet been accepted, declined, or blocked. Remove an entry to allow the character in future searches again."
        or (view == "contacted"
            and "Shared contacted characters and their latest invitation response: Pending, Accepted, or Declined. Remove an entry to allow it in future searches again."
            or "Shared manually blocked and invite-blocking characters. Remove an entry to allow it in future searches again."))
    panel.headerDetails:SetText(searchView and "Details" or "Recruitment history")
    panel.header:ClearAllPoints()
    if searchView then
        panel.header:SetPoint("TOPLEFT", panel.welcomeToggle, "BOTTOMLEFT", 3, -12)
    else
        panel.header:SetPoint("TOPLEFT", panel.historySummary, "BOTTOMLEFT", 3, -14)
    end
    self:UpdateScanButton()
    self.visibleEntries = visible
    panel.resultsContent:SetHeight(math.max(1, #visible * 51))
    local maximumScroll = math.max(0, #visible * 51 - panel.resultsScroll:GetHeight())
    if panel.resultsScroll:GetVerticalScroll() > maximumScroll then
        self:SetResultsScroll(maximumScroll)
    else
        self:SetResultsScroll(panel.resultsScroll:GetVerticalScroll())
    end
    panel.empty:SetText(view == "pending" and "No pending recruitment invitations."
        or (view == "contacted" and "No contacted characters recorded."
            or (view == "blocked" and "No blocked or Anti-Spam characters recorded."
                or "No recruitment results yet.")))
    panel.empty:SetShown(#visible == 0 and (view ~= "search" or not self.scanActive))
end

function Recruitment:Create(parent)
    if self.panel then return self.panel end
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    panel:SetFrameLevel(parent:GetFrameLevel() + 5)
    panel:EnableMouse(true)
    panel.background = panel:CreateTexture(nil, "BACKGROUND")
    panel.background:SetAllPoints()
    panel.background:SetColorTexture(0.006, 0.006, 0.006, 1)

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 18, -14)
    panel.title:SetText("Recruitment")
    panel.title:SetTextColor(1, 0.82, 0)
    panel.viewTabs = {}
    panel.viewTabs.blocked = makeButton(panel, 170, "Blocked / Anti-Spam")
    panel.viewTabs.blocked:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -18, -8)
    panel.viewTabs.contacted = makeButton(panel, 125, "Contacted")
    panel.viewTabs.contacted:SetPoint("RIGHT", panel.viewTabs.blocked, "LEFT", -6, 0)
    panel.viewTabs.pending = makeButton(panel, 105, "Pending")
    panel.viewTabs.pending:SetPoint("RIGHT", panel.viewTabs.contacted, "LEFT", -6, 0)
    panel.viewTabs.search = makeButton(panel, 82, "Search")
    panel.viewTabs.search:SetPoint("RIGHT", panel.viewTabs.pending, "LEFT", -6, 0)
    for view, button in pairs(panel.viewTabs) do
        local selectedView = view
        button:SetScript("OnClick", function() Recruitment:SetView(selectedView) end)
    end
    panel.help = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.help:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -5)
    panel.help:SetPoint("RIGHT", panel, "RIGHT", -18, 0)
    panel.help:SetJustifyH("LEFT")
    panel.help:SetText("Choose all classes or one class for the selected level range. WoW requires each WHO search to be initiated by you. Contacted and blocked players are shared and excluded from later scans.")

    local minLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    minLabel:SetPoint("TOPLEFT", panel.help, "BOTTOMLEFT", 0, -14)
    minLabel:SetText("Levels")
    panel.levelLabel = minLabel
    panel.minLevel = makeEdit(panel, 45, 24)
    panel.minLevel:SetPoint("LEFT", minLabel, "RIGHT", 8, 0)
    local dash = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dash:SetPoint("LEFT", panel.minLevel, "RIGHT", 5, 0)
    dash:SetText("-")
    panel.levelDash = dash
    panel.maxLevel = makeEdit(panel, 45, 24)
    panel.maxLevel:SetPoint("LEFT", dash, "RIGHT", 5, 0)
    panel.searchSelector = makeButton(panel, 145, "All classes")
    panel.searchSelector:SetPoint("LEFT", panel.maxLevel, "RIGHT", 10, 0)
    panel.searchSelector.text:ClearAllPoints()
    panel.searchSelector.text:SetPoint("LEFT", 9, 0)
    panel.searchSelector.text:SetPoint("RIGHT", -25, 0)
    panel.searchSelector.text:SetJustifyH("LEFT")
    panel.searchSelector.arrow = panel.searchSelector:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.searchSelector.arrow:SetPoint("RIGHT", -9, 0)
    panel.searchSelector.arrow:SetText("v")
    panel.searchSelector.menu = CreateFrame("Frame", nil, panel.searchSelector, "BackdropTemplate")
    panel.searchSelector.menu:SetPoint("TOPLEFT", panel.searchSelector, "BOTTOMLEFT", 0, -2)
    panel.searchSelector.menu:SetPoint("TOPRIGHT", panel.searchSelector, "BOTTOMRIGHT", 0, -2)
    panel.searchSelector.menu:SetFrameStrata("FULLSCREEN_DIALOG")
    panel.searchSelector.menu:SetFrameLevel(panel:GetFrameLevel() + 30)
    panel.searchSelector.menu:SetClampedToScreen(true)
    panel.searchSelector.menu:SetToplevel(true)
    panel.searchSelector.menu:EnableMouse(true)
    panel.searchSelector.menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    panel.searchSelector.menu:SetBackdropColor(0.025, 0.022, 0.018, 0.995)
    panel.searchSelector.menu:SetBackdropBorderColor(0.72, 0.43, 0.08, 1)
    panel.searchSelector.menu.buttons = {}
    local classOptions = searchClassOptions()
    panel.searchSelector.menu:SetHeight(#classOptions * 26 + 8)
    for index, option in ipairs(classOptions) do
        local optionButton = makeButton(panel.searchSelector.menu, 100, option.label)
        optionButton:ClearAllPoints()
        optionButton:SetPoint("TOPLEFT", panel.searchSelector.menu, "TOPLEFT", 4, -4 - (index - 1) * 26)
        optionButton:SetPoint("TOPRIGHT", panel.searchSelector.menu, "TOPRIGHT", -4, -4 - (index - 1) * 26)
        optionButton.value = option.value
        optionButton.text:ClearAllPoints()
        optionButton.text:SetPoint("LEFT", 9, 0)
        optionButton.text:SetPoint("RIGHT", -9, 0)
        optionButton.text:SetJustifyH("LEFT")
        optionButton:SetScript("OnClick", function(self)
            if Recruitment.scanActive then return end
            local settings = getSettings()
            settings.searchClass = self.value
            panel.searchSelector.menu:Hide()
            panel.searchSelector.text:SetText(searchClassLabel(self.value))
            if Recruitment.fullScanComplete then
                panel.status:SetText("Scan results are preserved. " .. searchClassLabel(self.value)
                    .. " is selected for the next scan.")
            else
                panel.status:SetText(self.value == "ALL" and "Ready to begin a full 9-class scan."
                    or ("Ready to scan " .. searchClassLabel(self.value) .. "."))
            end
            Recruitment:UpdateScanButton()
        end)
        panel.searchSelector.menu.buttons[index] = optionButton
    end
    function panel.searchSelector:RefreshSelection(selected)
        self.text:SetText(searchClassLabel(selected))
        for _, optionButton in ipairs(self.menu.buttons) do
            local active = optionButton.value == selected
            optionButton:SetBackdropColor(active and 0.12 or 0.075, active and 0.16 or 0.055,
                active and 0.055 or 0.035, 0.98)
            optionButton:SetBackdropBorderColor(active and 0.18 or 0.42, active and 0.78 or 0.31,
                active and 0.28 or 0.16, 1)
            optionButton.text:SetTextColor(active and 0.35 or 1, active and 1 or 1,
                active and 0.45 or 1)
        end
    end
    panel.searchSelector.menu:Hide()
    panel.searchSelector:SetScript("OnClick", function(self)
        if Recruitment.scanActive then return end
        self.menu:SetShown(not self.menu:IsShown())
        if self.menu:IsShown() then self.menu:Raise() end
    end)
    panel.scan = makeButton(panel, 175, "Start Full Scan - 9")
    panel.scan:SetPoint("LEFT", panel.searchSelector, "RIGHT", 8, 0)
    panel.scan:SetScript("OnClick", function() Recruitment:StartScan() end)
    panel.scan:SetScript("OnUpdate", function(self, elapsed)
        if not Recruitment.nextScanAllowedAt and not Recruitment.newScanConfirmUntil then return end
        self.countdownElapsed = (self.countdownElapsed or 0) + elapsed
        if self.countdownElapsed < 0.10 then return end
        self.countdownElapsed = 0
        Recruitment:UpdateScanButton()
    end)
    panel.cancelScan = makeButton(panel, 72, "Cancel")
    panel.cancelScan:SetPoint("LEFT", panel.scan, "RIGHT", 8, 0)
    panel.cancelScan:SetBackdropColor(0.16, 0.035, 0.025, 0.98)
    panel.cancelScan:SetBackdropBorderColor(0.82, 0.20, 0.12, 1)
    panel.cancelScan.text:SetTextColor(1, 0.55, 0.45)
    panel.cancelScan:SetScript("OnClick", function() Recruitment:CancelScan() end)
    panel.cancelScan:Hide()
    panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.status:SetPoint("LEFT", panel.scan, "RIGHT", 12, 0)
    panel.status:SetPoint("RIGHT", panel, "RIGHT", -18, 0)
    panel.status:SetHeight(20)
    panel.status:SetJustifyH("LEFT")
    panel.status:SetJustifyV("MIDDLE")
    panel.status:SetWordWrap(false)
    panel.status:SetTextColor(0.72, 0.72, 0.72)
    panel.status:SetText("Ready to begin a full 9-class scan.")

    local messageHeader = CreateFrame("Frame", nil, panel)
    messageHeader:SetHeight(24)
    messageHeader:SetPoint("TOPLEFT", minLabel, "BOTTOMLEFT", 0, -8)
    messageHeader:SetPoint("RIGHT", panel, "RIGHT", -18, 0)
    local messageLabel = messageHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    messageLabel:SetPoint("LEFT", messageHeader, "LEFT", 0, 0)
    messageLabel:SetText("Recruitment whispers (0/5 - Enter = new - %s = name)")
    panel.messageLabel = messageLabel
    panel.message = makeEdit(panel, 400, 42, true)
    panel.message:SetPoint("TOPLEFT", messageHeader, "BOTTOMLEFT", 0, -5)
    panel.message:SetPoint("RIGHT", panel, "RIGHT", -18, 0)
    panel.message:SetMaxLetters(MAX_RECRUITMENT_MESSAGE_BYTES)
    panel.message:SetScript("OnTextChanged", function(self)
        if self.limitingText then return end
        local text = self:GetText()
        local deleting = self.lastRecruitmentEditorText and #text < #self.lastRecruitmentEditorText
        local limited = limitRecruitmentEditor(text, not deleting)
        if limited ~= text then
            local cursor = self:GetCursorPosition()
            local cursorWasAtEnd = cursor >= #text
            local adjustedCursor = deleting and math.min(cursor, #limited)
                or #limitRecruitmentEditor(text:sub(1, math.max(0, cursor)), true)
            self.limitingText = true
            self:SetText(limited)
            self:SetCursorPosition(cursorWasAtEnd and #limited or math.min(adjustedCursor, #limited))
            self.limitingText = nil
        end
        self.lastRecruitmentEditorText = limited
        local count = #getRecruitmentWhispers(limited)
        messageLabel:SetText("Recruitment whispers (" .. count
            .. "/5 - Enter = new - %s = name)")
        if panel.RefreshWhisperPreview then panel:RefreshWhisperPreview() end
    end)
    panel.messageCollapse = makeButton(messageHeader, 88, "Collapse")
    panel.messageCollapse:SetPoint("RIGHT", messageHeader, "RIGHT", 0, 0)
    messageLabel:SetPoint("RIGHT", panel.messageCollapse, "LEFT", -12, 0)
    messageLabel:SetJustifyH("LEFT")
    panel.messagePreview = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    panel.messagePreview:SetHeight(44)
    panel.messagePreview:SetPoint("TOPLEFT", messageHeader, "BOTTOMLEFT", 0, -5)
    panel.messagePreview:SetPoint("RIGHT", panel, "RIGHT", -18, 0)
    panel.messagePreview:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    panel.messagePreview:SetBackdropColor(0.025, 0.025, 0.025, 0.98)
    panel.messagePreview:SetBackdropBorderColor(0.42, 0.31, 0.16, 1)
    if panel.messagePreview.SetClipsChildren then panel.messagePreview:SetClipsChildren(true) end
    panel.messagePreview.text = panel.messagePreview:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    panel.messagePreview.text:SetPoint("TOPLEFT", 7, -5)
    panel.messagePreview.text:SetPoint("RIGHT", panel.messagePreview, "RIGHT", -7, 0)
    panel.messagePreview.text:SetJustifyH("LEFT")
    panel.messagePreview.text:SetJustifyV("TOP")
    panel.messagePreview.text:SetWordWrap(true)
    panel.messagePreview:Hide()

    panel.welcomeToggle = makeButton(panel, 154, "Guild welcome: Disabled")
    panel.welcomeToggle:SetPoint("TOPLEFT", panel.message, "BOTTOMLEFT", 0, -8)
    panel.welcomeMessage = makeEdit(panel, 400, 24, false)
    panel.welcomeMessage:SetPoint("LEFT", panel.welcomeToggle, "RIGHT", 8, 0)
    panel.welcomeMessage:SetPoint("RIGHT", panel, "RIGHT", -18, 0)
    panel.welcomeMessage:SetMaxLetters(200)

    local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", panel.welcomeToggle, "BOTTOMLEFT", 3, -12)
    header:SetWidth(185)
    header:SetJustifyH("LEFT")
    header:SetText("Character")
    header:SetTextColor(1, 0.67, 0.15)
    panel.header = header
    panel.headerDetails = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.headerDetails:SetPoint("LEFT", panel, "LEFT", 220, 0)
    panel.headerDetails:SetPoint("TOP", header, "TOP", 0, 0)
    panel.headerDetails:SetWidth(390)
    panel.headerDetails:SetJustifyH("LEFT")
    panel.headerDetails:SetText("Details")
    panel.headerDetails:SetTextColor(1, 0.67, 0.15)
    panel.headerStatus = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.headerStatus:SetPoint("RIGHT", panel, "RIGHT", -179, 0)
    panel.headerStatus:SetPoint("TOP", header, "TOP", 0, 0)
    panel.headerStatus:SetWidth(145)
    panel.headerStatus:SetJustifyH("LEFT")
    panel.headerStatus:SetText("Status")
    panel.headerStatus:SetTextColor(1, 0.67, 0.15)
    panel.historySummary = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.historySummary:SetPoint("TOPLEFT", minLabel, "TOPLEFT", 0, 0)
    panel.historySummary:SetPoint("RIGHT", panel, "RIGHT", -18, 0)
    panel.historySummary:SetJustifyH("LEFT")
    panel.historySummary:SetTextColor(0.72, 0.72, 0.72)
    panel.historySummary:Hide()
    panel.resultsScroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    iRC:StyleScrollFrame(panel.resultsScroll)
    panel.resultsScroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -3, -7)
    panel.resultsScroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -31, 18)
    panel.resultsScroll:EnableMouseWheel(true)
    panel.resultsContent = CreateFrame("Frame", nil, panel.resultsScroll)
    panel.resultsContent:SetSize(1, 1)
    panel.resultsScroll:SetScrollChild(panel.resultsContent)
    panel.resultsScroll:SetScript("OnSizeChanged", function(self, width)
        panel.resultsContent:SetWidth(math.max(1, width))
    end)
    panel.resultsScroll:SetScript("OnVerticalScroll", function(self, offset)
        Recruitment:SetResultsScroll(offset)
    end)
    panel.resultsScroll:SetScript("OnMouseWheel", function(self, delta)
        local target = math.max(0, math.min(self:GetVerticalScrollRange(),
            self:GetVerticalScroll() - delta * 153))
        Recruitment:SetResultsScroll(target)
    end)

    panel.rows = {}
    function panel:CreateResultRow()
        local row = CreateFrame("Button", nil, self.resultsContent, "BackdropTemplate")
        row:SetHeight(48)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        row:SetBackdropColor(0.035, 0.031, 0.027, 0.96)
        row:SetBackdropBorderColor(0.25, 0.20, 0.13, 0.9)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        -- Cards are informational. Only the explicit Invite button may send a
        -- whisper or guild invitation, preventing accidental recruitment.
        row:SetScript("OnClick", nil)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("TOPLEFT", 9, -7)
        row.name:SetWidth(185)
        row.name:SetJustifyH("LEFT")
        row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
        row.detail:SetJustifyH("LEFT")
        row.detail:SetWordWrap(false)
        row.detail:SetTextColor(0.65, 0.65, 0.65)
        row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.status:SetWidth(145)
        row.status:SetJustifyH("LEFT")
        row.status:SetTextColor(0.35, 0.85, 0.45)
        row.invite = makeButton(row, 58, "Invite")
        row.invite:SetPoint("RIGHT", row, "RIGHT", -80, 0)
        row.invite:SetScript("OnClick", function() Recruitment:Invite(row.info) end)
        row.block = makeButton(row, 70, "Block")
        row.block:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.status:SetPoint("RIGHT", row.invite, "LEFT", -10, 0)
        row.detail:SetPoint("RIGHT", row.status, "LEFT", -12, 0)
        row.block:SetScript("OnClick", function()
            if row.info then
                if row.info.historyRecord then
                    Recruitment:SetStatus(row.info.name, "CLEAR", "Recruitment history removed")
                elseif row.info.localStatus == "Blocked" or row.info.localStatus == "Anti-Spam" then
                    Recruitment:SetStatus(row.info.name, "CLEAR", "Block removed")
                    row.info.localStatus = nil
                else
                    Recruitment:SetStatus(row.info.name, "BLOCKED", "Skipped by recruiter")
                    row.info.localStatus = "Blocked"
                end
                Recruitment:Refresh()
            end
        end)
        self.rows[#self.rows + 1] = row
        return row
    end
    -- Keep only enough rows for the viewport and reuse them while scrolling.
    for _ = 1, 9 do
        panel:CreateResultRow()
    end
    panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.empty:SetPoint("CENTER", panel.resultsScroll, "CENTER", 0, 0)
    panel.empty:SetText("No recruitment results yet.")
    panel.empty:SetTextColor(0.55, 0.55, 0.55)

    local settings = getSettings()
    panel.minLevel:SetText(tostring(settings.minLevel))
    panel.maxLevel:SetText(tostring(settings.maxLevel))
    panel.status:SetText(settings.searchClass == "ALL" and "Ready to begin a full 9-class scan."
        or ("Ready to scan " .. searchClassLabel(settings.searchClass) .. "."))
    panel.message:SetText(settings.message)
    panel.welcomeMessage:SetText(settings.welcomeMessage)
    function panel:RefreshWhisperPreview()
        local firstWhisper = getRecruitmentWhispers(self.message:GetText())[1]
        self.messagePreview.text:SetText(firstWhisper or "No recruitment whisper configured.")
        self.messagePreview.text:SetTextColor(firstWhisper and 1 or 0.55,
            firstWhisper and 1 or 0.55, firstWhisper and 1 or 0.55)
        self.messagePreview:SetHeight(math.max(34, self.messagePreview.text:GetStringHeight() + 10))
    end
    function panel:RefreshWhisperCollapse(searchVisible)
        local collapsed = settings.whispersCollapsed == true
        self.message:SetShown(searchVisible ~= false and not collapsed)
        self.messagePreview:SetShown(searchVisible ~= false and collapsed)
        self.messageCollapse:SetShown(searchVisible ~= false)
        self.messageCollapse.text:SetText(collapsed and "Edit" or "Collapse")
        self.message:SetBackdropColor(0.018, 0.085, 0.035, 0.98)
        self.message:SetBackdropBorderColor(0.16, 0.78, 0.30, 1)
        self.welcomeToggle:ClearAllPoints()
        self.welcomeToggle:SetPoint("TOPLEFT", collapsed and self.messagePreview or self.message,
            "BOTTOMLEFT", 0, -8)
    end
    panel.messageCollapse:SetScript("OnClick", function()
        settings.whispersCollapsed = not settings.whispersCollapsed
        panel.message:ClearFocus()
        panel:RefreshWhisperCollapse((Recruitment.view or "search") == "search")
        Recruitment:Refresh()
    end)
    panel:RefreshWhisperPreview()
    panel:RefreshWhisperCollapse(true)
    local function refreshWelcomeControls()
        local enabled = settings.welcomeEnabled == true
        panel.welcomeToggle.text:SetText(enabled and "Guild welcome: Enabled" or "Guild welcome: Disabled")
        panel.welcomeToggle:SetBackdropColor(enabled and 0.025 or 0.075,
            enabled and 0.16 or 0.055, enabled and 0.055 or 0.035, 0.98)
        panel.welcomeToggle:SetBackdropBorderColor(enabled and 0.18 or 0.72,
            enabled and 0.78 or 0.43, enabled and 0.28 or 0.08, 1)
        panel.welcomeToggle.text:SetTextColor(enabled and 0.35 or 0.78,
            enabled and 1 or 0.72, enabled and 0.45 or 0.62)
        panel.welcomeMessage:SetEnabled(enabled)
        panel.welcomeMessage:SetAlpha(enabled and 1 or 0.45)
    end
    panel.welcomeToggle:SetScript("OnClick", function()
        settings.welcomeEnabled = not settings.welcomeEnabled
        refreshWelcomeControls()
    end)
    refreshWelcomeControls()
    panel.minLevel:SetScript("OnEditFocusLost", function(self)
        settings.minLevel = math.max(1, math.floor(tonumber(self:GetText()) or settings.minLevel))
        self:SetText(tostring(settings.minLevel))
    end)
    panel.maxLevel:SetScript("OnEditFocusLost", function(self)
        settings.maxLevel = math.max(settings.minLevel, math.floor(tonumber(self:GetText()) or settings.maxLevel))
        self:SetText(tostring(settings.maxLevel))
    end)
    panel.message:SetScript("OnEditFocusLost", function(self)
        settings.message = normalizeRecruitmentMessage(self:GetText())
        self:SetText(settings.message)
    end)
    panel.welcomeMessage:SetScript("OnEditFocusLost", function(self)
        settings.welcomeMessage = normalizeChatMessage(self:GetText())
        self:SetText(settings.welcomeMessage)
    end)
    self.panel = panel
    return panel
end

function Recruitment:Show(parent)
    local panel = self:Create(parent)
    if panel:GetParent() ~= parent then panel:SetParent(parent); panel:SetAllPoints(parent) end
    panel:SetFrameLevel(parent:GetFrameLevel() + 5)
    panel:Show()
    panel.resultsContent:SetWidth(math.max(1, panel.resultsScroll:GetWidth()))
    self:RequestSync()
    self:Refresh()
end

function Recruitment:Hide()
    if self.panel then self.panel:Hide() end
end

local function recruitmentResponse(message)
    if iRC:IsSecretValue(message) or type(message) ~= "string" or message == "" then return end
    local lower = message:lower()
    local candidates, added = {}, {}
    local now = GetTime()
    for key, pending in pairs(Recruitment.pendingInvites or {}) do
        if now - (tonumber(pending.at) or 0) <= 1800 then
            candidates[#candidates + 1], added[key] = pending.name, true
        else
            Recruitment.pendingInvites[key] = nil
        end
    end
    local store = getStore(false)
    local selfKey = playerKey(iRC:GetPlayerName())
    for key, record in pairs(store and store.contacted or {}) do
        if not added[key] and playerKey(record.by) == selfKey then candidates[#candidates + 1] = record.name end
    end
    for _, name in ipairs(candidates) do
        local key = playerKey(name)
        local locallyInvited = Recruitment.pendingInvites and Recruitment.pendingInvites[key] ~= nil
        local nameAppears = lower:find(tostring(name):lower(), 1, true) ~= nil
        local accepted = type(ERR_GUILD_JOIN_S) == "string" and format(ERR_GUILD_JOIN_S, name) == message
            or (nameAppears and lower:find("has joined the guild", 1, true) ~= nil)
        local declined = type(ERR_GUILD_DECLINE_S) == "string" and format(ERR_GUILD_DECLINE_S, name) == message
            or (nameAppears and (lower:find("declines your guild invitation", 1, true) ~= nil
                or lower:find("declined your guild invitation", 1, true) ~= nil))
        local blocked = nameAppears and lower:find("guild invite", 1, true)
            and (lower:find("block", 1, true) or lower:find("not accepting", 1, true)
                or lower:find("anti%-spam"))
        local status, reason, label
        if accepted then
            status, reason, label = "ACCEPTED", "Accepted invitation and joined the guild", "Accepted"
        elseif declined then
            status, reason, label = "DECLINED", "Declined guild invitation", "Declined"
        elseif blocked then
            status, reason, label = "ANTISPAM", "Guild invitations blocked", "Anti-Spam"
        end
        if status then
            local current = store and store.contacted and store.contacted[key]
            Recruitment:SetStatus(name, status, reason, nil, current and current.by or nil)
            if accepted and locallyInvited and type(SendChatMessage) == "function" then
                local settings = getSettings()
                local welcome = settings.welcomeEnabled and settings.welcomeMessage or ""
                welcome = normalizeChatMessage(welcome)
                if welcome ~= "" then
                    local displayName = iRC:FormatPlayerName(name)
                    welcome = normalizeChatMessage(welcome:gsub("%%s", function() return displayName end))
                    SendChatMessage(welcome, "GUILD")
                end
            end
            if Recruitment.pendingInvites then Recruitment.pendingInvites[key] = nil end
            for _, info in ipairs(Recruitment.results or {}) do
                if playerKey(info.name) == key then info.localStatus = label end
            end
            Recruitment:Refresh()
            return status
        end
    end
end

local function whoThrottleDelay(message)
    if iRC:IsSecretValue(message) or type(message) ~= "string" then return nil end
    local lower = message:lower()
    if not lower:find("/who", 1, true) or not lower:find("wait", 1, true) then return nil end
    local seconds = tonumber(lower:match("wait%s+(%d+)%s+seconds?"))
    return seconds and math.max(0, seconds) or nil
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("WHO_LIST_UPDATE")
eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
eventFrame:SetScript("OnEvent", function(_, event, message)
    if event == "WHO_LIST_UPDATE" and Recruitment.scanActive and Recruitment.waitingForWho then
        iRC:DebugMsg("Recruitment WHO response received for "
            .. tostring(Recruitment.scanClasses and Recruitment.scanClasses[Recruitment.scanIndex] or "unknown class")
            .. ": " .. tostring(whoCount()) .. " result(s).", 3)
        Recruitment:CollectWhoResults()
        Recruitment:FinishCurrentClassScan(false)
    elseif event == "CHAT_MSG_SYSTEM" then
        local retryDelay = Recruitment.scanActive and Recruitment.waitingForWho
            and whoThrottleDelay(message)
        if retryDelay then
            iRC:DebugMsg("Recruitment WHO throttle detected from the system message; retry in "
                .. tostring(retryDelay) .. " seconds.", 2)
            Recruitment:FinishCurrentClassScan(true, retryDelay)
            return
        end
        recruitmentResponse(message)
    end
end)

