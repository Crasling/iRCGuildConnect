local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local Notes = { Prefix = "iRCNotesV1", Permissions = { "notesView", "notesAdd", "notesManage" } }
iRC.MemberNotes = Notes
-- Each edit is a separate operation. Merging histories never replaces another
-- officer's database, and concurrent changes remain available for review.
local VERSION, MAX_RECORDS, CHUNK_SIZE, MAX_CHUNKS = "1", 10000, 140, 64
local SYNC_INTERVAL = 30 * 60
local peers, transfers, requests = {}, {}, {}
local requestTimes, manifestTimes = {}, {}
local pendingManifests, snapshots, sessionScope = {}, {}, nil
local lastHello, sequence = -math.huge, 0

local function integer(value, minimum, maximum)
    return type(value) == "number" and value == value and value >= minimum
        and value <= maximum and value == math.floor(value)
end

local function hash(value)
    local result = 5381
    for index = 1, #value do result = (result * 33 + value:byte(index)) % 4294967296 end
    return string.format("%08x", result)
end
local sessionID = hash(tostring({}) .. GetTime())

local function hex(value)
    return (value:gsub(".", function(byte) return string.format("%02x", byte:byte()) end))
end

local function unhex(value)
    if #value % 2 ~= 0 or value:find("[^%x]") then return nil end
    return (value:gsub("%x%x", function(pair) return string.char(tonumber(pair, 16)) end))
end

