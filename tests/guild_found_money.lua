-- Exercise the real money checkpoint handler across independent login sessions.
local now, wallet, frame, timers, tickers, secret, moneyReads, playedRequests, cancelledTickers
local monitoringActive, characterName
local logs, notices = {}, {}
local addon = {
    Name = "iRC",
    NormalizeName = function(_, name) return name:lower() end,
    GetPlayerName = function() return characterName end,
    IsGuildFoundEconomyActive = function() return monitoringActive end,
    IsGuildConnectionActive = function() return false end,
    IsLowTrafficMode = function() return false end,
    DeferLowTraffic = function() return false end,
    GetSelfFoundState = function() return false end,
    GetStartupTrafficDelay = function() return 3 end,
    HasSecretValues = function(_, value) return value == secret and secret ~= nil end,
    Text = function(_, key, ...) return key .. " " .. table.concat({ ... }, " ") end,
    DebugMsg = function(_, text) logs[#logs + 1] = text end,
    Print = function(_, text) notices[#notices + 1] = text end,
}
function GetTime() return now end
function time() return 1800000000 + math.floor(now) end
function GetMoney() moneyReads = moneyReads + 1; return wallet end
function RequestTimePlayed() playedRequests = playedRequests + 1 end
function UnitLevel() return 10 end
function CreateFrame()
    frame = { RegisterEvent = function() end, SetScript = function(self, key, callback) self[key] = callback end }
    return frame
end
C_Timer = {
    After = function(delay, callback) timers[#timers + 1] = { at = now + delay, callback = callback } end,
    NewTicker = function(_, callback)
        local ticker = { Cancel = function(self)
            if not self.cancelled then cancelledTickers = cancelledTickers + 1 end
            self.cancelled = true
        end }
        tickers[#tickers + 1] = function() if not ticker.cancelled then callback() end end
        return ticker
    end,
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
local function fire(event, ...) frame.OnEvent(frame, event, ...) end
local function session(money, saved, active, name)
    now, wallet, timers, tickers, secret, moneyReads = 0, money, {}, {}, nil, 0
    playedRequests, cancelledTickers = 0, 0
    notices = {}
    monitoringActive, characterName = active ~= false, name or "Checkpoint Tester"
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

-- WoW reloads per-character SavedVariables on a character switch. Share an
-- account DB while swapping those stores and the real name-based seals.
local firstCharacter = iRCCharDB
local firstHistory, firstBalance, firstIssue = history, history.money, history.moneyDiscrepancyAt
local sharedAccount = { connections = {} }
iRCDB = sharedAccount
local logStart = #logs
sync = session(82, { guildFoundHistory = { money = 0, moneyMonitoringActive = false,
    moneyLastLogReason = "PLAYER_LOGOUT", moneyLastLoggedAt = time() - 300 } }, false, "Unguilded Other")
fire("PLAYER_LOGIN"); advance(5)
local otherCharacter = iRCCharDB
assert(otherCharacter.guildFoundHistory.money == 0 and not otherCharacter.guildFoundHistory.moneyMonitoringActive
    and not otherCharacter.guildFoundHistory.moneyDiscrepancyAt,
    "an inactive character can have a different balance without a Guild Found discrepancy")
assert(firstCharacter.guildFoundHistory == firstHistory and firstHistory.money == firstBalance
    and firstHistory.moneyDiscrepancyAt == firstIssue,
    "another character's login cannot change the first character's checkpoint or flags")
assert(#logs == logStart, "an inactive character receives no gold-monitoring messages")
wallet = 95; fire("PLAYER_MONEY"); fire("PLAYER_LOGOUT")
sync = session(firstBalance, firstCharacter, true, "Checkpoint Tester")
fire("PLAYER_LOGIN"); advance(5)
assert(iRCCharDB == firstCharacter and iRCCharDB.guildFoundHistory.moneyDiscrepancyAt == firstIssue,
    "returning to the monitored character restores only that character's existing evidence")
assert(otherCharacter.guildFoundHistory.money == 0 and not otherCharacter.guildFoundHistory.moneyDiscrepancyAt,
    "the second character's balance and clean state remain independent")
assert(iRCDB == sharedAccount and next(sharedAccount.connections) == nil and sharedAccount.guildFoundHistory == nil,
    "gold history is never stored in the shared account database")

-- An unguilded/inactive character must not read the wallet, write checkpoints,
-- request /played, or keep monitoring tickers alive at all.
sync = session(82, nil, false, "Unguilded Other")
fire("PLAYER_LOGIN"); advance(7)
for _, event in ipairs({ "PLAYER_MONEY", "MERCHANT_SHOW", "MERCHANT_CLOSED", "TRADE_SHOW", "TRADE_CLOSED",
    "MAIL_SHOW", "MAIL_CLOSED", "LOOT_OPENED", "LOOT_CLOSED", "QUEST_TURNED_IN" }) do fire(event) end
advance(2)
sync:RefreshMoneyMonitoring()
sync:CheckLocalMoneySnapshot()
assert(not sync:RequestHiddenTimePlayed())
fire("TIME_PLAYED_MSG", 99999, 1000)
fire("PLAYER_LOGOUT")
assert(moneyReads == 0 and playedRequests == 0 and #tickers == 0,
    "inactive characters perform no gold reads, played requests, or periodic monitoring")
assert(#notices == 0, "inactive characters receive no Guild Found warning")
assert(not iRCCharDB.guildFoundHistory or not iRCCharDB.guildFoundHistory.money,
    "ordinary money and interaction events cannot create an inactive money checkpoint")

-- Becoming subject to Guild Found after login starts a fresh audit; leaving
-- it cancels pending requests and preserves the last monitored checkpoint.
sync = session(82, { guildFoundHistory = { money = 0, moneyMonitoringActive = false, playedTotal = 1,
    playedExpectedAtExit = 1 } }, false)
fire("PLAYER_LOGIN"); advance(7)
monitoringActive = true
sync:RefreshMoneyMonitoring(); advance(1)
history = iRCCharDB.guildFoundHistory
assert(history.money == 82 and history.moneyMonitoringActive and playedRequests == 1,
    "activating Guild Found starts wallet and played monitoring after an inactive login")
assert(#notices == 1 and notices[1]:find("GUILD_FOUND_MONITORING_NOTICE", 1, true),
    "active Guild Found shows one general monitoring notice")
sync:RefreshMoneyMonitoring(); fire("PLAYER_MONEY")
assert(#notices == 1, "routine monitoring updates do not repeat the player notice")
fire("TIME_PLAYED_MSG", 10000, 100)
assert(not history.moneyDiscrepancyAt, "time spent outside Guild Found cannot become a played-time discrepancy")
assert(sync:RequestHiddenTimePlayed())
local readsAtStop, requestsAtStop, savedBalance = moneyReads, playedRequests, history.money
monitoringActive = false
fire("PLAYER_GUILD_UPDATE", "player"); advance(0)
assert(cancelledTickers == 2, "leaving the Guild Found guild cancels both monitoring tickers")
wallet = 120
for _, tick in ipairs(tickers) do tick() end
fire("PLAYER_MONEY"); fire("TIME_PLAYED_MSG", 20000, 200); advance(20)
assert(moneyReads == readsAtStop and playedRequests == requestsAtStop and history.money == savedBalance,
    "stopping Guild Found cancels timers and ignores late responses without reading or saving gold")
assert(not history.moneyDiscrepancyAt and not history.moneyMonitoringActive,
    "a late played reply after leaving Guild Found cannot flag the character")
assert(history.moneyMonitoringEverActive and history.moneyMonitoringPausedAt
    and history.playedExpectedAtExit,
    "pausing preserves this character's protected history and played-time checkpoint")
monitoringActive = true
logStart = #logs
sync:RefreshMoneyMonitoring(); advance(1)
assert(history.discrepancyReason == "MONEY_MISMATCH" and history.moneyBeforeDiscrepancy == 82
    and history.moneyAfterDiscrepancy == 120 and history.moneyDiscrepancySilentAt == history.moneyDiscrepancyAt,
    "reactivation compares against the paused protected checkpoint and retains silent review evidence")
local resumedCharacter = iRCCharDB
sync = session(120, resumedCharacter)
fire("PLAYER_LOGIN"); advance(6)
history = iRCCharDB.guildFoundHistory
fire("TIME_PLAYED_MSG", 20000, 200)
assert(history.discrepancyReason == "PLAYED_GAP" and history.moneyDiscrepancySilentAt == history.moneyDiscrepancyAt,
    "resumed played-time evidence stays silent across a reload before the reply arrives")
for index = logStart + 1, #logs do
    assert(not logs[index]:find("GF_AUDIT_VALIDATION", 1, true), "resume checks do not announce their comparison")
end

-- Actual gaps while monitoring is enabled must still be detected.
sync = session(10, { guildFoundHistory = { money = 10, moneyMonitoringActive = true,
    playedTotal = 100, playedExpectedAtExit = 100, playedExpectedAtExitAt = time() - 300 } })
fire("PLAYER_LOGIN"); advance(6)
fire("TIME_PLAYED_MSG", 500, 100)
assert(iRCCharDB.guildFoundHistory.discrepancyReason == "PLAYED_GAP",
    "enabled Guild Found monitoring still detects an unexplained played-time gap")

sync = session(0, nil, false)
fire("PLAYER_LOGIN"); advance(2)
monitoringActive, wallet = true, 10
sync:RefreshMoneyMonitoring()
assert(moneyReads == 0, "activating during login cannot bypass the wallet settling period")
advance(4)
assert(iRCCharDB.guildFoundHistory.money == 10 and not iRCCharDB.guildFoundHistory.moneyDiscrepancyAt,
    "activation during login establishes the settled wallet as a fresh baseline")

sync = session(8, { guildFoundHistory = { money = 4, moneyMonitoringActive = true,
    playedExpectedAtExit = 100 } }, false)
sync:RefreshMoneyMonitoring()
fire("PLAYER_LOGIN"); advance(3)
assert(iRCCharDB.guildFoundHistory.moneyMonitoringActive and iRCCharDB.guildFoundHistory.playedExpectedAtExit == 100,
    "an unresolved guild during early login cannot discard the saved monitoring continuity")
monitoringActive = true
sync:RefreshMoneyMonitoring(); advance(2)
assert(iRCCharDB.guildFoundHistory.discrepancyReason == "MONEY_MISMATCH",
    "late guild resolution still compares a protected character against its real saved checkpoint")
assert(#logs > 0, "checkpoint diagnostics explain the event and validation result")
print("Guild Found money tests passed: per-character isolation, inactive guards, timer cancellation, late replies, activation, money/played discrepancies, and checkpoint lifecycle.")
