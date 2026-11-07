local function key(instance, server, map) return tostring(server) .. "-" .. tostring(instance) .. "-" .. tostring(map) end
-- Two independent clients must agree on their own panels after book exchange.
local epoch, secret = 1800000000, {}
local function client(name)
    local env, addon, clock = {}, { LayerWireVersion = "8", Prefix = "iRCConnV1" }, 100
    local combat, hidden, mapId, unitReads = false, false, 1415, 0
    local timers, tickers, frames, members = {}, {}, {}, {}
    local requests, broadcasts, redraws, displays = 0, 0, 0, 0
    setmetatable(env, { __index = _G })
    env._G = env
    function env.GetTime() return clock end
    function env.time() return epoch + clock end
    env.GetServerTime = env.time
    function env.UnitName(unit)
        unitReads = unitReads + 1
        return unit == "player" and name or members[tonumber(unit:match("%d+$"))]
    end
    env.GetUnitName = env.UnitName
    function env.IsInRaid() return false end
    function env.GetNumSubgroupMembers() return #members end
    function env.GetNumGroupMembers() return #members + 1 end
    function env.UnitPlayerControlled() return false end
    env.C_Secrets = { ShouldUnitIdentityBeSecret = function() return hidden end }
    env.C_Map = {
        GetBestMapForUnit = function() return mapId end,
        GetMapInfo = function() return { mapType = 3 } end,
    }
    function env.strsplit(separator, text)
        local parts = {}
        for part in text:gmatch("[^" .. separator .. "]+") do parts[#parts + 1] = part end
        return table.unpack(parts)
    end
    function env.CreateFrame()
        local frame = { scripts = {} }
        function frame:RegisterEvent() end
        function frame:SetScript(event, callback) self.scripts[event] = callback end
        frames[#frames + 1] = frame
        return frame
    end
    env.C_Timer = {
        After = function(delay, callback) timers[#timers + 1] = { at = clock + delay, run = callback } end,
        NewTicker = function(_, callback) tickers[#tickers + 1] = callback; return { Cancel = function() end } end,
    }
    function addon:IsSecretValue(value) return value == secret end
    function addon:HasSecretValues(...)
        for index = 1, select("#", ...) do if select(index, ...) == secret then return true end end
        return false
    end
    function addon:NormalizeName(value) return (value or ""):lower() end
    function addon:IsForeverClient() return true end
    function addon:IsCombatTrafficBlocked() return combat end
    function addon:GetSettings() return { showLayerPanel = false } end
    function addon:GetPlayerName() return name end
    function addon:GetGuildKey() return "guild" end
    function addon:IsGuildMemberName() return true end
    function addon:IsGuildConnectionActive() return true end
    function addon:GetConnectionRules() return { guildMapEnabled = true } end
    function addon:AcceptIncomingAddonTraffic() return true end
    function addon:FormatPlayerName(value) return value end
    function addon:DebugMsg() end
    addon.RaceGrid = {
        IsLayerChannelReady = function() return true end,
        RequestLayerAssignment = function() requests = requests + 1; return true end,
        BroadcastLayerState = function() broadcasts = broadcasts + 1; return true end,
    }
    assert(loadfile("iRC_LayerRegistry.lua", "t", env))("iRC", { iRC = addon })
    assert(loadfile("iRC_GuildMap.lua", "t", env))("iRC", { iRC = addon })
    local map, registry, events = addon.GuildMap, addon.LayerRegistry, frames[#frames]
    function map:UpdatePins() redraws = redraws + 1 end
    function map:UpdateLocalLayerDisplay() displays = displays + 1 end
    local result = { map = map, registry = registry }
    function result.advance(seconds)
        local target = clock + seconds
        while true do
            local first
            for index, timer in ipairs(timers) do
                if timer.at <= target and (not first or timer.at < timers[first].at) then first = index end
            end
            if not first then break end
            local timer = table.remove(timers, first)
            clock = timer.at
            timer.run()
        end
        clock = target
    end
    function result.evidence(raw)
        for index = 1, 3 do
            env.UnitGUID = function() return "Creature-0-4621-" .. raw .. "-2-100-" .. index end
            map:ObserveLocalLayer("target", "target")
        end
    end
    function result.guid(value)
        env.UnitGUID = function() return value end
        return map:ObserveLocalLayer("target", "target")
    end
    function result.observe(raw)
        result.evidence(raw)
        result.advance(2)
    end
    function result.merge(rows, server, zone)
        registry:Merge(server or 4621, zone or 1415, rows)
        return map:OnLayerRegistryMerged(server or 4621, zone or 1415)
    end
    function result.event(event, ...) events.scripts.OnEvent(events, event, ...) end
    function result.group(list) members = list; result.event("GROUP_ROSTER_UPDATE") end
    function result.block(value, secretIdentity) combat, hidden = value, secretIdentity end
    function result.zone(value) mapId = value end
    function result.counts() return requests, broadcasts, redraws, displays, unitReads end
    function result.rawState(raw, number, sender, server, zone)
        return map:ReceiveLayerState({ "LAYER_STATE", "8", "4", tostring(server or 4621), tostring(raw),
            tostring(zone or 1415), tostring(number), "", tostring(server or 4621) .. "-4" }, sender)
    end
    return result
end

local a, b = client("Alpha Paladin"), client("Beta Paladin")
assert(b.registry:Claim(key(222, 4621, 1415), 4621, 1415, 1, "Beta Paladin", epoch + 90, epoch + 100))
a.observe(111)
b.observe(111)
assert(a.map:GetLocalLayer().number == 1 and b.map:GetLocalLayer().number == 2,
    "different discovery histories reproduce the original own-panel mismatch")
assert(a.rawState(111, 2, "Beta Paladin") and b.rawState(111, 1, "Alpha Paladin"))
assert(a.rawState(222, 1, "Third Paladin"))
assert(not a.registry:GetNumber(key(222, 4621, 1415), 4621, 1415), "a bare v7 state never invents registry claim metadata")
local aRows, bRows = a.registry:Export(4621, 1415), b.registry:Export(4621, 1415)
a.merge(bRows)
b.merge(aRows)
assert(a.map:GetLocalLayer().number == 2 and b.map:GetLocalLayer().number == 2,
    "both own panels follow the same merged book")
assert(a.map:GetUserLayer("Beta Paladin").number == 2 and b.map:GetUserLayer("Alpha Paladin").number == 2,
    "own panels and matching peers agree after collision repair")
assert(a.map:GetUserLayer("Third Paladin").number == 1, "all peer raw identities are refreshed from the merged scope")
assert(a.registry:GetNumber(key(222, 4621, 1415), 4621, 1415) == 1 and b.registry:GetNumber(key(222, 4621, 1415), 4621, 1415) == 1,
    "another raw identity keeps a unique number")
local requests, broadcasts, redraws = a.counts()
assert(not a.merge(b.registry:Export(4621, 1415)), "duplicate rows do not redraw the view")
a.rawState(111, 1, "Beta Paladin")
a.advance(60)
assert(a.map:GetLocalLayer().number == 2, "old reported aliases cannot undo agreement")
local afterRequests, afterBroadcasts = a.counts()
assert(afterRequests == requests and afterBroadcasts == broadcasts,
    "merges, old states, and elapsed time never create another network check")

local beforeOwn = a.map:GetLocalLayer().number
assert(a.rawState(111, 8, "Different Zone", 4621, 1416))
assert(a.rawState(111, 9, "Different Server", 9999, 1415))
assert(a.map:GetLocalLayer().number == beforeOwn, "different map and server scopes never change the own layer")

local c = client("Candidate Paladin")
c.evidence(333)
assert(not c.map:GetLocalLayer(), "new raw evidence waits for the bounded lookup")
c.rawState(333, 8, "Unconfirmed Paladin")
assert(not c.registry:GetNumber(key(333, 4621, 1415), 4621, 1415), "a bare state cannot confirm a pending candidate")
c.merge({ { identityKey = key(333, 4621, 1415), preferredNumber = 3, owner = "remote paladin",
    createdAt = epoch + 90, observedAt = epoch + 100 } })
c.advance(2)
assert(c.map:GetLocalLayer().number == 3 and c.map:GetLocalLayer().provisional == false,
    "a valid lookup book finalizes the pending candidate with its established number")

a.map:ClearLocalLayer()
local cachedRequests = a.counts()
a.observe(111)
assert(a.counts() == cachedRequests + 1, "a newly confirmed raw set queries once even when its claim is cached")
a.observe(111)
assert(a.counts() == cachedRequests + 1, "fresh NPC evidence for the current route does not query again")

local currentRequests, _, _, _, reads = a.counts()
a.group({ "Beta Paladin" })
assert(a.map:GetLayerGroupDistribution() == "PARTY" and a.map:IsLayerGroupMember("Beta Paladin"),
    "group transport uses readable cached membership")
assert(a.counts() == currentRequests + 1, "joining a group compares books once")
a.group({ "Beta Paladin" })
assert(a.counts() == currentRequests + 1, "an unchanged group does not repeat the query")
a.block(true, false)
local _, _, _, _, beforeBlocked = a.counts()
a.group({ "Gamma Paladin" })
assert(not a.map:GetLayerGroupDistribution() and not a.map:IsLayerGroupMember("Beta Paladin"),
    "a combat-deferred roster invalidates receive trust")
local _, _, _, _, afterBlocked = a.counts()
assert(beforeBlocked == afterBlocked, "combat roster changes never read native unit names")
a.block(false, false)
a.event("PLAYER_REGEN_ENABLED")
assert(a.map:IsLayerGroupMember("Gamma Paladin") and not a.map:IsLayerGroupMember("Beta Paladin"),
    "the deferred roster is rebuilt after combat")
a.block(false, true)
local _, _, _, _, beforeSecret = a.counts()
a.group({ "Secret Paladin" })
local _, _, _, _, afterSecret = a.counts()
assert(not a.map:GetLayerGroupDistribution() and beforeSecret == afterSecret,
    "secret identities block native name reads and group trust")
a.block(false, false)

assert(a.rawState(333, 3, "Moving Paladin"))
a.event("CHAT_MSG_ADDON", "iRCConnV1", "MAP_LAYER\t2\t1416\t4\t4621\t8", "GUILD", "Moving Paladin")
local moved = assert(a.map:GetUserLayer("Moving Paladin"))
assert(moved.mapId == 1416 and moved.number == 4 and not moved.zoneUID,
    "a number-only map update clears the old zone's raw identity")
assert(a.rawState(333, 3, "Moving Paladin"))
assert(a.map:ReceiveLayerTransition({ "LAYER_TRANSITION", "8", "1415" }, "Moving Paladin"))
a.event("CHAT_MSG_ADDON", "iRCConnV1", "MAP_LAYER\t2\t1415\t6\t4621\t9", "GUILD", "Moving Paladin")
assert(not a.map:GetUserLayer("Moving Paladin").zoneUID,
    "a number-only update after shard transfer cannot resurrect the previous raw identity")
local previous = a.map:GetUserLayer("Moving Paladin").instanceId
a.event("CHAT_MSG_ADDON", "iRCConnV1", "MAP_LAYER\t1\t1415\t1", "GUILD", "Moving Paladin")
assert(a.map:GetUserLayer("Moving Paladin").instanceId == previous,
    "old map-layer numbers cannot overwrite the new reference metadata")

print("PASS: independent own-panel convergence, collision repair, idempotence, one-shot queries, scope isolation, cached group trust, combat/secret guards, and legacy raw identity cleanup")

-- These are the two GUIDs measured on the same NPC by the live clients.
local crasling, moofin = client("Crasling Mordaine"), client("Evil Moofin")
crasling.zone(1420)
moofin.zone(1420)
local firstGUID = "Creature-0-7098-0-2-246378-3E9E2142A4"
local secondGUID = "Creature-0-7098-0-4-246378-906a87b9ac"
for _, entry in ipairs({ { crasling, firstGUID }, { moofin, secondGUID } }) do
    local peer, guid = entry[1], entry[2]
    assert(not peer.guid(guid), "one visible NPC is not enough evidence")
    assert(not peer.guid((guid:gsub("246378", "246379"))))
    assert(peer.guid((guid:gsub("246378", "246380"))))
    peer.advance(2)
    assert(peer.map:GetLocalLayer().identityKey == "7098-0-1420")
end
assert(crasling.map:GetLocalLayer().zoneUID == 2 and moofin.map:GetLocalLayer().zoneUID == 4)
assert(crasling.map:GetLocalLayer().number == moofin.map:GetLocalLayer().number,
    "different client-local ZoneUID values share the same server/instance/map label")
local beforeRequests = crasling.counts()
assert(crasling.guid((secondGUID:gsub("246378", "123456"))))
assert(crasling.counts() == beforeRequests, "changing NPC type or local ZoneUID never starts another lookup")
assert(#crasling.registry:Export(7098, 1420) == 1, "one shared reference does not create multiple registry rows")

local expired = client("Expiry Paladin")
expired.registry:Claim("4621-1-1415", 4621, 1415, 1, "old owner", epoch - 3500, epoch - 3490)
expired.registry:Claim("4621-111-1415", 4621, 1415, 1, "current owner", epoch + 90, epoch + 100)
expired.observe(111)
assert(expired.map:GetLocalLayer().number == 2)
expired.advance(12)
assert(expired.registry:Export(4621, 1415)[1].number == 1)
assert(expired.map:GetLocalLayer().number == 1, "the own panel reads the current assignment after a competing claim expires")
print("PASS: measured Crasling/Moofin GUIDs share a world label; NPC changes stay silent; expired claims cannot leave a stale panel number")
