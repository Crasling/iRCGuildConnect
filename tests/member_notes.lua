-- Exercise the real notes module through isolated clients and a queued network.
local clock, epoch, queue, timers, clients = 100, 1793982300, {}, {}, {}
local sent, roles, online = {}, {}, {}
local function read(path)
    local file = assert(io.open(path)); local source = file:read("*a"); file:close(); return source
end
local source = read("iRC_MemberNotes.lua")
local function client(name, permissions)
    roles[name], online[name] = permissions, true
    local connection = { active = true, rankPermissions = {}, memberPermissions = {}, rankPermissionsTimestamp = epoch }
    local addon = { name = name, connection = connection, scope = "s-18-3-1-0-pve", guild = "guild-one", seen = {}, messages = {} }
    local env = setmetatable({ _G = false, iRCDB = {} }, { __index = _G }); env._G = env
    env.GetTime = function() return clock end
    env.time = function() return epoch + math.floor(clock) end
    env.GetNormalizedRealmName = function() return "Forever" end
    addon.tickers = {}
    env.C_Timer = {
        After = function(delay, callback) timers[#timers + 1] = { at = clock + delay, run = callback } end,
        NewTicker = function(interval, callback)
            local ticker = { interval = interval, run = callback }
            addon.tickers[#addon.tickers + 1] = ticker
            return ticker
        end,
    }
    env.C_ChatInfo = { RegisterAddonMessagePrefix = function(prefix) assert(prefix == "iRCNotesV1") end }
    env.CreateFrame = function()
        local frame = { RegisterEvent = function() end, SetScript = function(self, event, callback) self[event] = callback end }
        addon.eventFrame = frame
        return frame
    end
    function addon:GetConnection() return self.connection end
    function addon:GetGuildKey() return self.guild end
    function addon:GetGuildDirectoryScope() return self.scope end
    function addon:IsGuildConnectionActive() return self.connection.active end
    function addon:IsSecretValue(v) return v == "SECRET" end
    function addon:HasSecretValues(...) for i=1,select("#",...) do if self:IsSecretValue(select(i,...)) then return true end end;return false end
    function addon:GetPlayerName() return self.name end
    function addon:NormalizeName(value) return (value or ""):lower() end
    function addon:FormatPlayerName(value) return value end
    function addon:IsGuildMemberName(value) return roles[value] ~= nil and value ~= "Other Guild" end
    function addon:ResolveGuildMemberFullName(value) return self:IsGuildMemberName(value) and value or nil end
    function addon:IsGuildMaster() return self.name == "Guild Master" end
    function addon:IsGuildMasterName(value) return value == "Guild Master" end
    function addon:HasGuildPermission(permission) return roles[self.name][permission] == true end
    function addon:GuildMemberHasPermission(value, permission) return roles[value] and roles[value][permission] == true or false end
    function addon:GetGuildRankPermission(permission) return self.connection.rankPermissions[permission] or 1 end
    function addon:IsRecentAddonPeer(value) return self.seen[value] ~= nil and clock - self.seen[value] < 30 end
    function addon:IsAddonWhisperTargetUnavailable(value) return not online[value] end
    function addon:GetGuildRosterSnapshot()
        local rows = {}
        for player in pairs(roles) do rows[#rows + 1] = { name = player, online = online[player] } end
        return rows
    end
    function addon:AcceptIncomingAddonTraffic(_, _, _, sender)
        if sender == self.name then return false end
        self.seen[sender] = clock
        return true
    end
    function addon:DebugMsg(message) self.messages[#self.messages + 1] = message end
    function addon:SendAddonTraffic(prefix, message, distribution, target)
        assert(#message <= 255, "every packet fits the addon-message limit")
        assert(self.MemberNotes:CanSendPacket(message, distribution, target), "the transport rechecks private permissions")
        local packet = { from = name, prefix = prefix, message = message, distribution = distribution, target = target, guild = self.guild, scope = self.scope }
        sent[#sent + 1] = packet; queue[#queue + 1] = packet
        if distribution == "GUILD" then
            assert(message:match("^NOTES_HELLO") or message:match("^NOTES_PERMS") or message:match("^NOTES_GRANTS"),
                "private contents and manifests never travel through guild chat")
        end
        return true
    end
    assert(load(source, "member notes", "t", env))("iRC", { iRC = addon })
    addon.env = env
    clients[name] = addon
    return addon
end
local manager = { notesView = true, notesAdd = true, notesManage = true }
local a = client("Guild Master", { notesView = true, notesAdd = true, notesManage = true })
local b = client("Officer Two", { notesView = true, notesAdd = true, notesManage = true })
local writer = client("Note Writer", { notesView = true, notesAdd = true })
local reader = client("Reader Only", { notesView = true })
local member = client("Regular Member", {})
local offline = client("Offline Officer", { notesView = true, notesAdd = true, notesManage = true })
online[offline.name] = false

local function tick(seconds)
    clock = clock + (seconds or 0.2)
    local due = timers; timers = {}
    for _, timer in ipairs(due) do
        if timer.at <= clock then timer.run() else timers[#timers + 1] = timer end
    end
end
local dropPacket
local function pump()
    local iterations = 0
    while #queue > 0 do
        iterations = iterations + 1; assert(iterations < 20000, "sync must settle without a request loop")
        local packet = table.remove(queue, 1)
        for name, receiver in pairs(clients) do
            if name ~= packet.from and online[name] and receiver.guild == packet.guild and receiver.scope == packet.scope
                and (packet.distribution == "GUILD" or packet.target == name) and not (dropPacket and dropPacket(packet, name)) then
                receiver.MemberNotes:OnMessage(packet.prefix, packet.message, packet.distribution, packet.from)
            end
        end
        tick()
    end
end
local function save(addon, title, strike)
    return assert(addon.MemberNotes:Save("Regular Member", title, "A normal multiline note.\n中文 | words % preserved.", strike))
end

assert(not member.MemberNotes:Save("Regular Member", "Not permitted", "", false))
assert(not reader.MemberNotes:Save("Regular Member", "Not permitted", "", false))
assert(not writer.MemberNotes:Save("Regular Member", "Cannot assign strikes", "", true))
local first = save(a, "Raid availability", false)
local second = save(b, "First warning", true)
local own = save(writer, "Helpful member", false)
a.MemberNotes:Announce(true); b.MemberNotes:Announce(true); writer.MemberNotes:Announce(true); reader.MemberNotes:Announce(true)
pump(); tick(3); pump()
for _, addon in ipairs({a,b,writer,reader}) do
    local notes, strikes = addon.MemberNotes:GetCounts("Regular Member")
    assert(notes == 3 and strikes == 1, addon.name .. " receives the merged notes and strike count: " .. notes .. "/" .. strikes)
    assert(addon.MemberNotes:GetRecord(first.noteID).body == first.body, "Unicode and line breaks survive chunking")
end
assert(member.MemberNotes:GetStore(false) == nil, "unauthorised members never store note contents")
assert(offline.MemberNotes:GetStore(false) == nil, "offline members are not whispered")
for _, packet in ipairs(sent) do assert(packet.target ~= member.name and packet.target ~= offline.name) end

local resolved = assert(b.MemberNotes:Save(second.member, second.title, second.body, true, second.noteID, second.id,
    "Reviewed with the member", "RESOLVE"))
local count, strikes = b.MemberNotes:GetCounts(second.member)
assert(count == 3 and strikes == 0)
assert(#b.MemberNotes:GetHistory(second.noteID) == 2, "resolving preserves the original strike")
assert(not writer.MemberNotes:Save(first.member, "Changed", "", false, first.noteID, first.id), "add permission does not grant editing")
tick(3); pump()
assert(reader.MemberNotes:GetRecord(second.noteID).status == "RESOLVED")
assert(not a.MemberNotes:Save(second.member, "Stale editor", "", true, second.noteID, second.id), "a stale editor cannot overwrite a newer decision")
local revoked = assert(a.MemberNotes:Save(second.member, second.title, second.body, true, second.noteID, resolved.id, "Incorrect report", "REVOKE"))
assert(revoked.status == "REVOKED")
tick(3); pump()

-- Two offline editors retain both changes, with deterministic current state.
online[a.name], online[b.name] = false, false
local branchA = assert(a.MemberNotes:Save(first.member, "One edit", "Details A", false, first.noteID, first.id))
local branchB = assert(b.MemberNotes:Save(first.member, "Another edit", "Details B", false, first.noteID, first.id))
online[a.name], online[b.name] = true, true
tick(65); a.MemberNotes:Announce(true); b.MemberNotes:Announce(true); pump(); tick(3); pump()
assert(a.MemberNotes:GetRecord(first.noteID).id == b.MemberNotes:GetRecord(first.noteID).id, "concurrent edits converge")
assert(#a.MemberNotes:GetHistory(first.noteID) == 3 and #b.MemberNotes:GetHistory(first.noteID) == 3, "both edits remain in history")

-- A new officer catches up later without replacing existing records.
online[offline.name] = true
offline.MemberNotes:Announce(true); pump(); tick(3); pump()
assert(#offline.MemberNotes:GetRecords() == 3 and #offline.MemberNotes:GetHistory(first.noteID) == 3)
local current = a.MemberNotes:GetRecord(own.noteID)
assert(not a.MemberNotes:Save(current.member, current.title, current.body, false, current.noteID, current.id, "", "DELETE"), "removal requires a reason")
local removed = assert(a.MemberNotes:Save(current.member, current.title, current.body, false, current.noteID, current.id, "Duplicate", "DELETE"))
tick(3); pump()
if reader.MemberNotes:GetRecord(own.noteID).status ~= "DELETED" then
    for _, packet in ipairs(sent) do
        if (packet.target == reader.name or packet.from == reader.name) and packet.message:find(removed.id, 1, true) then
            print("trace", packet.from, packet.target, packet.message:match("^[^\t]+"))
        end
    end
end
assert(#reader.MemberNotes:GetRecords() == 2 and reader.MemberNotes:GetRecord(own.noteID).status == "DELETED",
    "removal tombstones sync: " .. #reader.MemberNotes:GetRecords() .. "/" .. reader.MemberNotes:GetRecord(own.noteID).status)

-- Recheck recipient access at send time, including a queued private packet.
local privatePacket
for _, packet in ipairs(sent) do if packet.target == reader.name and packet.message:match("^NOTES_CHUNK") then privatePacket = packet end end
assert(privatePacket)
roles[reader.name].notesView = false
assert(not a.MemberNotes:CanSendPacket(privatePacket.message, "WHISPER", reader.name), "revocation blocks already-queued private data")
assert(not reader.MemberNotes:CanView() and #reader.MemberNotes:GetRecords() == 0)
roles[reader.name].notesView = true
online[reader.name] = false
assert(not a.MemberNotes:CanSendPacket(privatePacket.message, "WHISPER", reader.name), "offline recipients are blocked")
online[reader.name] = true

-- Realm/ruleset and guild boundaries have separate saved stores and sessions.
local oldScope = a.scope
a.scope = "s-18-3-2-0-pvp"
assert(#a.MemberNotes:GetRecords() == 0)
a.MemberNotes:OnMessage(privatePacket.prefix, privatePacket.message, "WHISPER", b.name)
assert(#a.MemberNotes:GetRecords() == 0, "another server's packets cannot populate the new scope")
local different = save(a, "Separate server", false)
a.scope = oldScope
assert(#a.MemberNotes:GetRecords() == 2 and not a.MemberNotes:GetRecord(different.noteID), "returning restores only the original server's notes")
a.guild = "another-guild"
assert(#a.MemberNotes:GetRecords() == 0)
a.guild = "guild-one"

-- Rank and individual note grants use their own route and timestamps.
a.connection.rankPermissions.notesView = 0
a.MemberNotes:SendPermissions(); pump()
assert(b.connection.rankPermissions.notesView == 0)
a.connection.memberPermissions[writer.name:lower()] = { name = writer.name, permissions = { notesView = true, notesAdd = true }, timestamp = epoch + math.floor(clock) }
a.MemberNotes:SendGrants(writer.name); pump()
local grants = b.connection.memberPermissions[writer.name:lower()]
assert(grants.permissions.notesView and grants.permissions.notesAdd and not grants.permissions.notesManage)

-- Page a larger history to a later login, then recover a lost data chunk.
for name in pairs(online) do online[name] = name == a.name end
for index = 1, 80 do save(a, "Backlog note " .. index, false) end
local late = client("Late Officer", { notesView = true, notesAdd = true, notesManage = true })
tick(65); late.MemberNotes:Announce(true); pump(); tick(3); pump()
assert(#late.MemberNotes:GetRecords() == #a.MemberNotes:GetRecords(), "paged manifests catch up beyond the first 32 operations")
local lateStore, sourceStore = late.MemberNotes:GetStore(false), a.MemberNotes:GetStore(false)
for id, operation in pairs(sourceStore.operations) do
    assert((lateStore.operations[id] ~= nil) == (operation.author == a.name),
        "catch-up sends only the online author's own operations, never cached histories from other officers")
end
local sawPage
for _, packet in ipairs(sent) do if packet.message:match("^NOTES_PAGE") then sawPage = true end end
assert(sawPage, "large histories request bounded manifest pages")
local lost = save(a, "Lost packet recovery", false)
local dropped = false
dropPacket = function(packet, target)
    if not dropped and target == late.name and packet.message:match("^NOTES_CHUNK")
        and packet.message:find(lost.id, 1, true) then dropped = true; return true end
end
pump()
assert(dropped and not late.MemberNotes:GetRecord(lost.noteID), "an incomplete transfer is not stored as a note")
dropPacket = nil
tick(66); pump(); tick(3); pump()
assert(late.MemberNotes:GetRecord(lost.noteID), "a dropped chunk is recovered after renewing online contact")
local before = #sent
tick(400); pump()
assert(#sent == before, "completed sync does not turn into idle whisper polling")

-- An authorised officer cannot relay someone else's note, even to another
-- authorised reader. The reader must meet the original author online.
for name in pairs(online) do online[name] = name == a.name or name == b.name end
tick(65); a.MemberNotes:Announce(true); b.MemberNotes:Announce(true); pump(); tick(3); pump()
local private = save(b, "Direct author only", true)
pump(); tick(3); pump()
assert(a.MemberNotes:GetRecord(private.noteID), "the other manager has a local copy")
local privacyReader = client("Privacy Reader", { notesView = true })
online[b.name], online[member.name] = false, true
tick(65); privacyReader.MemberNotes:Announce(true); pump(); tick(3); pump()
assert(not privacyReader.MemberNotes:GetRecord(private.noteID), "an offline author's note is never relayed by a manager")

local chunks = {}
for _, packet in ipairs(sent) do
    if packet.from == b.name and packet.target == a.name and packet.message:match("^NOTES_CHUNK")
        and packet.message:find(private.id, 1, true) then chunks[#chunks + 1] = packet end
end
assert(#chunks > 0)
local header = assert(chunks[1].message:match("^NOTES_CHUNK\t([^\t]+\t[^\t]+)\t"))
local list = "NOTES_LIST\t" .. header .. "\t" .. private.id
assert(not a.MemberNotes:CanSendPacket(chunks[1].message, "WHISPER", privacyReader.name), "the queue refuses another author's data")
assert(not a.MemberNotes:CanSendPacket(list, "WHISPER", privacyReader.name), "the queue also refuses relayed note IDs")
local offered = #sent
a.MemberNotes:OfferOperation(privacyReader.name, private.id)
assert(#sent == offered, "cached notes cannot enter live offers")

-- Pretend a stale or modified client sends the old relay protocol anyway.
privacyReader.MemberNotes:OnMessage(a.MemberNotes.Prefix, list, "WHISPER", a.name)
for _, packet in ipairs(chunks) do
    privacyReader.MemberNotes:OnMessage(packet.prefix, packet.message, "WHISPER", a.name)
end
assert(not privacyReader.MemberNotes:GetRecord(private.noteID), "receivers reject relayed contents even from a permitted manager")
pump()
local wanted = "NOTES_WANT\t" .. header .. "\t" .. private.id
local unpermitted = #sent
b.MemberNotes:OnMessage(b.MemberNotes.Prefix, wanted, "WHISPER", member.name)
assert(#sent == unpermitted, "unpermitted members cannot request private contents")
assert(not b.MemberNotes:CanSendPacket(chunks[1].message, "GUILD"), "note contents cannot be broadcast to the guild")
assert(not b.MemberNotes:CanSendPacket(chunks[1].message, "CHANNEL", 6), "note contents cannot use the public channel")
assert(not b.MemberNotes:CanSendPacket(chunks[1].message, "WHISPER", member.name), "even online unpermitted members receive no contents")

online[b.name] = true
tick(65); b.MemberNotes:Announce(true); privacyReader.MemberNotes:Announce(true); pump(); tick(3); pump()
assert(privacyReader.MemberNotes:GetRecord(private.noteID), "the author sends the note directly when back online")
roles[b.name].notesManage = false
assert(not b.MemberNotes:CanSendPacket(chunks[1].message, "WHISPER", privacyReader.name),
    "removing an author's write permission also stops queued strike updates")
roles[b.name].notesManage = true
for _, packet in ipairs(sent) do
    if packet.message:match("^NOTES_CHUNK") then
        local id = assert(packet.message:match("^NOTES_CHUNK\t[^\t]+\t[^\t]+\t([^\t]+)"))
        local store = assert(clients[packet.from].MemberNotes:GetStore(false))
        assert(store.operations[id].author == packet.from, "every transmitted operation comes directly from its author")
    end
end

-- Login starts exactly one half-hour check. It discovers peers through the
-- guild, then sends only missing changes over the private author-only route.
for name in pairs(online) do online[name] = false end
local periodicAuthor = client("Periodic Author", { notesView = true, notesAdd = true, notesManage = true })
local periodicReader = client("Periodic Reader", { notesView = true })
local periodicMember = client("Periodic Member", {})
for _, addon in ipairs({periodicAuthor, periodicReader, periodicMember}) do
    addon.eventFrame:OnEvent("PLAYER_LOGIN")
    addon.eventFrame:OnEvent("PLAYER_LOGIN")
    assert(#addon.tickers == 1 and addon.tickers[1].interval == 1800, "login starts one 30-minute sync ticker")
end
tick(16); pump(); tick(3); pump()
online[periodicReader.name] = false
local periodicNote = save(periodicAuthor, "Half-hour catch-up", false)
pump()
assert(not periodicReader.MemberNotes:GetRecord(periodicNote.noteID))
online[periodicReader.name] = true
tick(1800)
periodicAuthor.tickers[1].run(); periodicReader.tickers[1].run(); periodicMember.tickers[1].run()
pump(); tick(3); pump()
assert(periodicReader.MemberNotes:GetRecord(periodicNote.noteID), "the automatic check catches up missing authored changes")
assert(periodicMember.MemberNotes:GetStore(false) == nil, "the periodic check never sends notes to an unpermitted member")
local periodicBefore = #sent
tick(1800); periodicAuthor.tickers[1].run(); periodicReader.tickers[1].run(); pump(); tick(3); pump()
for index = periodicBefore + 1, #sent do
    assert(not sent[index].message:match("^NOTES_CHUNK"), "unchanged notes are not downloaded again every 30 minutes")
end
roles[periodicAuthor.name].notesView = false
periodicReader.connection.active = false
tick(1800); pump()
local stopped = #sent
periodicAuthor.tickers[1].run(); periodicReader.tickers[1].run(); periodicMember.tickers[1].run()
assert(#sent == stopped, "periodic checks pause without notes permission or an active guild connection")
roles[periodicAuthor.name].notesView = true
periodicReader.connection.active = true

local core = read("iRC_Core.lua")
assert(core:find('prefix == "iRCNotesV1"',1,true) and core:find('self.MemberNotes:CanSendPacket',1,true), "the real queue guards private packets")
assert(core:find('iRC.MemberNotes:CanSendPacket',1,true), "the actual send revalidates permissions after queueing")
print("PASS: member notes, optional strikes, permissions, direct author-only sync, relay rejection, offline catch-up, concurrent edits, tombstones, scope isolation and revocation")
return { clients = clients, roles = roles, tick = tick, pump = pump, online = online, queue = queue, sent = sent }
