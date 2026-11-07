-- Real saved-log cleanup and synchronization, without sending network traffic.
local now, sequence = 1800000000, 0
local name = "Spellcaster Forsaken"
local promotion = name .. " was promoted from Dark Initiate to Ghoul."
local attributed = name .. " was promoted from Dark Initiate to Ghoul by Witherbloom Barrows."
local demotion = name .. " was demoted from Ghoul to Dark Initiate."
function time() return now end
function CreateFrame() return { RegisterEvent = function() end, SetScript = function() end } end
local function record(kind, text, at, member)
    sequence = sequence + 1
    return { id = tostring(sequence), eventType = kind, name = member or name, text = text,
        occurredAt = at, classFile = "MAGE" }
end
local function fixture(records)
    local addon = {}
    function addon:GetGuildKey() return "guild" end
    function addon:NormalizeName(value) return tostring(value or ""):lower() end
    function addon:FormatPlayerName(value) return tostring(value or "") end
    function addon:HasGuildPermission() return false end
    function addon:GuildMemberHasPermission() return true end
    function addon:GetGuildMemberRankIndex() return 1 end
    function addon:IsGuildMemberName() return true end
    function addon:IsGuildConnectionActive() return false end
    local store = { guildLog = records or {} }
    iRCDB = { identityGuilds = { guild = store } }
    assert(loadfile("iRC_Identity.lua"))("iRC", { iRC = addon })
    local identity = addon.Identity
    identity:GetGuildLog()
    local function receive(kind, text, at)
        sequence = sequence + 1
        return identity:ReceiveSync({ "IDENT_EVENT", "2", tostring(sequence), tostring(at),
            kind, name, "MAGE", text }, "Trusted Officer")
    end
    return identity, store, receive
end

local identity = fixture({ record("PROMOTE", attributed, now - 420), record("PROMOTE", promotion, now) })
local log = identity:GetGuildLog()
assert(#log == 1 and log[1].text == attributed and log[1].occurredAt == now - 420,
    "the seven-minute duplicate in the screenshot is repaired while keeping the officer and earliest time")

identity = fixture({ record("PROMOTE", promotion, now - 900), record("LEVEL", "Another member leveled.", now - 800, "Other Member"),
    record("PROMOTE", attributed, now) })
log = identity:GetGuildLog()
assert(#log == 2 and log[2].text == attributed and log[2].occurredAt == now - 900,
    "saved cleanup merges delayed attributed observations across unrelated guild activity")

local store, receive
identity, store, receive = fixture({ record("PROMOTE", promotion, now) })
assert(not receive("PROMOTE", attributed, now - 420))
log = identity:GetGuildLog()
assert(#log == 1 and log[1].text == attributed and log[1].occurredAt == now - 420,
    "an older attributed report arriving later enriches the existing event")
assert(not receive("PROMOTE", promotion, now + 1000) and #identity:GetGuildLog() == 1,
    "a delayed plain observation cannot remove officer attribution or create another row")

identity, store, receive = fixture({ record("PROMOTE", promotion, now - 60), record("DEMOTE", demotion, now - 30) })
assert(receive("PROMOTE", promotion, now) and #identity:GetGuildLog() == 3,
    "a real promotion after a demotion remains distinct even within the old two-minute window")
assert(not receive("DEMOTE", demotion, now - 29) and #identity:GetGuildLog() == 3,
    "out-of-order duplicate demotions merge into their own adjacent transition")
local restored = fixture(store.guildLog)
assert(#restored:GetGuildLog() == 3, "genuine promotion/demotion cycles survive saved-log cleanup")

identity, store, receive = fixture({ record("PROMOTE", promotion, now - 1000),
    record("LEAVE", name .. " left the guild.", now - 900),
    record("REJOIN", name .. " rejoined the guild.", now - 800) })
assert(receive("PROMOTE", promotion, now) and #identity:GetGuildLog() == 4,
    "leaving and rejoining separates otherwise identical promotions")

identity, store, receive = fixture()
assert(receive("PROMOTE", attributed, now))
local history = identity:GetMemberHistory(name)
assert(#history.rankHistory == 1 and history.rankHistory[1].toRank == "Ghoul",
    "officer attribution is not included in the destination rank name")
assert(not receive("PROMOTE", promotion, now + 420) and #history.rankHistory == 1,
    "duplicate observations do not add duplicate rank-history entries")
print("Guild rank log tests passed: delayed duplicates, attribution, reload cleanup, real cycles and membership boundaries")
