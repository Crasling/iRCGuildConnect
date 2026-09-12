local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local Snapshot = {}
iRC.GuildBankSnapshot = Snapshot
local transfers = {}
local CHUNK_SIZE = 170
local MAX_CHUNKS = 40

function Snapshot:IsNewer(candidate, current)
    if not current then return true end
    local candidateTime, currentTime = tonumber(candidate.savedAt) or 0, tonumber(current.savedAt) or 0
    if candidateTime ~= currentTime then return candidateTime > currentTime end
    return (iRC:NormalizeName(candidate.owner or "") or "") > (iRC:NormalizeName(current.owner or "") or "")
end

function Snapshot:GetLatest(connection)
    local latest
    local count = 0
    for _, snapshot in pairs(connection and connection.guildBankSnapshots or {}) do
        count = count + 1
        if snapshot.guildKey == connection.key and self:IsNewer(snapshot, latest) then latest = snapshot end
    end
    if connection and count > 1 then
        connection.guildBankSnapshots = latest and { [iRC:NormalizeName(latest.owner)] = latest } or {}
    end
    return latest
end

local function checksum(value)
    local a, b = 1, 0
    for index = 1, #value do
        a = (a + value:byte(index)) % 65521
        b = (b + a) % 65521
    end
    return string.format("%08x", b * 65536 + a)
end

