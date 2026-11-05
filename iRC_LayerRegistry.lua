local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

-- Shared layer claims are merged before assigning the short display numbers.
-- Relaying a row never renews its observation time or changes its claim owner.
local Registry = {}
iRC.LayerRegistry = Registry

local MAX_ROWS, ROW_LIFETIME, CLOCK_TOLERANCE = 99, 3600, 300
local books, bookCount = {}, 0

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
    if value and value >= minimum and value == math.floor(value) then return value end
end

local function scope(serverId, mapId)
    serverId, mapId = identifier(serverId, 0), identifier(mapId, 1)
    if serverId and mapId then return tostring(serverId) .. ":" .. tostring(mapId) end
end

local function ownerKey(value)
    if not readable(value) or type(value) ~= "string" or #value > 128 or value:find("[%c]") then return nil end
    value = value:match("^%s*(.-)%s*$"):gsub("%s+", " "):lower()
    if value ~= "" then return value end
end

local function validRow(row, clock)
    if not readable(row) or type(row) ~= "table" then return nil end
    local id = identifier(row.zoneUID, 1)
    local preferred = identifier(row.preferredNumber, 1)
    local owner = ownerKey(row.owner)
    local created, observed = finite(row.createdAt), finite(row.observedAt)
    if not id or not preferred or preferred > MAX_ROWS or not owner or not created or not observed
        or created < 0 or observed < 0 or created > clock + CLOCK_TOLERANCE
        or observed > clock + CLOCK_TOLERANCE or clock - observed > ROW_LIFETIME then return nil end
    return { zoneUID = id, preferredNumber = preferred, owner = owner, createdAt = created, observedAt = observed }
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
    return a.zoneUID < b.zoneUID
end

local function rebuild(book)
    local rows, numbers, used = {}, {}, {}
    for _, row in pairs(book.rows) do rows[#rows + 1] = row end
    if #rows > MAX_ROWS then
        table.sort(rows, function(a, b)
            if a.observedAt ~= b.observedAt then return a.observedAt > b.observedAt end
            return priority(a, b)
        end)
        for index = MAX_ROWS + 1, #rows do book.rows[rows[index].zoneUID] = nil end
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
        numbers[row.zoneUID], used[number] = number, true
        local expiresAt = row.observedAt + ROW_LIFETIME
        if not book.nextExpiry or expiresAt < book.nextExpiry then book.nextExpiry = expiresAt end
    end
    book.numbers = numbers
    book.revision = book.revision + 1
end

local function getBook(serverId, mapId, create)
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
    return { zoneUID = row.zoneUID, preferredNumber = row.preferredNumber, owner = row.owner,
        createdAt = row.createdAt, observedAt = row.observedAt, number = number }
end

function Registry:GetNumber(zoneUID, serverId, mapId)
    zoneUID = identifier(zoneUID, 1)
    local book = getBook(serverId, mapId)
    return zoneUID and book and book.numbers[zoneUID] or nil
end

function Registry:Claim(zoneUID, serverId, mapId, preferredNumber, owner, createdAt, observedAt)
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
    local incoming = validRow({ zoneUID = zoneUID, preferredNumber = preferredNumber, owner = owner,
        createdAt = createdAt == nil and clock or createdAt, observedAt = observedAt == nil and clock or observedAt }, clock)
    if not incoming then return nil end
    local existing = book.rows[incoming.zoneUID]
    if existing then
        if incoming.observedAt > existing.observedAt then
            existing.observedAt = incoming.observedAt
            rebuild(book)
        end
    else
        book.rows[incoming.zoneUID] = incoming
        rebuild(book)
    end
    local row = book.rows[incoming.zoneUID]
    return row and copyRow(row, book.numbers[incoming.zoneUID]) or nil
end

function Registry:ValidateRows(rows)
    if not readable(rows) or type(rows) ~= "table" or #rows > MAX_ROWS then return false end
    local clock, seen = now(), {}
    for _, row in ipairs(rows) do
        local valid = validRow(row, clock)
        if not valid or seen[valid.zoneUID] then return false end
        seen[valid.zoneUID] = true
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
        if incoming then
            local existing = book.rows[incoming.zoneUID]
            if not existing then
                book.rows[incoming.zoneUID], changed = incoming, true
            else
                local observedAt = math.max(existing.observedAt, incoming.observedAt)
                if earlierClaim(incoming, existing) then
                    incoming.observedAt = observedAt
                    book.rows[incoming.zoneUID], changed = incoming, true
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
    table.sort(rows, function(a, b) return a.zoneUID < b.zoneUID end)
    return rows
end

function Registry:GetRevision(serverId, mapId)
    local book = getBook(serverId, mapId)
    return book and book.revision or 0
end

function Registry:AttachStore(store)
    if not readable(store) or type(store) ~= "table" then return false end
    local saved = store.layerNumberBooks
    if saved == books then return true end
    if type(saved) == "table" and readable(saved) then
        local count = 0
        for savedScope, savedBook in pairs(saved) do
            if count >= 128 then break end
            local serverId, mapId
            if type(savedScope) == "string" then serverId, mapId = savedScope:match("^(%d+):(%d+)$") end
            if serverId and type(savedBook) == "table" and readable(savedBook)
                and type(savedBook.rows) == "table" and readable(savedBook.rows) then
                local rows = {}
                for _, row in pairs(savedBook.rows) do
                    if #rows >= MAX_ROWS then break end
                    local valid = type(row) == "table" and validRow(row, now())
                    if valid then rows[#rows + 1] = valid end
                end
                self:Merge(tonumber(serverId), tonumber(mapId), rows)
                count = count + 1
            end
        end
    end
    store.layerNumberBooks = books
    return true
end
