-- Modern guild-roster races, cached fallbacks and bounded retries. No messages.
local function fixture(count, nativeReady)
    local env, addon, private, frames = {}, {}, {}, {}
    setmetatable(env, { __index = _G }); env._G = env
    local state = { now = 100, timers = {}, lookup = {}, units = {}, reads = 0, nativeReads = 0,
        ready = nativeReady, dirty = 0, refreshes = 0, secret = {}, connection = { active = true, members = {} } }
    local roster, ids = {}, {}
    for index = 1, count do
        ids[index] = index
        roster[index] = { name = "Member " .. index, guid = "Player-1-" .. index }
    end
    env.iRCDB, env.iRCCharDB = {}, {}
    env.GetBuildInfo = function() return "1.60.1", "70790", "", 16001 end
    env.GetTime = function() return state.now end
    env.time = env.GetTime
    env.GetNumGuildMembers = function() return #roster end
    env.GetGuildRosterInfo = function(index)
        local member = roster[index]
        return member.name, "Member", 4, 20, "Warrior", nil, nil, nil, false, nil, "WARRIOR", nil, nil, nil, nil, nil, member.guid
    end
    env.GetGuildInfo = function() return "Example Guild" end
    env.issecretvalue = function(value) return rawequal(value, state.secret) end
    env.LibStub = function(name) if name == "AceAddon-3.0" then return { NewAddon = function() return addon end } end end
    env.CreateFrame = function()
        local frame = { events = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:SetScript(event, callback) self[event] = callback end
        frames[#frames + 1] = frame
        return frame
    end
    env.C_Timer = { After = function(delay, callback)
        state.timers[#state.timers + 1] = { at = state.now + delay, callback = callback }
    end }
    env.C_ChatInfo = { InChatMessagingLockdown = function() return state.locked or false end,
        SendAddonMessage = function() error("race discovery must not send messages") end }
    env.C_Club = {
        GetGuildClubId = function() return state.ready and 99 or nil end,
        GetClubMembers = function() return state.secretMembers and state.secret or ids end,
        GetMemberInfo = function(_, id)
            state.nativeReads = state.nativeReads + 1
            return { guid = roster[id].guid, name = roster[id].name,
                race = state.secretRace and state.secret or (id == 2 and 5 or 1), classID = 8,
                profession1ID = state.secretProfession and state.secret or (id == 2 and 171 or nil),
                profession1Rank = id == 2 and 1 or nil }
        end,
    }
    env.C_CreatureInfo = {
        GetRaceInfo = function(id) return { clientFileString = id == 5 and "Scourge" or "Human" } end,
        GetClassInfo = function() return { classFile = "MAGE", className = "Mage" } end,
    }
    env.GetPlayerInfoByGUID = function(guid)
        state.reads = state.reads + 1
        local race = state.lookup[guid]
        if race == "error" then error("unavailable") end
        return nil, nil, race, race
    end
    env.UnitGUID = function(unit) return state.units[unit] and state.units[unit].guid end
    env.UnitRace = function(unit)
        local race = state.units[unit] and state.units[unit].race
        return race, race
    end
    assert(loadfile("iRC_Core.lua", "t", env))("iRC", private)
    assert(loadfile("Localization/enUS.lua", "t", env))("iRC", private)
    function addon:GetConnection() return state.connection end
    function addon:GetGuildKey() return "example guild" end
    function addon:GetPlayerName() return "Member 1" end
    function addon:IsInGuildConnection() return state.connection ~= nil end
    function addon:IsGuildConnectionActive() return state.connection ~= nil end
    function addon:HasGuildPermission() return false end
    function addon:CheckGuildRosterForNewMembers() end
    function addon:GetLocalProfile() return { name = "Member 1", guid = "Player-1-1", race = "HUMAN", class = "MAGE", level = 20 } end
    function addon:SendAddonTraffic() error("race discovery must not send messages") end
    function addon:DebugMsg() end
    addon.RaceGrid = { MarkLocalReportDirty = function() state.dirty = state.dirty + 1 end }
    addon.MainUI = { frame = { category = "Guild Overview", IsShown = function() return true end },
        RefreshIfShown = function() state.refreshes = state.refreshes + 1 end }
    addon.ConnectionDashboard = { RefreshIfShown = function() end }
    assert(loadfile("iRC_RosterRaces.lua", "t", env))("iRC", private)
    assert(loadfile("iRC_Guild.lua", "t", env))("iRC", private)
    function addon:GetMemberVerification(_, online) return { state = online and "verified" or "offline" } end
    function addon:GetMemberAttentionSince() end
    state.addon, state.env, state.roster = addon, env, roster
    for _, frame in ipairs(frames) do
        if frame.events.PLAYER_TARGET_CHANGED then state.raceEvents = frame end
        if frame.events.GUILD_ROSTER_UPDATE then state.guildEvents = frame end
    end
    function state:advance(seconds)
        local finish = self.now + seconds
        while true do
            table.sort(self.timers, function(a, b) return a.at < b.at end)
            if not self.timers[1] or self.timers[1].at > finish then break end
            local timer = table.remove(self.timers, 1)
            self.now = timer.at
            timer.callback()
        end
        self.now = finish
    end
    function state:row(name)
        for _, row in ipairs(addon:GetGuildRosterRows()) do if row.name == name then return row end end
    end
    return state
end

local test = fixture(1000, true)
local rows = test.addon:GetGuildRosterRows()
assert(#rows == 1000 and test:row("Member 2").race == "Undead" and test:row("Member 2").class == "MAGE",
    "native guild member records supply race and class for offline non-iRC members")
assert(test:row("Member 2").rosterProfession1ID == 171
    and test:row("Member 2").professionData == nil,
    "the roster exposes a profession ID without treating its unreliable rank as iRC skill data")
assert(test.nativeReads == 1000 and test.reads == 0)
test.addon:GetGuildRosterRows()
assert(test.nativeReads == 1000 and #test.timers == 0, "cached pages do not rescan 1,000 club members or start fallback work")
assert(test.connection.memberRaceCache["Player-1-2"] == "SCOURGE")
test.connection.members["member 2"] = { guid = "Player-1-2", race = "Troll", class = "WARRIOR" }
test.addon:InvalidateGuildMemberRow("Member 2")
assert(test:row("Member 2").race == "Undead" and test:row("Member 2").class == "MAGE",
    "native roster race/class take priority over an older addon profile")
test.addon.RosterRaces:LearnProfile(test.connection, test.connection.members["member 2"])
assert(test.connection.memberRaceCache["Player-1-2"] == "SCOURGE")

test = fixture(2, false)
test.connection.members["member 2"] = { race = "Unknown", guid = "Player-1-2", class = "UNKNOWN" }
test.lookup["Player-1-2"] = "Troll"
assert(test:row("Member 2").race == "Unknown")
test:advance(1)
assert(test:row("Member 2").race == "Troll" and test.dirty > 0 and test.refreshes > 0,
    "an Unknown iRC profile no longer blocks the GUID fallback or leaves reports cached")
test.lookup["Player-1-2"] = nil
test.addon:InvalidateGuildMemberRows()
local readsBefore = test.reads
assert(test:row("Member 2").race == "Troll" and test.reads == readsBefore,
    "known GUID races survive API cache misses and row rebuilds")
test.roster[2].guid = "Player-1-ReusedName"
test.addon:InvalidateGuildRosterSnapshot()
assert(test:row("Member 2").race == "Unknown", "a reused name cannot inherit the old character GUID's race")

test = fixture(2, false)
test:row("Member 2")
test.lookup["Player-1-2"] = test.secret
test:advance(1)
assert(test:row("Member 2").race == "Unknown", "secret race values are neither inspected nor saved")
test.units.target = { guid = "Player-1-2", race = "Scourge" }
test.raceEvents.OnEvent(test.raceEvents, "PLAYER_TARGET_CHANGED")
assert(test:row("Member 2").race == "Undead", "a safe unit sighting fills an unresolved guild member race")

test = fixture(2, false)
test:row("Member 2")
test.ready = true
test.guildEvents.OnEvent(test.guildEvents, "CLUB_MEMBERS_UPDATED", 99)
test:advance(1)
assert(test:row("Member 2").race == "Undead", "late native roster data refreshes the existing cached rows")
local nativeBefore = test.nativeReads
test.guildEvents.OnEvent(test.guildEvents, "CLUB_MEMBERS_UPDATED", 100)
test:advance(1)
assert(test.nativeReads == nativeBefore, "unrelated community updates do not rescan the guild")

test = fixture(2, true)
test.locked = true
assert(test:row("Member 2").race == "Unknown" and test.nativeReads == 0,
    "chat lockdown avoids reading restricted native club member tables")
test.locked = false
test.guildEvents.OnEvent(test.guildEvents, "PLAYER_REGEN_ENABLED")
test:advance(1)
assert(test:row("Member 2").race == "Undead", "public native data is retried after combat")

test = fixture(2, false)
test:row("Member 2")
test:advance(1)
test.lookup["Player-1-2"] = "Orc"
local priorReads = test.reads
test:advance(59)
assert(test.reads == priorReads, "unresolved GUIDs observe their retry cooldown")
test:advance(1)
assert(test:row("Member 2").race == "Orc", "later public GUID data refreshes an unchanged roster")

test = fixture(2, true)
test.secretMembers = true
assert(test:row("Member 2").race == "Unknown" and test.nativeReads == 0,
    "a secret native member list is never enumerated")
test.secretMembers, test.secretRace, test.secretProfession = false, true, true
test.addon.RosterRaces:InvalidateNativeMembers()
test.addon:InvalidateGuildRosterSnapshot()
assert(test:row("Member 2").race == "Unknown" and test:row("Member 2").rosterProfession1ID == nil,
    "secret native race and profession IDs are not used as roster data")

test = fixture(1000, false)
test.addon:GetGuildRosterRows()
assert(#test.timers == 1, "1,000 unresolved members share one worker timer")
test:advance(5)
assert(test.reads <= 40, "unknown GUID lookups remain bounded to eight per second")
local oldConnection, oldReads = test.connection, test.reads
test.connection = {}
test:advance(2)
assert(test.reads == oldReads, "pending lookups stop when the guild connection changes")
assert(oldConnection.memberRaceCache["Player-1-1"] == "HUMAN", "per-character GUID evidence stays with its original guild")
print("Roster race tests passed: native offline data, class/race fields, fallback, persistence, secret values, retries and 1,000-member pacing")
