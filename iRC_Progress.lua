local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

-- Legacy rewards are account wide. The achievement API also reports whether
-- this particular character earned one, which is the only completion we share.
local Progress = {}
iRC.Progress = Progress

local LEGACY_CURRENCY = 4225
local WIRE_VERSION = "2"
local BUCKETS = { "PVE", "PVP" }
local MAX_CHUNK_BYTES = 160
local MAX_PARTS = 64
local MAX_ENTRIES = 1024
local RECEIVE_TIMEOUT = 120
-- Forever's launch raids: Onyxia's Lair (40), Hyjal Summit (20), Barrow Deeps (10).
-- The achievement ID is checked against the live Raids catalog before use.
local RAID_SIZES = { [684] = 40, [62034] = 20, [62035] = 10 }
local pendingSend
local sendSequence = 0
local pendingReceives = {}

-- Honor ranks are reported by WoW as rank IDs. Ask WoW for the displayed
-- rank number so the wire format does not depend on those internal IDs.
function Progress:ReadLocalPVPRank()
    if type(GetPVPLifetimeStats) ~= "function" or type(GetPVPRankInfo) ~= "function" then return nil end
    local ok, _, rankID = pcall(GetPVPLifetimeStats)
    if not ok or rankID == nil or iRC:IsSecretValue(rankID) or type(rankID) ~= "number" then return nil end
    if rankID == 0 then return 0 end
    local infoOK, _, rank = pcall(GetPVPRankInfo, rankID)
    if not infoOK or iRC:IsSecretValue(rank) or type(rank) ~= "number"
        or rank < 0 or rank > 14 or rank % 1 ~= 0 then return nil end
    return rank
end

function Progress:GetPVPRankTitle(rank, faction)
    if type(rank) ~= "number" or rank < 1 or rank > 14 then return nil end
    if type(GetPVPRankInfo) == "function" then
        local factionID = faction == "Alliance" and 1 or faction == "Horde" and 0 or nil
        local ok, name = pcall(GetPVPRankInfo, rank + 4, factionID)
        if ok and not iRC:IsSecretValue(name) and type(name) == "string" and name ~= "" then return name end
    end
    return "Rank " .. rank
end

function Progress:GetRaidSize(id)
    return RAID_SIZES[tonumber(id)]
end

local function categoryBucket(categoryID)
    local visited = {}
    while categoryID and categoryID > 0 and not visited[categoryID] do
        visited[categoryID] = true
        local name, parentID = GetCategoryInfo(categoryID)
        local lower = type(name) == "string" and name:lower() or ""
        if lower:find("player vs. player", 1, true) or lower:find("pvp", 1, true)
            or (type(PVP) == "string" and name == PVP) then return "PVP" end
        if lower:find("dungeon", 1, true) or (type(DUNGEONS) == "string" and name == DUNGEONS) then return end
        if lower:find("raid", 1, true) or (type(RAIDS) == "string" and name == RAIDS) then return "PVE" end
        categoryID = tonumber(parentID)
    end
end

function Progress:ReadLocal()
    local result = { PVE = {}, PVP = {} }
    if not GetCategoryList or not GetCategoryInfo or not GetCategoryNumAchievements
        or not GetAchievementInfo or not C_Traits or not C_Traits.GetTraitCurrencyForAchievement then
        return result
    end
    local seen = {}
    for _, categoryID in ipairs(GetCategoryList() or {}) do
        local bucket = categoryBucket(categoryID)
        if bucket then
            for index = 1, GetCategoryNumAchievements(categoryID) or 0 do
                local id, name, _, _, _, _, _, _, _, _, _, _, earnedByCharacter =
                    GetAchievementInfo(categoryID, index)
                if not iRC:IsSecretValue(id) and not iRC:IsSecretValue(name)
                    and type(id) == "number" and type(name) == "string" and not seen[id] then
                    seen[id] = true
                    local ok, points = pcall(C_Traits.GetTraitCurrencyForAchievement, LEGACY_CURRENCY, id)
                    if ok and not iRC:IsSecretValue(points) and type(points) == "number" and points > 0 then
                        result[bucket][#result[bucket] + 1] = {
                            id = id, name = name, earned = earnedByCharacter == true,
                        }
                    end
                end
            end
        end
    end
    for _, bucket in ipairs(BUCKETS) do
        table.sort(result[bucket], function(a, b) return a.id < b.id end)
    end
    return result
end