local function split(value, separator)
    local values = {}
    for part in (value .. separator):gmatch("(.-)" .. separator) do values[#values + 1] = part end
    return values
end

local function resetSession(scope)
    if sessionScope == scope then return end
    peers, transfers, requests, requestTimes, manifestTimes, pendingManifests, snapshots = {}, {}, {}, {}, {}, {}, {}
    lastHello, sessionScope = -math.huge, scope
end

function Notes:GetScope()
    if not iRC:IsGuildConnectionActive() or not iRC:GetConnection() then resetSession(nil); return nil end
    local server = iRC:GetGuildDirectoryScope()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName and GetRealmName()
    local guild = iRC:GetGuildKey()
    if iRC:HasSecretValues(server, realm, guild) or type(server) ~= "string" or server == ""
        or type(realm) ~= "string" or realm == "" or type(guild) ~= "string" or guild == "" then resetSession(nil); return nil end
    local scope = server .. ":" .. realm:lower() .. ":" .. guild
    resetSession(scope)
    return scope
end

function Notes:CanView()
    return self:GetScope() ~= nil and iRC:HasGuildPermission("notesView") == true
end

function Notes:Can(permission)
    return self:CanView() and iRC:HasGuildPermission(permission) == true
end

function Notes:GetStore(create)
    if not self:CanView() then return nil end
    local scope, connection = self:GetScope(), iRC:GetConnection()
    if not connection.memberNotes and create then connection.memberNotes = {} end
    local stores = connection.memberNotes
    if not stores then return nil end
    if not stores[scope] and create then stores[scope] = { operations = {}, sequence = 0, count = 0 } end
    return stores[scope]
end

local function text(value, maximum, multiline)
    if iRC:IsSecretValue(value) or type(value) ~= "string" or #value > maximum then return nil end
    value = value:gsub("\r\n", "\n"):gsub("\r", "\n")
    local invalid = multiline and "[%z\1-\8\11\12\14-\31\127]" or "[%c]"
    if value:find(invalid) then return nil end
    return value:match("^%s*(.-)%s*$")
end

local function validID(value)
    return type(value) == "string" and #value > 0 and #value <= 48 and not value:find("[^%w%-]")
end

local actions = { CREATE = true, EDIT = true, RESOLVE = true, REVOKE = true, DELETE = true }
local statuses = { ACTIVE = true, RESOLVED = true, REVOKED = true, DELETED = true }
local fields = { "id", "noteID", "parent", "revision", "member", "title", "body", "strike", "status",
    "author", "at", "createdBy", "createdAt", "reason", "action", "scope", "reference" }

local function encode(operation)
    local values = {}
    for index, key in ipairs(fields) do
        local value = operation[key]
        values[index] = hex(value == nil and "" or tostring(value))
    end
    return table.concat(values, ":")
end

local function decode(payload)
    local values = split(payload, ":")
    if #values ~= #fields then return nil end
    local operation = {}
    for index, key in ipairs(fields) do
        operation[key] = unhex(values[index])
        if operation[key] == nil then return nil end
    end
    for _, key in ipairs({ "revision", "at", "createdAt" }) do operation[key] = tonumber(operation[key]) end
    if operation.strike ~= "true" and operation.strike ~= "false" then return nil end
    operation.strike = operation.strike == "true"
    return operation
end

local function validOperation(operation, scope)
    if type(operation) ~= "table" or operation.scope ~= scope or not validID(operation.id)
        or not validID(operation.noteID) or not integer(operation.revision, 1, MAX_RECORDS)
        or not actions[operation.action] or not statuses[operation.status]
        or not integer(operation.at, 1, time() + 300)
        or not integer(operation.createdAt, 1, operation.at)
        or type(operation.strike) ~= "boolean" then return false end
    for _, key in ipairs({ "member", "author", "createdBy" }) do
        if not text(operation[key], 120) or operation[key] == "" then return false end
    end
    if not text(operation.title, 120) or operation.title == "" or not text(operation.body, 2048, true)
        or not text(operation.reason, 240, true) or not text(operation.reference, 120) then return false end
    if operation.action == "CREATE" then
        return operation.id == operation.noteID and operation.parent == "" and operation.revision == 1
            and operation.status == "ACTIVE" and operation.author == operation.createdBy
            and operation.at == operation.createdAt
    end
    if not validID(operation.parent) or operation.revision < 2 then return false end
    if operation.action == "DELETE" then return operation.status == "DELETED" and operation.reason ~= "" end
    if operation.action == "RESOLVE" then return operation.strike and operation.status == "RESOLVED" and operation.reason ~= "" end
    if operation.action == "REVOKE" then return operation.strike and operation.status == "REVOKED" and operation.reason ~= "" end
    return operation.status ~= "DELETED" and (operation.strike or operation.status == "ACTIVE")
end

local function newer(a, b)
    if not b then return true end
    if (a.status == "DELETED") ~= (b.status == "DELETED") then return a.status == "DELETED" end
    if a.revision ~= b.revision then return a.revision > b.revision end
    -- A concurrent edit must not undo a removal or a strike decision.
    local priority = { ACTIVE = 0, RESOLVED = 1, REVOKED = 2, DELETED = 3 }
    if priority[a.status] ~= priority[b.status] then return priority[a.status] > priority[b.status] end
    if a.at ~= b.at then return a.at > b.at end
    return a.id > b.id
end

function Notes:GetHistory(noteID)
    local history, store = {}, self:GetStore(false)
    for _, operation in pairs(store and store.operations or {}) do
        if operation.noteID == noteID then history[#history + 1] = operation end
    end
    table.sort(history, function(a, b) return newer(b, a) end)
    return history
end

function Notes:GetRecords(member, includeDeleted)
    local records, result, store = {}, {}, self:GetStore(false)
    local key = member and iRC:NormalizeName(member)
    for _, operation in pairs(store and store.operations or {}) do
        if (not key or iRC:NormalizeName(operation.member) == key) and newer(operation, records[operation.noteID]) then
            records[operation.noteID] = operation
        end
    end
    for _, operation in pairs(records) do
        if includeDeleted or operation.status ~= "DELETED" then result[#result + 1] = operation end
    end
    table.sort(result, function(a, b) return a.at == b.at and a.id > b.id or a.at > b.at end)
    return result
end

function Notes:GetRecord(noteID)
    local current
    for _, operation in ipairs(self:GetHistory(noteID)) do if newer(operation, current) then current = operation end end
    return current
end

function Notes:GetCounts(member)
    local notes, strikes = 0, 0
    for _, record in ipairs(self:GetRecords(member)) do
        notes = notes + 1
        if record.strike and record.status == "ACTIVE" then strikes = strikes + 1 end
    end
    return notes, strikes
end

function Notes:Changed()
    if self.refreshScheduled then return end
    self.refreshScheduled = true
    C_Timer.After(0.1, function()
        Notes.refreshScheduled = false
        if Notes.UI then Notes.UI:RefreshIfShown() end
        local frame = iRC.MainUI and iRC.MainUI.frame
        if frame and frame:IsShown() and frame.category == "Member Management" and frame.memberManagementView == "NOTES" then
            iRC.MainUI:RefreshIfShown()
        end
    end)
end

function Notes:Store(operation)
    local store = self:GetStore(true)
    if not store or not validOperation(operation, self:GetScope()) then return false end
    if store.operations[operation.id] then return true end
    if store.count == nil then
        store.count = 0
        for _ in pairs(store.operations) do store.count = store.count + 1 end
    end
    if store.count >= MAX_RECORDS then return false end
    store.operations[operation.id] = operation
    store.count = store.count + 1
    self:Changed()
    return true
end

function Notes:Save(member, title, body, strike, noteID, expectedID, reason, action, reference)
    if not self:CanView() then return nil, "You do not have permission to view member notes." end
    local current = noteID and self:GetRecord(noteID)
    if noteID and (not current or current.id ~= expectedID or current.status == "DELETED") then
        return nil, "This note changed. Select it again before saving."
    end
    local permission = (current or strike) and "notesManage" or "notesAdd"
    if not self:Can(permission) then return nil, "You do not have permission to make this change." end
    member = current and current.member or iRC:ResolveGuildMemberFullName(member)
    if not member or (not current and not iRC:IsGuildMemberName(member)) then return nil, "Choose a guild member first." end
    title, body, reason = text(title, 120), text(body or "", 2048, true), text(reason or "", 240, true)
    if not title or title == "" then return nil, "Enter a short title for the note." end
    if not body or not reason then return nil, "Please shorten the note or change reason." end
    action = action or (current and "EDIT" or "CREATE")
    if not current and action ~= "CREATE" or current and action == "CREATE" then return nil, "Invalid note action." end
    if current and action ~= "EDIT" then strike = current.strike end
    if current and current.strike and not strike and reason == "" then
        return nil, "Enter a reason for removing the strike flag."
    end
    local status = current and current.strike and strike and current.status or "ACTIVE"
    if action == "RESOLVE" then status = "RESOLVED"
    elseif action == "REVOKE" then status = "REVOKED"
    elseif action == "DELETE" then status = "DELETED" end
    if action ~= "CREATE" and action ~= "EDIT" and reason == "" then return nil, "Enter a reason for this change." end
    local store, now = self:GetStore(true), time()
    sequence = sequence + 1
    store.sequence = (store.sequence or 0) + 1
    local author = iRC:GetPlayerName()
    local id = hash(author) .. "-" .. sessionID .. "-" .. string.format("%x-%x-%x", now, store.sequence, sequence)
    local operation = { id = id, noteID = noteID or id, parent = current and current.id or "",
        revision = current and current.revision + 1 or 1, member = member, title = title, body = body,
        strike = strike == true, status = status, author = author, at = math.max(now, current and current.at or 0),
        createdBy = current and current.createdBy or author, createdAt = current and current.createdAt or now,
        reason = reason, action = action, scope = self:GetScope(), reference = current and current.reference or reference or "" }
    if not self:Store(operation) then return nil, "The note could not be saved. The local history may be full." end
    iRC:DebugMsg("Member note saved: " .. action .. "; private sync queued.", 3)
    self:Announce()
    for _, peer in pairs(peers) do self:OfferOperation(peer.name, operation.id) end
    return operation
end

local function peerAllowed(name)
    if not Notes:CanView() or not iRC:IsGuildMemberName(name)
        or not iRC:GuildMemberHasPermission(name, "notesView") then return false end
    return iRC:NormalizeName(name) ~= iRC:NormalizeName(iRC:GetPlayerName())
end

local function online(name)
    local key = iRC:NormalizeName(name)
    if (not peers[key] and not iRC:IsRecentAddonPeer(name)) or iRC:IsAddonWhisperTargetUnavailable(name) then return false end
    for _, member in ipairs(iRC:GetGuildRosterSnapshot() or {}) do
        if iRC:NormalizeName(member.name) == key then return member.online == true end
    end
    return false
end

local function canShareOwn(operation)
    -- Received histories stay local. Even a manager may only send changes
    -- they authored directly to another member with notes access.
    return operation ~= nil and iRC:NormalizeName(operation.author) == iRC:NormalizeName(iRC:GetPlayerName())
        and (Notes:Can("notesManage") or operation.action == "CREATE" and not operation.strike and Notes:Can("notesAdd"))
end

local function partsFor(kind, ...)
    local scope = Notes:GetScope()
    if not scope then return nil end
    return table.concat({ kind, VERSION, hash(scope), ... }, "\t")
end

function Notes:CanSendPacket(message, distribution, target)
    if type(message) ~= "string" then return false end
    local parts, scope = split(message, "\t"), self:GetScope()
    if not scope or parts[2] ~= VERSION or parts[3] ~= hash(scope) then return false end
    if parts[1] == "NOTES_PERMS" or parts[1] == "NOTES_GRANTS" then
        return iRC:IsGuildMaster() and (distribution == "GUILD" or distribution == "WHISPER" and iRC:IsGuildMemberName(target))
    end
    if parts[1] == "NOTES_HELLO" then return distribution == "GUILD" and self:CanView() end
    if distribution ~= "WHISPER" or not peerAllowed(target) or not online(target) then return false end
    if parts[1] == "NOTES_CHUNK" then
        local store = self:GetStore(false)
        local operation = store and store.operations[parts[4]]
        return canShareOwn(operation)
    end
    if parts[1] == "NOTES_LIST" then
        if #parts ~= 4 then return false end
        if parts[4] == "" then return true end
        local ids, store = split(parts[4], ","), self:GetStore(false)
        if #ids > 4 then return false end
        for _, id in ipairs(ids) do
            if not canShareOwn(store and store.operations[id]) then return false end
        end
        return true
    end
    return parts[1] == "NOTES_WANT" or parts[1] == "NOTES_END" or parts[1] == "NOTES_PAGE"
end

local function send(kind, target, ...)
    local message = partsFor(kind, ...)
    local distribution = target and "WHISPER" or "GUILD"
    if not message or not Notes:CanSendPacket(message, distribution, target) then return false end
    return iRC:SendAddonTraffic(Notes.Prefix, message, distribution, target)
end

function Notes:OfferOperation(target, id)
    local store = self:GetStore(false)
    if not canShareOwn(store and store.operations[id]) then return end
    if send("NOTES_LIST", target, id) then return end
    local peer = peers[iRC:NormalizeName(target)]
    if peer then
        peer.pending = peer.pending or {}
        peer.pending[id] = true
    end
end

function Notes:FlushOffers(target)
    local peer = peers[iRC:NormalizeName(target)]
    if not peer or not peer.pending then return end
    local batch, offered = {}, 0
    local store = self:GetStore(false)
    for id in pairs(peer.pending) do
        if canShareOwn(store and store.operations[id]) then batch[#batch + 1] = id
        else peer.pending[id] = nil end
        if #batch == 4 then
            if not send("NOTES_LIST", target, table.concat(batch, ",")) then return end
            for _, sentID in ipairs(batch) do peer.pending[sentID] = nil end
            offered, batch = offered + 4, {}
            if offered >= 32 then return end
        end
    end
    if #batch > 0 and send("NOTES_LIST", target, table.concat(batch, ",")) then
        for _, id in ipairs(batch) do peer.pending[id] = nil end
    end
end

function Notes:Announce(force)
    if not self:CanView() then return false end
    if GetTime() - lastHello < (force and 10 or 30) then return false end
    lastHello = GetTime()
    iRC:DebugMsg("Member notes: requesting private updates from authorised guild members.", 3)
    return send("NOTES_HELLO", nil, force and "1" or "0")
end

function Notes:StartPeriodicSync()
    if self.syncTicker then return end
    self.syncTicker = C_Timer.NewTicker(SYNC_INTERVAL, function()
        -- Discovery contains no notes. Missing changes still travel directly
        -- from their authors, with permissions checked for every private send.
        if Notes:Announce() then
            iRC:DebugMsg("Member notes: automatic 30-minute sync check sent.", 3)
        end
    end)
end

function Notes:SendPermissions(target)
    if not iRC:IsGuildMaster() then return false end
    local connection = iRC:GetConnection()
    if not connection or not self:GetScope() then return false end
    local values = {}
    for _, permission in ipairs(self.Permissions) do values[#values + 1] = tostring(iRC:GetGuildRankPermission(permission)) end
    return send("NOTES_PERMS", target, tostring(connection.rankPermissionsTimestamp or 0), table.concat(values, ","))
end

function Notes:SendGrants(memberName, target)
    if not iRC:IsGuildMaster() then return end
    local connection = iRC:GetConnection()
    for _, entry in pairs(connection and connection.memberPermissions or {}) do
        if not memberName or iRC:NormalizeName(entry.name) == iRC:NormalizeName(memberName) then
            local mask = 0
            for index, permission in ipairs(self.Permissions) do
                if entry.permissions[permission] then mask = mask + 2 ^ (index - 1) end
            end
            send("NOTES_GRANTS", target, hex(entry.name), tostring(entry.timestamp), tostring(mask))
        end
    end
end

function Notes:SendManifest(target, force, cursor, token)
    local key = iRC:NormalizeName(target)
    if not peerAllowed(target) or not online(target) then return end
    local delay = not cursor and (force and 2 or 60) - (GetTime() - (manifestTimes[key] or -math.huge)) or 0
    if delay > 0 then
        if force and not pendingManifests[key] then
            local scope = self:GetScope()
            pendingManifests[key] = true
            C_Timer.After(delay + 0.01, function()
                if Notes:GetScope() ~= scope then return end
                pendingManifests[key] = nil
                Notes:SendManifest(target, true)
            end)
        end
        return
    end
    local snapshot = snapshots[key]
    if cursor then
        if not snapshot or snapshot.token ~= token or snapshot.next ~= cursor
            or GetTime() - snapshot.at > 300 then return end
    else
        manifestTimes[key] = GetTime()
        local ids, store = {}, self:GetStore(false)
        for id, operation in pairs(store and store.operations or {}) do if canShareOwn(operation) then ids[#ids + 1] = id end end
        table.sort(ids)
        sequence = sequence + 1
        snapshot = { ids = ids, token = hash(key .. GetTime() .. sequence), at = GetTime() }
        snapshots[key] = snapshot
    end
    local ids = snapshot.ids
    cursor = cursor or 0
    if #ids == 0 then send("NOTES_LIST", target, ""); return end
    -- Send only a small page at a time. Large guild histories must not fill
    -- the shared addon queue with every saved note at login.
    local last = math.min(cursor + 32, #ids)
    for first = cursor + 1, last, 4 do
        local batch = {}
        for index = first, math.min(first + 3, last) do batch[#batch + 1] = ids[index] end
        send("NOTES_LIST", target, table.concat(batch, ","))
    end
    snapshot.next = last < #ids and last or nil
    send("NOTES_END", target, snapshot.token, tostring(snapshot.next or 0))
end

local function transferCount()
    local count = 0
    for key, transfer in pairs(transfers) do
        if GetTime() - transfer.at > 90 then transfers[key] = nil else count = count + 1 end
    end
    return count
end

function Notes:RequestMissing(target)
    local key, missing, wanted = iRC:NormalizeName(target), {}, requests[iRC:NormalizeName(target)]
    local store = self:GetStore(false)
    if not wanted then return end
    local active = 0
    for id, request in pairs(wanted) do
        if store and store.operations[id] then wanted[id] = nil
        elseif request.sent and GetTime() - request.sent <= 60 then active = active + 1
        elseif (request.attempts or 0) < 2 and #missing < 2 then
            missing[#missing + 1] = id
        end
    end
    if active >= 2 or #missing == 0 then return end
    while #missing > 2 - active do table.remove(missing) end
    -- Renew contact through the guild before retrying an old whisper. A
    -- missing packet is not proof that its sender is still online.
    if not online(target) then self:Announce(true); return end
    if send("NOTES_WANT", target, table.concat(missing, ",")) then
        for _, id in ipairs(missing) do
            wanted[id].sent = GetTime()
            wanted[id].attempts = (wanted[id].attempts or 0) + 1
        end
        local scope = self:GetScope()
        C_Timer.After(65, function() if Notes:GetScope() == scope then Notes:RequestMissing(target) end end)
    end
end

local function receivePermissions(parts, sender)
    if not iRC:IsGuildMemberName(sender) or not iRC:IsGuildMasterName(sender) then return end
    local connection = iRC:GetConnection()
    if parts[1] == "NOTES_PERMS" then
        local timestamp, values = tonumber(parts[4]), split(parts[5] or "", ",")
        if not integer(timestamp, 1, time() + 300) or timestamp < (connection.notePermissionsTimestamp or 0)
            or #values ~= 3 then return end
        for _, value in ipairs(values) do if not integer(tonumber(value), 0, 9) then return end end
        local unchanged = timestamp == connection.notePermissionsTimestamp
        for index, permission in ipairs(Notes.Permissions) do
            if not connection.rankPermissions or connection.rankPermissions[permission] ~= tonumber(values[index]) then unchanged = false end
        end
        if unchanged then return end
        connection.rankPermissions = connection.rankPermissions or {}
        for index, permission in ipairs(Notes.Permissions) do connection.rankPermissions[permission] = tonumber(values[index]) end
        connection.notePermissionsTimestamp = timestamp
    else
        local name, timestamp, mask = unhex(parts[4] or ""), tonumber(parts[5]), tonumber(parts[6])
        if not name or not iRC:IsGuildMemberName(name) or not integer(timestamp, 1, time() + 300)
            or not integer(mask, 0, 7) then return end
        local key = iRC:NormalizeName(name)
        connection.memberPermissions = connection.memberPermissions or {}
        local entry = connection.memberPermissions[key] or { name = name, permissions = {}, timestamp = 0 }
        if timestamp < (entry.notePermissionsTimestamp or 0) then return end
        local unchanged = timestamp == entry.notePermissionsTimestamp
        for index, permission in ipairs(Notes.Permissions) do
            if (entry.permissions[permission] == true) ~= (math.floor(mask / 2 ^ (index - 1)) % 2 == 1) then unchanged = false end
        end
        if unchanged then return end
        for index, permission in ipairs(Notes.Permissions) do entry.permissions[permission] = math.floor(mask / 2 ^ (index - 1)) % 2 == 1 or nil end
        entry.notePermissionsTimestamp = timestamp
        connection.memberPermissions[key] = entry
    end
    if iRC.RefreshOptionsIfShown then iRC:RefreshOptionsIfShown() end
    if iRC.MainUI then iRC.MainUI:RefreshIfShown() end
    Notes:Changed()
    Notes:Announce()
end

function Notes:OnMessage(prefix, message, distribution, sender)
    if prefix ~= self.Prefix or iRC:HasSecretValues(prefix, message, distribution, sender)
        or type(message) ~= "string" or #message > 255
        or distribution ~= "GUILD" and distribution ~= "WHISPER" then return end
    local parts, scope = split(message, "\t"), self:GetScope()
    if not scope or parts[2] ~= VERSION or parts[3] ~= hash(scope)
        or not iRC:IsGuildMemberName(sender) then return end
    if not iRC:AcceptIncomingAddonTraffic(prefix, message, distribution, sender, "member-notes") then return end
    if parts[1] == "NOTES_PERMS" or parts[1] == "NOTES_GRANTS" then receivePermissions(parts, sender); return end
    if not peerAllowed(sender) then return end
    local key = iRC:NormalizeName(sender)
    if not peers[key] then
        local count = 0
        for peer, info in pairs(peers) do
            if GetTime() - info.at > 300 and (not peerAllowed(info.name) or not online(info.name)) then
                peers[peer] = nil
            else count = count + 1 end
        end
        if count >= 1024 then return end
    end
    peers[key] = peers[key] or {}
    peers[key].at, peers[key].name = GetTime(), sender
    self:FlushOffers(sender)
    if parts[1] == "NOTES_HELLO" and distribution == "GUILD" then
        self:SendManifest(sender, parts[4] == "1")
    elseif distribution ~= "WHISPER" then return
    elseif parts[1] == "NOTES_END" and #parts == 5 then
        local cursor = tonumber(parts[5])
        if type(parts[4]) == "string" and parts[4]:match("^%x%x%x%x%x%x%x%x$") and integer(cursor, 1, MAX_RECORDS) then
            send("NOTES_PAGE", sender, parts[4], tostring(cursor))
        end
    elseif parts[1] == "NOTES_PAGE" and #parts == 5 then
        local cursor = tonumber(parts[5])
        if integer(cursor, 1, MAX_RECORDS) then self:SendManifest(sender, false, cursor, parts[4]) end
    elseif parts[1] == "NOTES_LIST" and #parts == 4 then
        local ids = parts[4] == "" and {} or split(parts[4], ",")
        if #ids > 4 then return end
        requests[key] = requests[key] or {}
        local store = self:GetStore(false)
        local queued = 0
        for _ in pairs(requests[key]) do queued = queued + 1 end
        for _, id in ipairs(ids) do
            if validID(id) and queued < MAX_RECORDS and not (store and store.operations[id]) then
                if not requests[key][id] then queued = queued + 1 end
                requests[key][id] = requests[key][id] or {}
                if requests[key][id].sent and GetTime() - requests[key][id].sent > 90 then
                    requests[key][id].attempts = 0
                end
            end
        end
        self:RequestMissing(sender)
        self:SendManifest(sender)
    elseif parts[1] == "NOTES_WANT" and #parts == 4 then
        local budget = requestTimes[key]
        if not budget or GetTime() - budget.at >= 1 then budget = { at = GetTime(), count = 0 }; requestTimes[key] = budget end
        if budget.count >= 16 then return end
        budget.count = budget.count + 1
        local ids, store = split(parts[4], ","), self:GetStore(false)
        if #ids > 2 then return end
        for _, id in ipairs(ids) do
            local operation = store and store.operations[id]
            if canShareOwn(operation) then
                local payload = encode(operation)
                local count = math.ceil(#payload / CHUNK_SIZE)
                if count <= MAX_CHUNKS then
                    for index = 1, count do
                        send("NOTES_CHUNK", sender, id, tostring(index), tostring(count),
                            payload:sub((index - 1) * CHUNK_SIZE + 1, index * CHUNK_SIZE))
                    end
                end
            end
        end
    elseif parts[1] == "NOTES_CHUNK" and #parts == 7 then
        local id, index, count = parts[4], tonumber(parts[5]), tonumber(parts[6])
        local wanted = requests[key] and requests[key][id]
        if not wanted or not wanted.sent or GetTime() - wanted.sent > 90 or not validID(id)
            or not integer(index, 1, MAX_CHUNKS) or not integer(count, index, MAX_CHUNKS)
            or #parts[7] > CHUNK_SIZE then return end
        local transferKey = key .. ":" .. id
        local transfer = transfers[transferKey]
        if not transfer then
            if transferCount() >= 16 then return end
            transfer = { count = count, chunks = {}, at = GetTime(), received = 0 }
            transfers[transferKey] = transfer
        end
        if transfer.count ~= count then return end
        if not transfer.chunks[index] then transfer.received = transfer.received + 1 end
        transfer.chunks[index] = parts[7]
        if transfer.received ~= count then return end
        transfers[transferKey] = nil
        local operation = decode(table.concat(transfer.chunks))
        local manager = iRC:GuildMemberHasPermission(sender, "notesManage")
        local directAuthor = operation and iRC:NormalizeName(operation.author) == iRC:NormalizeName(sender)
        local ownOrdinary = operation and operation.action == "CREATE"
            and not operation.strike and iRC:GuildMemberHasPermission(sender, "notesAdd")
        if directAuthor and operation.id == id and (manager or ownOrdinary) and self:Store(operation) then
            requests[key][id] = nil
            iRC:DebugMsg("Member notes: received a private history update from " .. iRC:FormatPlayerName(sender) .. ".", 3)
            self:RequestMissing(sender)
        elseif operation and not directAuthor then
            requests[key][id] = nil
            iRC:DebugMsg("Member notes: rejected a forwarded update from " .. iRC:FormatPlayerName(sender) .. ".", 3)
            self:RequestMissing(sender)
        end
    end
end

local frame = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE", "CHAT_MSG_ADDON" }) do frame:RegisterEvent(event) end
local scheduled
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then Notes:OnMessage(...); return end
    Notes:Changed()
    if event == "GUILD_ROSTER_UPDATE" then return end
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(Notes.Prefix) end
        Notes:StartPeriodicSync()
    end
    if scheduled then return end
    scheduled = true
    C_Timer.After(event == "PLAYER_LOGIN" and 15 or 3, function()
        scheduled = false
        Notes:Changed()
        Notes:Announce()
    end)
end)
