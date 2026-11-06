-- Run from the addon directory. No game, network, or saved-variable writes.
local now, combat = 1000, false
local timers, frames, sent, errors, diagnostics = {}, {}, {}, {}, {}
local addon, private = {}, {}
function wipe(value) for key in pairs(value) do value[key] = nil end; return value end
function GetTime() return now end
function time() return 1800000000 + math.floor(now) end
function GetBuildInfo() return "1.60.1", "70374", "", 16001 end
function GetGuildInfo() return "Own Guild", "Guild Master", 0 end
function UnitAffectingCombat() return combat end
function InCombatLockdown() return combat end
function CreateFrame()
    local frame = { scripts = {} }
    function frame:RegisterEvent() end
    function frame:SetScript(key, callback) self.scripts[key] = callback end
    frames[#frames + 1] = frame
    return frame
end
function LibStub(name)
    if name == "AceAddon-3.0" then return { NewAddon = function() return addon end } end
end
function geterrorhandler() return function(err) errors[#errors + 1] = err end end
C_Timer = { After = function(delay, callback)
    timers[#timers + 1] = { at = now + delay, callback = callback }
end }
C_ChatInfo = { SendAddonMessage = function(prefix, message, distribution, target)
    sent[#sent + 1] = { prefix = prefix, message = message, distribution = distribution, target = target }
    return true
end }
assert(loadfile("iRC_Core.lua"))("iRC", private)
local settings = {}
function addon:GetSettings() return settings end
function addon:GetPlayerName() return "Self" end
function addon:IsGuildConnectionActive() return true end
function addon:IsGuildMemberName(name) return name ~= "Outsider" end
function addon:AcceptIncomingAddonTraffic() return true end
function addon:GetStartupTrafficDelay() return 2 end
function addon:GetGuildDirectoryScope() return "s-18-3-10-0-pve" end
function addon:ContainsProfanity() return false end
function addon:CheckForNewVersion() end
function addon:Text(key) return key end
function addon:DebugMsg(message) diagnostics[#diagnostics + 1] = message end
assert(loadfile("iRC_RaceGrid.lua"))("iRC", private)
local grid, receiver = addon.RaceGrid, frames[#frames]

local function upvalue(callback, wanted)
    for index = 1, 100 do
        local key, value = debug.getupvalue(callback, index)
        if key == wanted then return value end
        if not key then break end
    end
    error("missing fixture helper: " .. wanted)
end
local serialize = upvalue(grid.BroadcastReport, "serializeGuildReport")
local function advance(seconds)
    local finish = now + seconds
    while true do
        table.sort(timers, function(a, b) return a.at < b.at end)
        if not timers[1] or timers[1].at > finish then break end
        local timer = table.remove(timers, 1)
        now = timer.at
        timer.callback()
    end
    now = finish
    assert(#errors == 0, table.concat(errors, "\n"))
end
local function split(message)
    local result = {}
    for field in (message .. "\t"):gmatch("(.-)\t") do result[#result + 1] = field end
    return result
end
local function receive(fields, sender, distribution)
    if type(fields) == "table" then
        fields = { table.unpack(fields) }
        fields[2] = addon.GridWireVersion
        fields[#fields + 1] = "@" .. addon:GetGuildDirectoryScope()
    end
    receiver.scripts.OnEvent(receiver, "CHAT_MSG_ADDON", "iRCGridV1",
        type(fields) == "table" and table.concat(fields, "\t") or fields,
        distribution or "WHISPER", sender or "Sender")
end
local function checksum(value)
    local first, second = 1, 0
    for index = 1, #value do
        first = (first + value:byte(index)) % 65521
        second = (second + first) % 65521
    end
    return string.format("%04x%04x", second, first)
end
local function fixture(guild, name)
    local report = {
        name = name or "Sender", guid = "Player-1-" .. guild, guildName = guild,
        race = "HUMAN", faction = "Alliance", members = 6, averageLevel = 60,
        membersLevel60 = 6, activeLevel60 = 6, activePlayers = 6, activeMembers = 6,
        timestamp = time(), classes = { DRUID = 6 }, addonVersion = "0.6.2",
        guildDescription = string.rep("a", 160), guildDescriptionTimestamp = time(),
        guildDescriptionEditedBy = "Editor", rules = {}, classBreakdownMode = "ALL",
    }
    report.payload = serialize(report, true)
    report.checksum = checksum(report.payload)
    return report
end
local function packets(kind, startAt)
    local result = {}
    for index = startAt or 1, #sent do
        local fields = split(sent[index].message)
        if fields[1] == kind then result[#result + 1] = { fields = fields, packet = sent[index] } end
    end
    return result
end
local function discover(reports)
    local before = #sent + 1
    assert(grid:RequestGuildCache(), "start cache discovery")
    advance(0.2)
    local request = assert(packets("CACHE_REQUEST", before)[1], "discovery reaches the transport")
    local id = request.fields[3]
    for _, report in ipairs(reports) do
        receive({ "CACHE_OFFER", "7", id, "Self", report.guildName, report.timestamp, report.checksum, "0" }, "Sender", "GUILD")
    end
    advance(5.2)
    return id
end
local function chunks(report, id)
    local hex = report.payload:gsub(".", function(character) return string.format("%02x", character:byte()) end)
    local total, result = math.ceil(#hex / 100), {}
    assert(total <= 16, "fixture fits the released cache protocol")
    for part = 1, total do
        result[part] = { "CACHE_DATA", "7", id, report.guildName, part, total,
            report.checksum, hex:sub((part - 1) * 100 + 1, part * 100) }
    end
    return result
end
local function stored(guild)
    return iRCDB.globalRaceGrid.servers["forever:" .. addon:GetGuildDirectoryScope()].guildReports[guild:lower()]
end
local function enterCombat()
    combat = true
    addon:EnterLowTrafficMode()
end
local function leaveCombat()
    combat = false
    addon:LeaveLowTrafficMode()
end

-- More than 32 chunks must survive without using the shared 32-task queue.
local reports = {}
for index = 1, 6 do reports[index] = fixture("Queue Guild " .. index) end
local id = discover(reports)
enterCombat()
local chunkCount = 0
for _, report in ipairs(reports) do
    local parts = chunks(report, id)
    receive(parts[1])
    for index = #parts, 1, -1 do receive(parts[index]); chunkCount = chunkCount + 1 end
end
assert(chunkCount > 32, "exercise a burst larger than the old shared queue")
advance(60)
assert(not grid:IsCacheUpdating(), "received saved reports finish without waiting for combat to end")
for _, report in ipairs(reports) do assert(stored(report.guildName), "saved report parsing progresses during combat") end
leaveCombat()
advance(1)
for _, report in ipairs(reports) do
    local saved = assert(stored(report.guildName), "every guild from the same sender is retained")
    assert(saved.guildDescription == report.guildDescription and saved.members == 6, "report contents survive reassembly")
end
assert(not grid:IsCacheUpdating(), "a completed transfer clears the updating state")

-- A partly assembled transfer can finish while the receiver stays in combat.
local partial = fixture("Partial Guild")
id = discover({ partial })
local parts = chunks(partial, id)
receive(parts[1])
advance(0.1)
enterCombat()
advance(5)
for index = 2, #parts do receive(parts[index]) end
advance(2)
assert(stored(partial.guildName), "a partial transfer continues during combat")
advance(45)
leaveCombat()

-- Missing data still expires during combat, so the updating state cannot stick.
id = discover({ fixture("Missing Guild") })
assert(not grid:RequestGuildCache(), "an active discovery is not duplicated")
enterCombat()
advance(16)
assert(not grid:IsCacheUpdating(), "an abandoned transfer also times out during combat")
leaveCombat()
assert(grid:RequestGuildCache(), "an expired request does not block a new discovery")
advance(16)

-- Cached offer selection is safe during combat and no longer restarts just
-- because the client keeps fighting after the discovery window.
local beforeRestart = #sent + 1
assert(grid:RequestGuildCache(), "start discovery before a combat interruption")
advance(0.2)
local oldRequest = packets("CACHE_REQUEST", beforeRestart)[1].fields[3]
local oldOffer = fixture("Expired Peer Offer")
receive({ "CACHE_OFFER", "7", oldRequest, "Self", oldOffer.guildName,
    oldOffer.timestamp, oldOffer.checksum, "0" }, "Sender", "GUILD")
enterCombat()
advance(60)
leaveCombat()
advance(3)
local restarted = packets("CACHE_REQUEST", beforeRestart)
assert(#restarted == 1, "combat does not indefinitely restart cache discovery")
assert(#packets("CACHE_GET", beforeRestart) == 1, "the existing offer is selected during combat")
advance(16)

-- Base reports, descriptions and class details all survive repeated combat;
-- they use saved fields and do not need to wait for another combat gap.
local public = fixture("Public Guild", "Public Sender")
local base = serialize(public, false)
local classes = { "GUILD_CLASS_BREAKDOWN", "7", public.timestamp, "MAX", "60", "60" }
for index = 1, 9 do classes[#classes + 1] = index == 1 and "2" or "0" end
classes[#classes + 1], classes[#classes + 2], classes[#classes + 3] = "NORMAL", "0", ""
enterCombat()
receive({ "GUILD_DESC", "7", public.timestamp, "Editor", "A separate description" }, "Public Sender", "CHANNEL")
receive(classes, "Public Sender", "CHANNEL")
receive(base, "Public Sender", "CHANNEL")
advance(20)
leaveCombat()
advance(1)
enterCombat()
advance(20)
assert(stored(public.guildName), "repeated combat cannot postpone saved report processing")
leaveCombat()
advance(4)
local saved = assert(stored(public.guildName), "the base report survives alongside its extra packets")
assert(saved.guildDescription == "A separate description", "the description was not overwritten by class details")
assert(saved.classBreakdownMode == "MAX" and saved.classBreakdownClasses.DRUID == 2, "class details are applied after the base report")

-- Offer requests from different peers, and GETs for different guilds, are
-- separate jobs too. Repeated GETs must not send a duplicate transfer.
enterCombat()
local beforeOffers = #sent + 1
receive({ "CACHE_REQUEST", "7", "a1" }, "Requester A", "GUILD")
receive({ "CACHE_REQUEST", "7", "b1" }, "Requester B", "GUILD")
advance(7)
local offers, peers = {}, {}
for _, record in ipairs(packets("CACHE_OFFER", beforeOffers)) do
    peers[record.fields[4]] = true
    if record.fields[3] == "a1" then offers[#offers + 1] = record.fields end
end
assert(peers["Requester A"] and peers["Requester B"] and #offers >= 2, "both peers receive saved-data offers during combat")
local beforeData = #sent + 1
for index = 1, 2 do
    local offer = offers[index]
    receive({ "CACHE_GET", "7", "a1", offer[5], offer[6], offer[7] }, "Requester A")
end
advance(10)
assert(#packets("CACHE_DATA", beforeData) > 0, "saved report packets can be sent without live unit reads during combat")
local outgoing = {}
for _, record in ipairs(packets("CACHE_DATA", beforeData)) do
    local fields = record.fields
    outgoing[fields[4]] = (outgoing[fields[4]] or 0) + 1
end
assert(outgoing[offers[1][5]] and outgoing[offers[2][5]], "both guild GETs survive the pause")
local beforeDuplicate = #sent + 1
receive({ "CACHE_GET", "7", "a1", offers[1][5], offers[1][6], offers[1][7] }, "Requester A")
advance(0.5)
assert(#packets("CACHE_DATA", beforeDuplicate) == 0, "duplicate transfer requests remain suppressed")
leaveCombat()
advance(3)

-- Description and class packets can arrive in any order relative to the base.
for index, order in ipairs({ "BCD", "BDC", "CBD", "CDB", "DBC", "DCB" }) do
    local report = fixture("Ordered Guild " .. index, "Order Reporter " .. index)
    local detail = { "GUILD_CLASS_BREAKDOWN", "7", report.timestamp, "MAX", "60", "60" }
    for column = 1, 9 do detail[#detail + 1] = column == 1 and "2" or "0" end
    detail[#detail + 1], detail[#detail + 2], detail[#detail + 3] = "NORMAL", "0", ""
    local messages = {
        B = serialize(report, false), C = detail,
        D = { "GUILD_DESC", "7", report.timestamp, "Editor", "Details " .. index },
    }
    for kind in order:gmatch(".") do receive(messages[kind], report.name, "CHANNEL") end
    advance(1)
    local record = assert(stored(report.guildName), "every packet order retains the base")
    assert(record.guildDescription == "Details " .. index, "description survives packet order " .. order)
    assert(record.classBreakdownMode == "MAX" and record.classBreakdownClasses.DRUID == 2,
        "class details survive packet order " .. order)
end

local invalid = fixture("Invalid Details Guild", "Validated Reporter")
local badClass = { "GUILD_CLASS_BREAKDOWN", "7", invalid.timestamp, "MAX", "60", "60" }
for column = 1, 9 do badClass[#badClass + 1] = column == 1 and "7" or "0" end
badClass[#badClass + 1], badClass[#badClass + 2], badClass[#badClass + 3] = "NORMAL", "0", ""
receive(badClass, invalid.name, "CHANNEL")
receive({ "GUILD_DESC", "7", invalid.timestamp, "Editor", string.rep("x", 161) }, invalid.name, "CHANNEL")
receive({ "GUILD_DESC", "7", invalid.timestamp, "Editor", "Wrong author" }, "Other Reporter", "CHANNEL")
receive(serialize(invalid, false), invalid.name, "CHANNEL")
advance(1)
assert(stored(invalid.guildName).classBreakdownMode == "ALL", "held details cannot exceed the base member total")
assert(stored(invalid.guildName).guildDescription == "", "oversized and wrong-author details remain rejected")

local held = fixture("Held Details Guild", "Held Reporter")
receive({ "GUILD_DESC", "7", held.timestamp, "Editor", "Held through combat" }, held.name, "CHANNEL")
advance(1)
enterCombat()
advance(60)
receive(serialize(held, false), held.name, "CHANNEL")
leaveCombat()
advance(4)
assert(stored(held.guildName).guildDescription == "Held through combat", "held metadata can be matched during local combat")

local expired = fixture("Expired Details Guild", "Expired Reporter")
receive({ "GUILD_DESC", "7", expired.timestamp, "Editor", "Too old" }, expired.name, "CHANNEL")
advance(122)
receive(serialize(expired, false), expired.name, "CHANNEL")
advance(1)
assert(stored(expired.guildName).guildDescription == "", "unmatched metadata expires outside combat")

-- Filling all transfer slots must not evict a partially received report when
-- the next chunk belongs to an existing transfer rather than a new guild.
local interleaved, largest = {}, 0
reports = {}
for index = 1, 32 do reports[index] = fixture("Interleaved Guild " .. index) end
id = discover(reports)
for index, report in ipairs(reports) do
    interleaved[index] = chunks(report, id)
    largest = math.max(largest, #interleaved[index])
end
enterCombat()
for part = 1, largest do
    for _, packetList in ipairs(interleaved) do
        if packetList[part] then receive(packetList[part]) end
    end
end
advance(25)
for _, report in ipairs(reports) do
    assert(stored(report.guildName), "all 32 interleaved transfers survive during combat")
end
assert(not grid:IsCacheUpdating(), "interleaved reports complete during combat")
leaveCombat()
assert(#errors == 0, table.concat(errors, "\n"))
assert(#packets("GUILD_REPORT_ACK") == 0, "receiving public guild reports never sends automatic whisper receipts")

-- A queued public report can outlive its author. It must still be saved, with
-- no attempt to contact the now-offline player after normal or combat work.
for _, fighting in ipairs({ false, true }) do
    local report = fixture(fighting and "Offline Combat Guild" or "Offline Public Guild", "Goldmoon Morbus")
    local before = #sent
    if fighting then enterCombat() end
    receive(serialize(report, true), report.name, "CHANNEL")
    advance(2)
    assert(stored(report.guildName), "a report is stored without a receipt from an online author")
    assert(#sent == before, "public report processing sends no reply to its offline author")
    if fighting then leaveCombat() end
    advance(16)
    assert(#sent == before, "no delayed receipt is left behind after processing or combat")
end
print("PASS: cache queues, combat-aware timeouts, public packet ordering, metadata validation, and silent public report reception")