local function encode(entries)
    local values = {}
    for _, entry in ipairs(entries or {}) do
        values[#values + 1] = tostring(entry.id) .. (entry.earned and "+" or "-")
    end
    return table.concat(values, ",")
end

local function encodeChunks(entries)
    if #entries > MAX_ENTRIES then return nil end
    local chunks, chunk = {}, ""
    for _, entry in ipairs(entries or {}) do
        local token = tostring(entry.id) .. (entry.earned and "+" or "-")
        if #token > MAX_CHUNK_BYTES then return nil end
        if chunk ~= "" and #chunk + #token + 1 > MAX_CHUNK_BYTES then
            chunks[#chunks + 1], chunk = chunk, ""
        end
        chunk = chunk == "" and token or chunk .. "," .. token
    end
    chunks[#chunks + 1] = chunk
    if #chunks > MAX_PARTS then return nil end
    return chunks
end

local function store(sender, bucket, entries, pvpRank)
    local connection = iRC:GetConnection()
    if not connection then return end
    connection.progressReports = connection.progressReports or {}
    local scope = (iRC.GetGuildDirectoryScope and iRC:GetGuildDirectoryScope()) or ""
    connection.progressReports[scope] = connection.progressReports[scope] or {}
    local key = iRC:NormalizeName(sender)
    local reports = connection.progressReports[scope]
    local report = reports[key] or {}
    report[bucket] = entries
    if bucket == "PVP" then report.pvpRank = pvpRank end
    report.receivedAt = time()
    reports[key] = report
    if iRC.RaceGrid then iRC.RaceGrid:MarkLocalReportDirty() end
    if iRC.MainUI and iRC.MainUI.frame and iRC.MainUI.frame.category == "Progress" then
        iRC.MainUI:RefreshIfShown()
    end
end

function Progress:Send(force)
    if not iRC:IsGuildConnectionActive() then return end
    local catalog = self:ReadLocal()
    local sent = 0
    for _, bucket in ipairs(BUCKETS) do
        local entries = catalog[bucket]
        local rank = bucket == "PVP" and self:ReadLocalPVPRank() or nil
        if #entries > 0 or rank ~= nil then
            local payload = encode(entries)
            local signature = payload .. ":" .. tostring(rank or "")
            if force or self.lastSent == nil or self.lastSent[bucket] ~= signature then
                local chunks = encodeChunks(entries)
                if chunks then
                    sendSequence = sendSequence + 1
                    local transferID = tostring(time()) .. "-" .. tostring(sendSequence)
                    local accepted = true
                    for index, chunk in ipairs(chunks) do
                        local message = table.concat({ "PROGRESS", WIRE_VERSION, bucket,
                            transferID, tostring(index), tostring(#chunks),
                            bucket == "PVP" and rank ~= nil and tostring(rank) or "", chunk }, "\t")
                        if not iRC:SendAddonTraffic(iRC.Prefix, message, "GUILD") then
                            accepted = false
                            break
                        end
                        sent = sent + 1
                    end
                    if accepted then
                        self.lastSent = self.lastSent or {}
                        self.lastSent[bucket] = signature
                    else
                        self:ScheduleSend(30, true)
                    end
                else
                    iRC:DebugMsg("Character Legacy progress is too large to share.", 2)
                end
            end
            store(iRC:GetPlayerName(), bucket, entries, rank)
        end
    end
    if sent > 0 then iRC:DebugMsg("Character Legacy progress shared (" .. sent .. " categories).", 3) end
end

function Progress:ScheduleSend(delay, force)
    if pendingSend then return end
    pendingSend = true
    C_Timer.After(delay or 2, function()
        pendingSend = nil
        Progress:Send(force)
    end)
end

function Progress:Receive(parts, sender, distribution)
    if distribution ~= "GUILD" or parts[2] ~= WIRE_VERSION
        or (parts[3] ~= "PVE" and parts[3] ~= "PVP")
        or not iRC:IsGuildMemberName(sender) then return end
    local transferID = parts[4]
    local index, total = tonumber(parts[5]), tonumber(parts[6])
    if type(transferID) ~= "string" or not transferID:match("^%d+%-%d+$")
        or not index or index < 1 or index % 1 ~= 0
        or not total or total < 1 or total > MAX_PARTS or total % 1 ~= 0
        or index > total then return end
    local rank
    if parts[3] == "PVP" and parts[7] ~= nil and parts[7] ~= "" then
        rank = tonumber(parts[7])
        if not rank or rank < 0 or rank > 14 or rank % 1 ~= 0 then return end
    end
    local chunk = parts[8] or ""
    if #chunk > MAX_CHUNK_BYTES then return end
    local scope = (iRC.GetGuildDirectoryScope and iRC:GetGuildDirectoryScope()) or ""
    local key = scope .. "\031" .. iRC:NormalizeName(sender) .. "\031" .. parts[3]
    local now = time()
    local transfer = pendingReceives[key]
    if not transfer or transfer.id ~= transferID or now - transfer.startedAt > RECEIVE_TIMEOUT then
        transfer = { id = transferID, total = total, rank = rank, startedAt = now,
            chunks = {}, count = 0 }
        pendingReceives[key] = transfer
    end
    if transfer.total ~= total or transfer.rank ~= rank then return end
    if transfer.chunks[index] then
        if transfer.chunks[index] ~= chunk then pendingReceives[key] = nil end
        return
    end
    transfer.chunks[index] = chunk
    transfer.count = transfer.count + 1
    if transfer.count < total then return end
    pendingReceives[key] = nil
    local entries, seen = {}, {}
    for partIndex = 1, total do
        local part = transfer.chunks[partIndex]
        if not part then return end
        for token in part:gmatch("[^,]+") do
            local id, state = token:match("^(%d+)([+%-])$")
            id = tonumber(id)
            if not id or id < 1 or id > 1000000 or seen[id] or #entries >= MAX_ENTRIES then return end
            seen[id] = true
            entries[#entries + 1] = { id = id, earned = state == "+" }
        end
    end
    if #entries == 0 and rank == nil then return end
    store(sender, parts[3], entries, rank)
    iRC:DebugMsg("Character Legacy " .. parts[3] .. " progress received from "
        .. iRC:FormatPlayerName(sender) .. " (" .. #entries .. " challenges).", 3)
end

function Progress:GetReports()
    local connection = iRC:GetConnection()
    local scope = (iRC.GetGuildDirectoryScope and iRC:GetGuildDirectoryScope()) or ""
    return connection and connection.progressReports and connection.progressReports[scope] or {}
end

function Progress:GetReport(name)
    return self:GetReports()[iRC:NormalizeName(name)]
end

-- Count distinct challenges completed by characters currently in this guild.
-- A missing character report stays unknown; it is never counted as a failure.
function Progress:GetGuildSummary(roster)
    local reports = self:GetReports()
    local knownMembers, earned, knownByBucket = 0, { PVE = {}, PVP = {} }, { PVE = 0, PVP = 0 }
    local counted = {}
    local playerRanks = {}
    for _, member in ipairs(roster or {}) do
        local key = iRC:NormalizeName(member.name)
        if key ~= "" and not counted[key] then
            counted[key] = true
            local mainName = iRC.Identity and iRC.Identity:GetMainCharacterName(member.name)
            local playerKey = iRC:NormalizeName(mainName or member.name)
            local report = reports[key]
            if report and (report.PVE or report.PVP) then
                knownMembers = knownMembers + 1
                if type(report.pvpRank) == "number" then
                    playerRanks[playerKey] = math.max(playerRanks[playerKey] or 0, report.pvpRank)
                end
                for _, bucket in ipairs(BUCKETS) do
                    if report[bucket] then knownByBucket[bucket] = knownByBucket[bucket] + 1 end
                    for _, entry in ipairs(report[bucket] or {}) do
                        if entry.earned then
                            earned[bucket][entry.id] = earned[bucket][entry.id] or {}
                            earned[bucket][entry.id][playerKey] = true
                        end
                    end
                end
            end
        end
    end
    if knownMembers == 0 then return nil end
    local catalog = self:ReadLocal()
    local summary = { knownMembers = knownMembers }
    if knownByBucket.PVE > 0 then
        local raids, completed, partial = {}, 0, 0
        for _, entry in ipairs(catalog.PVE) do
            local size = RAID_SIZES[entry.id]
            if size then
                local count = 0
                for _ in pairs(earned.PVE[entry.id] or {}) do count = count + 1 end
                local state = count >= size and "CLEARED" or count >= size / 2 and "YELLOW" or "NONE"
                if state == "CLEARED" then completed = completed + 1
                elseif state == "YELLOW" then partial = partial + 1 end
                raids[#raids + 1] = { id = entry.id, count = count, size = size, state = state }
            end
        end
        if #raids > 0 then summary.PVE = { completed = completed, partial = partial, total = #raids, raids = raids } end
    end
    if knownByBucket.PVP > 0 then
        local completed = 0
        for _, entry in ipairs(catalog.PVP) do
            if earned.PVP[entry.id] then completed = completed + 1 end
        end
        local score, highestRank, rankedMembers, knownRanks = 0, 0, 0, 0
        for _, rank in pairs(playerRanks) do
            knownRanks = knownRanks + 1
            if rank > 0 then rankedMembers = rankedMembers + 1 end
            score = score + rank
            highestRank = math.max(highestRank, rank)
        end
        summary.PVP = { completed = completed, total = #catalog.PVP,
            score = knownRanks > 0 and score or nil,
            highestRank = knownRanks > 0 and highestRank or nil,
            rankedMembers = rankedMembers }
    end
    return (summary.PVE or summary.PVP) and summary or nil
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_GUILD_UPDATE")
events:RegisterEvent("ACHIEVEMENT_EARNED")
events:RegisterEvent("RECEIVED_ACHIEVEMENT_LIST")
events:SetScript("OnEvent", function(_, event, unit)
    if event ~= "PLAYER_GUILD_UPDATE" or unit == "player" then
        Progress:ScheduleSend(event == "PLAYER_LOGIN" and (10 + math.random(0, 30)) or 3,
            event == "PLAYER_LOGIN" or event == "PLAYER_GUILD_UPDATE")
    end
end)
if C_Timer and C_Timer.After then
    C_Timer.After(60, function() Progress:ScheduleSend(math.random(0, 30), true) end)
end
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(1800, function() Progress:ScheduleSend(math.random(0, 60), true) end)
end
