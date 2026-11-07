local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

-- Shared server/instance/map references receive short estimated layer names.
-- NPC ZoneUID and spawn GUIDs are client-local and never enter these keys.
-- Relaying a row never renews its observation time or changes its claim owner.
local Registry = {}
iRC.LayerRegistry = Registry

local MAX_ROWS, ROW_LIFETIME, CLOCK_TOLERANCE = 99, 3600, 300
local books, bookCount = {}, 0
local attachedRoot, activeServerScope

local function readable(value)
    return not (iRC.IsSecretValue and iRC:IsSecretValue(value))
end

local function finite(value)
    if not readable(value) then return nil end
    value = tonumber(value)
    if value and value == value and value > -math.huge and value < math.huge then return value end
end

local function now()
    for _, clock in ipairs({ GetServerTime or false, time or false, GetTime or false }) do
        if type(clock) == "function" then
            local ok, value = pcall(clock)
            value = ok and finite(value)
            if value and value >= 0 then return value end
        end
    end
    return 0
end

local function identifier(value, minimum)
    value = finite(value)
    if value and value >= minimum and value <= 2147483647 and value == math.floor(value) then return value end
end

function Registry:MakeKey(serverId, instanceId, mapId)
    serverId, instanceId, mapId = identifier(serverId, 0), identifier(instanceId, 0), identifier(mapId, 1)
    if serverId and instanceId and mapId then return serverId .. "-" .. instanceId .. "-" .. mapId end
end

local function keyParts(value)
    if not readable(value) or type(value) ~= "string" or #value > 32 then return nil end
    local serverId, instanceId, mapId = value:match("^(%d+)%-(%d+)%-(%d+)$")
    serverId, instanceId, mapId = identifier(serverId, 0), identifier(instanceId, 0), identifier(mapId, 1)
    if serverId and instanceId and mapId and Registry:MakeKey(serverId, instanceId, mapId) == value then
        return serverId, instanceId, mapId
    end
end

function Registry:IsKey(value, serverId, mapId)
    if not readable(serverId) or not readable(mapId) then return false end
    local server, _, map = keyParts(value)
    return server ~= nil and (serverId == nil or server == serverId) and (mapId == nil or map == mapId)
end

local function scope(serverId, mapId)
    serverId, mapId = identifier(serverId, 0), identifier(mapId, 1)
    -- Number all server/instance references together within the same zone.
    if serverId and mapId then return tostring(mapId) end
end

local function ownerKey(value)
    if not readable(value) or type(value) ~= "string" or #value > 128 or value:find("[%c]") then return nil end
    value = value:match("^%s*(.-)%s*$"):gsub("%s+", " "):lower()
    if value ~= "" then return value end
end

local function validRow(row, clock)
    if not readable(row) or type(row) ~= "table" then return nil end
    local id = row.identityKey
    local preferred = identifier(row.preferredNumber, 1)
    local owner = ownerKey(row.owner)
    local created, observed = finite(row.createdAt), finite(row.observedAt)
    if not Registry:IsKey(id) or not preferred or preferred > MAX_ROWS or not owner or not created or not observed
        or created < 0 or observed < 0 or created > clock + CLOCK_TOLERANCE
        or observed > clock + CLOCK_TOLERANCE or clock - observed > ROW_LIFETIME then return nil end
    return { identityKey = id, preferredNumber = preferred, owner = owner, createdAt = created, observedAt = observed }
end

local function earlierClaim(a, b)
    if a.createdAt ~= b.createdAt then return a.createdAt < b.createdAt end
    if a.owner ~= b.owner then return a.owner < b.owner end
    -- Conflicting copies of the exact same claim must also merge in either order.
    return a.preferredNumber < b.preferredNumber
end

local function priority(a, b)
    if a.createdAt ~= b.createdAt then return a.createdAt < b.createdAt end
    if a.owner ~= b.owner then return a.owner < b.owner end
    return a.identityKey < b.identityKey
