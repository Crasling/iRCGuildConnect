-- Exercise the real queue with short combat gaps and no game or network calls.
local now, combat, timers, errors, debugMessages = 0, false, {}, {}, {}
local addon, private = {}, {}
local secret = {}
function GetTime() return now end
function time() return math.floor(now) end
function GetBuildInfo() return "1.60.1", "70374", "", 16001 end
function issecretvalue(value) return value == secret end
function UnitAffectingCombat()
    if combat == "error" then error("combat state unavailable") end
    if combat == "secret" then return secret end
    return combat
end
function InCombatLockdown() return combat == true end
function CreateFrame() return { RegisterEvent = function() end, SetScript = function() end } end
function LibStub(name)
    if name == "AceAddon-3.0" then return { NewAddon = function() return addon end } end
end
function geterrorhandler() return function(err) errors[#errors + 1] = err end end
C_Timer = { After = function(delay, callback) timers[#timers + 1] = { at = now + delay, callback = callback } end }
assert(loadfile("iRC_Core.lua"))("iRC", private)
function addon:DebugMsg(message) debugMessages[#debugMessages + 1] = message end
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
end
local function enter(value) combat = value == nil and true or value; addon:EnterLowTrafficMode() end
local function leave() combat = false; addon:LeaveLowTrafficMode() end

-- Each genuine safe gap runs the oldest protected job immediately. Newer
-- updates keep that job's place instead of moving it to the back of the queue.
local ran = {}
enter()
for index = 1, 16 do
    addon:DeferLowTraffic("ui:protected:" .. index, function()
        assert(combat == false, "protected work never runs in combat")
        ran[#ran + 1] = index
    end)
end
for index = 1, 16 do
    advance(0.1)
    assert(#ran == index - 1, "combat does not release protected work")
    leave()
    assert(#ran == index and ran[index] == index, "a short gap makes fair progress without a cooldown")
    advance(0.01)
    enter()
end
leave()
advance(1)
assert(#ran == 16, "old wakeups cannot repeat completed jobs")

local latest
enter()
addon:DeferLowTraffic("ui:first", function() end)
addon:DeferLowTraffic("ui:latest", function() latest = "old" end)
leave()
advance(0.1)
enter()
addon:DeferLowTraffic("ui:latest", function() latest = "new" end)
advance(0.5)
leave()
assert(latest == "new", "an older drained callback cannot replace a newer update")
advance(1)

enter()
addon:DeferLowTraffic("ui:first", function() end)
addon:DeferLowTraffic("ui:outside", function() latest = "stale" end)
leave()
if not addon:DeferLowTraffic("ui:outside", function() latest = "unused" end) then latest = "live" end
advance(1)
assert(latest == "live", "a fresh out-of-combat update cancels the older queued copy")

-- Saved-data callbacks pass only their own guard. A nested protected request
-- still waits for an actual safe moment.
local sent, protectedReads = {}, 0
local function savedRules(value)
    if addon:DeferLowTraffic("traffic:rules:Guild", function() savedRules(value) end) then return end
    sent[#sent + 1] = value
    addon:DeferLowTraffic("traffic:guild-map-position", function()
        assert(combat == false, "safe reply context cannot unlock live map reads")
        protectedReads = protectedReads + 1
    end)
end
enter()
savedRules("old")
savedRules("latest")
advance(1)
assert(#sent == 1 and sent[1] == "latest" and protectedReads == 0, "saved replies run during combat, coalesced and paced")
for _ = 1, 20 do savedRules("repeat") end
advance(1)
assert(#sent == 2, "a burst of saved updates stays one queued job")
leave()
assert(protectedReads == 1, "the latest protected read runs in the first safe gap")
advance(1)

for _, state in ipairs({ "secret", "error" }) do
    enter(state)
    addon:DeferLowTraffic("ui:unreadable", function() protectedReads = protectedReads + 1 end)
    local before = protectedReads
    advance(1)
    assert(protectedReads == before, "unknown combat state cannot release protected work")
    addon:LeaveLowTrafficMode()
    combat = false
    advance(0.5)
    assert(protectedReads == before + 1 and not addon:IsLowTrafficMode(), "a retry recovers without another combat event")
end

enter()
addon:DeferLowTraffic("ui:fails", function() error("expected queued failure") end)
addon:DeferLowTraffic("ui:continues", function() latest = "continued" end)
leave()
advance(0.5)
assert(#errors == 1 and tostring(errors[1]):find("expected queued failure", 1, true), "callback failures are reported")
assert(latest == "continued", "one failed callback does not stall the queue")
print("PASS: short combat gaps, latest updates, combat-safe replies, secret guards, and queue recovery")
