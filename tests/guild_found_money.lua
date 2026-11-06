-- Exercise the real money checkpoint handler across independent login sessions.
local now, wallet, frame, timers, tickers, secret, moneyReads
local logs = {}
local addon = {
    Name = "iRC",
    NormalizeName = function(_, name) return name:lower() end,
    GetPlayerName = function() return "Checkpoint Tester" end,
    IsGuildFoundEconomyActive = function() return true end,
    IsGuildConnectionActive = function() return false end,
    IsLowTrafficMode = function() return false end,
    DeferLowTraffic = function() return false end,
    GetSelfFoundState = function() return false end,
    GetStartupTrafficDelay = function() return 3 end,
    HasSecretValues = function(_, value) return value == secret and secret ~= nil end,
    Text = function(_, key, ...) return key .. " " .. table.concat({ ... }, " ") end,
    DebugMsg = function(_, text) logs[#logs + 1] = text end,
}
function GetTime() return now end
function time() return 1800000000 + math.floor(now) end
function GetMoney() moneyReads = moneyReads + 1; return wallet end
function UnitLevel() return 10 end
function CreateFrame()
    frame = { RegisterEvent = function() end, SetScript = function(self, key, callback) self[key] = callback end }
    return frame
end
C_Timer = {
    After = function(delay, callback) timers[#timers + 1] = { at = now + delay, callback = callback } end,
    NewTicker = function(_, callback) tickers[#tickers + 1] = callback end,
}
local function advance(seconds)
    local target = now + seconds
    while true do
        local selected
        for index, timer in ipairs(timers) do
            if timer.at <= target and (not selected or timer.at < timers[selected].at) then selected = index end
        end
        if not selected then break end
        local timer = table.remove(timers, selected)
        now = timer.at
        timer.callback()
    end
    now = target
end
local function fire(event) frame.OnEvent(frame, event) end
local function session(money, saved)
    now, wallet, timers, tickers, secret, moneyReads = 0, money, {}, {}, nil, 0
    iRCCharDB = saved or {}
    assert(loadfile("iRC_RaceLockedSync.lua"))("iRC", { iRC = addon })
    return addon.RaceLockedSync
end

session(0)
fire("PLAYER_LOGIN")
advance(5)
wallet = 4
fire("PLAYER_MONEY")
assert(iRCCharDB.guildFoundHistory.money == 4, "a vendor sale saves on PLAYER_MONEY")
fire("MERCHANT_CLOSED")
advance(0.5)
assert(iRCCharDB.guildFoundHistory.moneyLastLogReason == "MERCHANT_CLOSED_SETTLED")
fire("PLAYER_LOGOUT")
local saved = iRCCharDB
session(4, saved)
fire("PLAYER_LOGIN")
advance(5)
assert(not iRCCharDB.guildFoundHistory.moneyDiscrepancyAt, "ordinary sale/logout/login stays clean")

-- A real unexplained balance change must still be detected.
fire("PLAYER_LOGOUT")
session(8, saved)
fire("PLAYER_LOGIN")
advance(5)
assert(iRCCharDB.guildFoundHistory.discrepancyReason == "MONEY_MISMATCH")
assert(iRCCharDB.guildFoundHistory.moneyBeforeDiscrepancy == 4)
assert(iRCCharDB.guildFoundHistory.moneyAfterDiscrepancy == 8)

-- The reported Forever failure: the wallet becomes zero during logout even
-- though the last vendor sale was correctly saved as six copper.
session(4)
fire("PLAYER_LOGIN")
advance(5)
wallet = 6
fire("PLAYER_MONEY")
fire("MERCHANT_CLOSED")
advance(0.5)
local history = iRCCharDB.guildFoundHistory
local checkpointAt, checkpointReason, checkpointSeal = history.moneyLastLoggedAt, history.moneyLastLogReason, history.rk
wallet = 0
local readsBeforeLogout = moneyReads
fire("PLAYER_LOGOUT")
assert(history.money == 6, "logout must preserve the six-copper vendor checkpoint")
assert(moneyReads == readsBeforeLogout, "logout must not read a wallet that is already being torn down")
assert(history.moneyLastLoggedAt == checkpointAt and history.moneyLastLogReason == checkpointReason
    and history.rk == checkpointSeal, "retaining a checkpoint must also retain its original time, source, and seal")
saved = iRCCharDB
session(6, saved)
fire("PLAYER_LOGIN")
advance(5)
assert(not iRCCharDB.guildFoundHistory.moneyDiscrepancyAt, "six copper survives logout and login without a false flag")

-- Delayed merchant callbacks and late money events must not write during
-- world teardown. Normal checkpoint updates resume after entering the world.
session(6)
fire("PLAYER_LOGIN")
advance(5)
fire("MERCHANT_CLOSED")
fire("PLAYER_LEAVING_WORLD")
wallet = 0
local readsBeforeLeaving = moneyReads
fire("PLAYER_MONEY")
advance(0.5)
tickers[1]()
assert(iRCCharDB.guildFoundHistory.money == 6 and moneyReads == readsBeforeLeaving,
    "late events, settled callbacks, and watchdogs cannot overwrite the frozen checkpoint")
fire("PLAYER_ENTERING_WORLD")
wallet = 7
fire("PLAYER_MONEY")
assert(iRCCharDB.guildFoundHistory.money == 7, "normal updates resume after zoning")

-- A genuine zero saved while playing stays valid across the same lifecycle.
wallet = 0
fire("PLAYER_MONEY")
fire("PLAYER_LEAVING_WORLD")
fire("PLAYER_LOGOUT")
session(0, iRCCharDB)
fire("PLAYER_LOGIN")
advance(5)
assert(iRCCharDB.guildFoundHistory.money == 0 and not iRCCharDB.guildFoundHistory.moneyDiscrepancyAt)

-- Freezing the checkpoint must not repair edits or erase existing evidence.
session(6)
fire("PLAYER_LOGIN")
advance(5)
history = iRCCharDB.guildFoundHistory
history.money = 9
wallet = 0
fire("PLAYER_LOGOUT")
session(6, iRCCharDB)
fire("PLAYER_LOGIN")
advance(5)
assert(iRCCharDB.guildFoundHistory.discrepancyReason == "SNAPSHOT_MISMATCH",
    "an edited open checkpoint is still detected against its saved seal")
local discrepancyAt = iRCCharDB.guildFoundHistory.moneyDiscrepancyAt
fire("PLAYER_LOGOUT")
session(6, iRCCharDB)
fire("PLAYER_LOGIN")
advance(5)
assert(iRCCharDB.guildFoundHistory.moneyDiscrepancyAt == discrepancyAt,
    "a normal relog does not erase earlier audit evidence or create another discrepancy")

session(0)
fire("PLAYER_MONEY")
assert(iRCCharDB.guildFoundHistory == nil, "money events before PLAYER_LOGIN cannot initialize a checkpoint")
fire("PLAYER_LOGIN")
wallet = 4
advance(5)
assert(iRCCharDB.guildFoundHistory.money == 4)

-- Unavailable or restricted reads must not replace a usable checkpoint.
wallet = nil
fire("PLAYER_MONEY")
assert(iRCCharDB.guildFoundHistory.money == 4)
secret, wallet = {}, nil
wallet = secret
fire("PLAYER_MONEY")
assert(iRCCharDB.guildFoundHistory.money == 4)
secret, wallet = nil, 0
fire("PLAYER_MONEY")
assert(iRCCharDB.guildFoundHistory.money == 0, "spending the last copper is a valid checkpoint")

-- A failed first read is retried rather than leaving the entire session unmonitored.
local sync = session(nil)
fire("PLAYER_LOGIN")
advance(5)
wallet = 9
tickers[1]()
assert(iRCCharDB.guildFoundHistory.money == 9)
assert(sync:SaveCurrentMoney("TEST"))
-- Keep separate incidents together with their own money and played samples.
wallet = 6
assert(sync:FlagMonitoringDiscrepancy("MONEY_MISMATCH", 0, 6, time() - 15))
history = iRCCharDB.guildFoundHistory
local oldStamp, oldSampleAt = history.moneyDiscrepancyAt, history.moneyAfterDiscrepancyAt
history.playedBeforeDiscrepancy, history.playedAfterDiscrepancy = 100, 170
history.playedBeforeDiscrepancyAt, history.playedAfterDiscrepancyAt = time() - 70, time()
advance(60)
wallet = 10
fire("PLAYER_MONEY")
local tradeStarted = time()
advance(1)
assert(sync:FlagMonitoringDiscrepancy("TRADE_BLOCK_BYPASS", 10, 10, tradeStarted))
assert(history.moneyBeforeDiscrepancy == 10 and history.moneyAfterDiscrepancy == 10
    and history.moneyBeforeDiscrepancyAt == tradeStarted and history.moneyAfterDiscrepancyAt == time(),
    "the later trade uses its own ten-copper balance and timestamps")
assert(history.discrepancyReason == "TRADE_BLOCK_BYPASS" and history.playedBeforeDiscrepancy == nil,
    "a new reason cannot inherit an older issue's played-time evidence")
local old = assert(history.discrepancyHistory[1])
assert(old.tamperAt == oldStamp and old.moneyBefore == 0 and old.moneyAfter == 6
    and old.moneyAfterAt == oldSampleAt and old.discrepancyReason == "MONEY_MISMATCH" and old.playedAfter == 170,
    "the original logout evidence is preserved in a separate history record")
for _ = 1, 12 do sync:FlagMonitoringDiscrepancy("TRADE_BLOCK_BYPASS", 10, 10, time()) end
assert(#history.discrepancyHistory == 10, "incident history is bounded")
assert(#logs > 0, "checkpoint diagnostics explain the event and validation result")
print("Guild Found money tests passed: sales, logout teardown, zoning, real zero, tampering, evidence retention, startup guards, safe reads, and retry.")