end

local function rebuild(book)
    local rows, numbers, used = {}, {}, {}
    for _, row in pairs(book.rows) do rows[#rows + 1] = row end
    if #rows > MAX_ROWS then
        table.sort(rows, function(a, b)
            if a.observedAt ~= b.observedAt then return a.observedAt > b.observedAt end
            return priority(a, b)
        end)
        for index = MAX_ROWS + 1, #rows do book.rows[rows[index].identityKey] = nil end
        for index = #rows, MAX_ROWS + 1, -1 do rows[index] = nil end
    end
    table.sort(rows, priority)
    book.nextExpiry = nil
    for _, row in ipairs(rows) do
        local number = row.preferredNumber
        if used[number] then
            number = 1
            while used[number] do number = number + 1 end
        end
        numbers[row.identityKey], used[number] = number, true
        local expiresAt = row.observedAt + ROW_LIFETIME
        if not book.nextExpiry or expiresAt < book.nextExpiry then book.nextExpiry = expiresAt end
    end
    book.numbers = numbers
    book.revision = book.revision + 1
end

local function getBook(serverId, mapId, create)
    if iRC.GetGuildDirectoryScope then
        local serverScope = iRC:GetGuildDirectoryScope()
        if not serverScope then return nil end
        if serverScope ~= activeServerScope then
            if attachedRoot then Registry:AttachStore(attachedRoot)
            else books, bookCount, activeServerScope = {}, 0, serverScope end
        end
    end
    local key = scope(serverId, mapId)
    if not key then return nil end
    local book = books[key]
    if not book and create then
        if bookCount >= 128 then
            local oldest, oldestAt
            for oldKey, oldBook in pairs(books) do
                if not oldestAt or (oldBook.usedAt or 0) < oldestAt then oldest, oldestAt = oldKey, oldBook.usedAt or 0 end
            end
            if oldest then books[oldest] = nil; bookCount = bookCount - 1 end
        end
        book = { rows = {}, numbers = {}, revision = 0 }
        books[key] = book
        bookCount = bookCount + 1
    end
    local clock = now()
    if book then book.usedAt = clock end
    if book and book.nextExpiry and clock > book.nextExpiry then
        for id, row in pairs(book.rows) do
            if clock - row.observedAt > ROW_LIFETIME then book.rows[id] = nil end
        end
        rebuild(book)
    end
    return book, clock
end

local function copyRow(row, number)
    return { identityKey = row.identityKey, preferredNumber = row.preferredNumber, owner = row.owner,
        createdAt = row.createdAt, observedAt = row.observedAt, number = number }
end

function Registry:GetNumber(identityKey, serverId, mapId)
    -- A zone book can contain several servers. Replies carry the requesting
    -- server as context, while each row retains its own complete identity.
    if not self:IsKey(identityKey, nil, mapId) then return nil end
    local book = getBook(serverId, mapId)
    return identityKey and book and book.numbers[identityKey] or nil
end

function Registry:Claim(identityKey, serverId, mapId, preferredNumber, owner, createdAt, observedAt)
    if not self:IsKey(identityKey, serverId, mapId) then return nil end
    local clock = now()
    local book = getBook(serverId, mapId, true)
    if not book then return nil end
    if preferredNumber == nil then
        local used = {}
        for _, number in pairs(book.numbers) do used[number] = true end
        preferredNumber = 1
        while used[preferredNumber] and preferredNumber <= MAX_ROWS do preferredNumber = preferredNumber + 1 end
        if preferredNumber > MAX_ROWS then preferredNumber = 1 end
    end
    local incoming = validRow({ identityKey = identityKey, preferredNumber = preferredNumber, owner = owner,
        createdAt = createdAt == nil and clock or createdAt, observedAt = observedAt == nil and clock or observedAt }, clock)
    if not incoming then return nil end
    local existing = book.rows[incoming.identityKey]
    if existing then
        if incoming.observedAt > existing.observedAt then
            existing.observedAt = incoming.observedAt
            rebuild(book)
        end
    else
        book.rows[incoming.identityKey] = incoming
        rebuild(book)
    end
    local row = book.rows[incoming.identityKey]
    return row and copyRow(row, book.numbers[incoming.identityKey]) or nil
end

function Registry:ValidateRows(rows, mapId)
    if not readable(rows) or type(rows) ~= "table" or #rows > MAX_ROWS then return false end
    local clock, seen = now(), {}
    for _, row in ipairs(rows) do
        local valid = validRow(row, clock)
        if not valid or not self:IsKey(valid.identityKey, nil, mapId) or seen[valid.identityKey] then return false end
        seen[valid.identityKey] = true
    end
    return true
end

function Registry:Merge(serverId, mapId, rows)
    if not readable(rows) or type(rows) ~= "table" or #rows > MAX_ROWS then return false end
    local book, clock = getBook(serverId, mapId, true)
    if not book then return false end
    local changed = false
    for _, row in ipairs(rows) do
        local incoming = validRow(row, clock)
        if incoming and self:IsKey(incoming.identityKey, nil, mapId) then
            local existing = book.rows[incoming.identityKey]
            if not existing then
                book.rows[incoming.identityKey], changed = incoming, true
            else
                local observedAt = math.max(existing.observedAt, incoming.observedAt)
                if earlierClaim(incoming, existing) then
                    incoming.observedAt = observedAt
                    book.rows[incoming.identityKey], changed = incoming, true
                elseif observedAt > existing.observedAt then
                    existing.observedAt, changed = observedAt, true
                end
            end
        end
    end
    if changed then rebuild(book) end
    return changed
end

function Registry:Export(serverId, mapId)
    local book, rows = getBook(serverId, mapId), {}
    if not book then return rows end
    for id, row in pairs(book.rows) do rows[#rows + 1] = copyRow(row, book.numbers[id]) end
    table.sort(rows, function(a, b) return a.identityKey < b.identityKey end)
    return rows
end

function Registry:GetRevision(serverId, mapId)
    local book = getBook(serverId, mapId)
    return book and book.revision or 0
end

function Registry:AttachStore(store)
    if not readable(store) or type(store) ~= "table" then return false end
    if iRC.GetGuildDirectoryScope then
        attachedRoot = store
        local serverScope = iRC:GetGuildDirectoryScope()
        if not serverScope then return false end
        store.layerRulesetBooks = store.layerRulesetBooks or {}
        store.layerRulesetBooks[serverScope] = store.layerRulesetBooks[serverScope] or {}
        store = store.layerRulesetBooks[serverScope]
        if activeServerScope ~= serverScope then
            books, bookCount, activeServerScope = {}, 0, serverScope
        end
        -- Older unlabelled books remain saved, but cannot be attributed to
        -- the current server safely. New claims stay in their own ruleset.
    end
    local saved = store.worldNumberBooks
    if saved == books then return true end
    if type(saved) == "table" and readable(saved) then
        local count = 0
        for savedScope, savedBook in pairs(saved) do
            if count >= 128 then break end
            local mapId = type(savedScope) == "string" and savedScope:match("^(%d+)$")
            if mapId and type(savedBook) == "table" and readable(savedBook)
                and type(savedBook.rows) == "table" and readable(savedBook.rows) then
                local rows = {}
                for _, row in pairs(savedBook.rows) do
                    if #rows >= MAX_ROWS then break end
                    local valid = type(row) == "table" and validRow(row, now())
                    if valid then rows[#rows + 1] = valid end
                end
                self:Merge(0, tonumber(mapId), rows)
                count = count + 1
            end
        end
    end
    store.worldNumberBooks = books
    store.layerNumberBooks = nil
    return true
end