local function encode(snapshot)
    local records = {}
    local counts = {}
    local sections = snapshot.items and { snapshot.items } or { snapshot.bank or {}, snapshot.bags or {} }
    for _, entries in ipairs(sections) do
        for _, entry in ipairs(entries) do
            local itemID = tonumber(entry.itemID) or tonumber(tostring(entry.link or ""):match("item:(%d+)"))
            local count = tonumber(entry.count) or 1
            if itemID and itemID > 0 and count >= 1 then counts[itemID] = (counts[itemID] or 0) + count end
        end
    end
    local ids = {}
    for itemID in pairs(counts) do ids[#ids + 1] = itemID end
    table.sort(ids)
    for index, itemID in ipairs(ids) do
        if counts[itemID] > 1000000 then return nil end
        records[#records + 1] = table.concat({ "K", math.floor((index - 1) / 100), ((index - 1) % 100) + 1, itemID, counts[itemID] }, ",")
    end
    return table.concat(records, ";")
end

function Snapshot:Send()
    local saved = iRCCharDB and iRCCharDB.guildBankSnapshot
    if not saved or saved.guildKey ~= iRC:GetGuildKey() or not iRC:IsGuildConnectionActive()
        or not iRC:IsGuildBankSnapshotPublisher(iRC:GetPlayerName()) then return false end
    local latest = self:GetLatest(iRC:GetConnection())
    if latest and self:IsNewer(latest, { savedAt = saved.savedAt, owner = iRC:GetPlayerName() }) then return false end
    local payload = encode(saved)
    if not payload or #payload > CHUNK_SIZE * MAX_CHUNKS then return false end
    local stamp, money = math.floor(tonumber(saved.savedAt) or 0), math.floor(tonumber(saved.money) or 0)
    if stamp <= 0 or money < 0 then return false end
    local bankType = "G"
    local digest = checksum(stamp .. ":" .. money .. ":" .. bankType .. ":" .. payload)
    local total = math.max(1, math.ceil(#payload / CHUNK_SIZE))
    for index = 1, total do
        local chunk = payload:sub((index - 1) * CHUNK_SIZE + 1, index * CHUNK_SIZE)
        local message = table.concat({ "BANK_SNAPSHOT", "2", stamp, money, bankType, index, total, digest, chunk }, "\t")
        if index == 1 or not C_Timer or not C_Timer.After then
            if not iRC:SendAddonTraffic(iRC.Prefix, message, "GUILD") then return false end
        else
            C_Timer.After((index - 1) * 0.08, function()
                if iRC:IsGuildConnectionActive() and iRC:IsGuildBankSnapshotPublisher(iRC:GetPlayerName()) then
                    iRC:SendAddonTraffic(iRC.Prefix, message, "GUILD")
                end
            end)
        end
    end
    return true
end

local function decode(payload)
    local snapshot = { items = {} }
    local byID = {}
    if payload == "" then return snapshot end
    for record in (payload .. ";"):gmatch("(.-);") do
        local section, bag, slot, itemID, count = record:match("^([KBE]),(-?%d+),(%d+),(%d+),(%d+)$")
        bag, slot, itemID, count = tonumber(bag), tonumber(slot), tonumber(itemID), tonumber(count)
        if not section or not bag or bag < -1 or bag > 20 or not slot or slot < 1 or slot > 100
            or not itemID or itemID < 1 or not count or count < 1 or count > 1000000 then return nil end
        if section ~= "E" then
            local item = byID[itemID]
            if not item then
                item = { itemID = itemID, count = 0 }
                byID[itemID] = item
                snapshot.items[#snapshot.items + 1] = item
            end
            item.count = item.count + count
            if item.count > 1000000 or #snapshot.items > 350 then return nil end
        end
    end
    return snapshot
end

function Snapshot:Receive(message, sender)
    local version = message:match("^BANK_SNAPSHOT\t([^\t]*)")
    local stamp, money, bankType, index, total, digest, chunk
    if version == "1" then
        _, stamp, money, index, total, digest, chunk = message:match("^BANK_SNAPSHOT\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
        bankType = "G"
    elseif version == "2" then
        _, stamp, money, bankType, index, total, digest, chunk = message:match("^BANK_SNAPSHOT\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
    end
    stamp, money, index, total = tonumber(stamp), tonumber(money), tonumber(index), tonumber(total)
    if not chunk or (version ~= "1" and version ~= "2") or (bankType ~= "G" and bankType ~= "P")
        or not stamp or stamp < 1 or stamp > time() + 300 or not money or money < 0
        or not index or not total or index < 1 or index > total or total > MAX_CHUNKS
        or not digest or not digest:match("^[0-9a-f]+$") or #digest ~= 8 or #chunk > CHUNK_SIZE then return end
    local connection = iRC:GetConnection()
    if not connection or not iRC:IsGuildBankSnapshotPublisher(sender, connection) then return end
    local key = iRC:NormalizeName(sender)
    local latest = self:GetLatest(connection)
    if latest and self:IsNewer(latest, { savedAt = stamp, owner = sender }) then return end
    local transfer = transfers[key]
    if not transfer or transfer.stamp ~= stamp or transfer.digest ~= digest or transfer.total ~= total
        or transfer.bankType ~= bankType or time() - transfer.startedAt > 60 then
        transfer = { stamp = stamp, money = money, bankType = bankType, version = version, digest = digest, total = total, chunks = {}, startedAt = time() }
        transfers[key] = transfer
    end
    if transfer.money ~= money then return end
    transfer.chunks[index] = chunk
    for part = 1, total do if transfer.chunks[part] == nil then return end end
    transfers[key] = nil
    local payload = table.concat(transfer.chunks)
    local checkInput = version == "1" and (stamp .. ":" .. money .. ":" .. payload)
        or (stamp .. ":" .. money .. ":" .. bankType .. ":" .. payload)
    if checksum(checkInput) ~= digest or not iRC:IsGuildMemberName(sender) then return end
    local snapshot = decode(payload)
    if not snapshot then return end
    snapshot.guildKey, snapshot.owner, snapshot.savedAt, snapshot.receivedAt, snapshot.money = connection.key, sender, stamp, time(), money
    snapshot.bankType = bankType == "P" and "PERSONAL" or "GUILD"
    connection.guildBankSnapshots = { [key] = snapshot }
    if iRC.MainUI and iRC.MainUI.frame and iRC.MainUI.frame.category == "Guild Bank" then
        iRC.MainUI:RefreshIfShown()
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(600, function() Snapshot:Send() end) end
end)
