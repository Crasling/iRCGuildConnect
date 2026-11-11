-- Check the real dashboard helpers without creating game frames.
local mode, members = "SELF_FOUND_OR_GUILD_FOUND", {}
local addon = {
    ColorValues = { Orange = { 1, .6, 0 }, Green = { 0, 1, 0 }, Gray = { .5, .5, .5 } },
    Colors = setmetatable({}, { __index = function() return "" end }),
    Identity = { IsPersonalBank = function() return false end },
    IsGuildConnectionActive = function() return true end,
    IsAddonResponseRequired = function() return true end,
    GetConnection = function() return {} end,
    GetConnectionRules = function() return {} end,
    GetProgressionMode = function() return mode end,
    GetMaxLevelProgressionMode = function() return "NONE" end,
    IsGuildFoundProgressionApplicable = function(_, level, selfFound)
        return mode == "GUILD_FOUND" or mode == "SELF_FOUND_OR_GUILD_FOUND" and selfFound ~= true
    end,
    IsLiveAddonState = function(_, state) return state == "verified" end,
    IsAttentionVerificationState = function(_, state) return state == "attention" end,
    GetGuildRosterRows = function() return members end,
    GetClassDisplayName = function(_, value) return value end,
    FormatPlayerName = function(_, value) return value end,
    Text = function(self, key, ...)
        local value = assert(self.L[key], key)
        return select("#", ...) > 0 and string.format(value, ...) or value
    end,
}
local private = { iRC = addon }
assert(loadfile("Localization/enUS.lua"))("iRC", private)
assert(loadfile("iRC_ConnectionDashboard.lua"))("iRC", private)
local dashboard = addon.ConnectionDashboard

-- Use the functions captured by the real UI entry points, rather than copies
-- of their implementation. No test-only functions are exposed by the addon.
local function captured(fn, wanted, seen)
    seen = seen or {}
    if seen[fn] then return end
    seen[fn] = true
    for index = 1, math.huge do
        local name, value = debug.getupvalue(fn, index)
        if not name then return end
        if name == wanted then return value end
        if type(value) == "function" then
            local found = captured(value, wanted, seen)
            if found then return found end
        end
    end
end
local warning = assert(captured(dashboard.Create, "ruleViolationWhisper"))
local materialize = assert(captured(dashboard.RenderVisibleRows, "materializeVerificationRow"))
local member = {
    name = "Drim Spleenstab", level = 26, class = "ROGUE", race = "Undead", selfFound = false,
    profile = {}, addonVersion = "0.7.8", hasParticipationSnapshot = true,
    verification = { state = "verified", label = "iRC response received" },
}
members[1] = member
local function row()
    local data = { verificationMember = member, frame = {}, verificationContext = {
        progressionMode = mode, progressionRulesActive = mode ~= "NONE", usesSelfFound = mode ~= "GUILD_FOUND",
        usesGuildFound = mode == "SELF_FOUND_OR_GUILD_FOUND" or mode == "GUILD_FOUND",
        verificationStates = { [member] = "verified" },
    } }
    materialize(data)
    return data
end

member.raceLockedStatus = { verified = false, clean = true }
assert(row().values[4] == addon.L.RL_UNVERIFIED,
    "an iRC response alone cannot display Guild Found progression as Verified")
assert(dashboard:GetNeedsAttentionCount() == 1)
assert(warning(member), "unverified Guild Found progression can be explained to a member")

member.raceLockedStatus = { verified = true, clean = true }
assert(row().values[4] == addon.L.RL_VERIFIED and row().values[5] == addon.L.RL_CLEAN)
assert(dashboard:GetNeedsAttentionCount() == 0)
assert(warning(member) == nil, "a verified clean member must not receive a false progression warning")

member.selfFound = true
member.raceLockedStatus = false
assert(warning(member) == nil, "active Self-Found satisfies the combined rule")
assert(dashboard:GetNeedsAttentionCount() == 0)
member.raceLockedStatus = { verified = true, clean = false }
assert(warning(member) == nil and row().values[5] == addon.L.VERIFICATION_OK,
    "old Guild Found evidence does not warn against an active Self-Found character")
mode = "NONE"
assert(warning(member) == nil and dashboard:GetNeedsAttentionCount() == 0,
    "paused progression rules do not enforce historical Guild Found monitoring")

mode, member.selfFound = "GUILD_FOUND", true
member.raceLockedStatus = false
assert(warning(member), "the Guild Found-only rule still requires Guild Found eligibility")
member.selfFound = false
member.raceLockedStatus = { verified = true }
assert(row().values[5] == addon.L.RL_STATUS_UNKNOWN,
    "missing monitoring evidence is shown as Unknown rather than OK")
assert(dashboard:GetNeedsAttentionCount() == 1, "unknown required monitoring status needs attention")
member.raceLockedStatus.clean = false
assert(row().values[5] == addon.L.RL_FLAGGED and warning(member))
member.raceLockedStatus.clean = true
assert(row().values[5] == addon.L.RL_CLEAN and warning(member) == nil)
member.verification.state = "offline"
assert(row().values[4] == "" and row().values[5] == "", "offline rows do not claim live verification")
assert(dashboard:GetNeedsAttentionCount() == 0)
addon.Identity.IsPersonalBank = function() return true end
mode, member.verification.state = "SELF_FOUND", "verified"
member.raceLockedStatus = { verified = false, clean = true }
assert(row().values[4] == addon.L.RL_UNVERIFIED and dashboard:GetNeedsAttentionCount() == 1,
    "a personal bank still needs its own Guild Found verification")
member.raceLockedStatus = { verified = true }
assert(row().values[5] == addon.L.RL_STATUS_UNKNOWN and dashboard:GetNeedsAttentionCount() == 1,
    "a personal bank with missing monitoring evidence is not shown as clean")
member.raceLockedStatus.clean = true
assert(row().values[4] == addon.L.RL_VERIFIED and dashboard:GetNeedsAttentionCount() == 0,
    "a verified clean personal bank is shown as verified")
print("PASS: progression labels, monitoring state, attention counts, and member warnings use saved evidence")
