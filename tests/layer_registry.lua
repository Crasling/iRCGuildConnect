local function key(instance, server, map) return tostring(server) .. "-" .. tostring(instance) .. "-" .. tostring(map) end
-- Independent clients must derive the same display numbers after merging claims.
local clock, secret = 1800000000, {}
local function client(clockMode, getScope)
    local env, addon = {}, {}
    setmetatable(env, { __index = _G })
    env.GetServerTime = function() return clock end
    env.time = function() return clock + 999 end
    if clockMode then env.GetServerTime = false end
    if clockMode == "monotonic" then env.time = false end
    env.GetTime = function() return 100 end
    function addon:IsSecretValue(value) return value == secret end
    if getScope then addon.GetGuildDirectoryScope = getScope end
    assert(loadfile("iRC_LayerRegistry.lua", "t", env))("iRC", { iRC = addon })
    return addon.LayerRegistry
end

local server, map = 4621, 1415
local fallback = client("time")
assert(fallback:Claim(key(1, server, map), server, map, 1, "fallback", clock + 999, clock + 999), "local epoch clock is used when server time is unavailable")
fallback = client("monotonic")
assert(fallback:Claim(key(1, server, map), server, map, 1, "fallback", 100, 100), "test clients can fall back to their monotonic clock")
local function row(id, preferred, owner, created, observed)
    return { identityKey = type(id) == "number" and key(id, server, map) or id, preferredNumber = preferred, owner = owner,
        createdAt = created or clock, observedAt = observed or clock }
end
local function same(a, b)
    local first, second = a:Export(server, map), b:Export(server, map)
    assert(#first == #second, "merged books have the same membership")
    local used = {}
    for index, entry in ipairs(first) do
        local other = second[index]
        assert(entry.identityKey == other.identityKey and entry.preferredNumber == other.preferredNumber
            and entry.owner == other.owner and entry.createdAt == other.createdAt
            and entry.observedAt == other.observedAt and entry.number == other.number,
            "merged claim metadata and effective numbers are identical")
        assert(entry.number >= 1 and entry.number <= 99 and not used[entry.number], "raw identities never share a display number")
        used[entry.number] = true
    end
end

local a, b = client(), client()
assert(a:Claim(key(111, server, map), server, map, 1, "Player-A", clock - 10, clock))
assert(b:Claim(key(222, server, map), server, map, 1, "Player-B", clock - 20, clock))
assert(b:Claim(key(111, server, map), server, map, 2, "Player-B", clock - 5, clock))
local first, second = a:Export(server, map), b:Export(server, map)
assert(a:Merge(server, map, second) and b:Merge(server, map, first))
same(a, b)
assert(a:GetNumber(key(222, server, map), server, map) == 1 and a:GetNumber(key(111, server, map), server, map) == 2,
    "earlier distinct claims reserve their preferred number before a collision is reassigned")
assert(not a:Merge(server, map, b:Export(server, map)), "replaying identical registry rows is idempotent")

local batches = { {}, {}, {} }
for id = 1, 18 do
    local batch = (id - 1) % 3 + 1
    batches[batch][#batches[batch] + 1] = row(1000 + id, (id - 1) % 4 + 1,
        "origin " .. id % 3, clock - id, clock - id)
end
batches[1][#batches[1] + 1] = row(1006, 8, "alternate", clock - 30, clock - 1)
batches[2][#batches[2] + 1] = row(1009, 2, "alternate", clock - 29, clock - 2)
local ordered, shuffled, grouped = client(), client(), client()
for _, batch in ipairs(batches) do ordered:Merge(server, map, batch) end
for index = #batches, 1, -1 do shuffled:Merge(server, map, batches[index]) end
grouped:Merge(server, map, batches[1])
grouped:Merge(server, map, batches[2])
local intermediary = client()
intermediary:Merge(server, map, batches[3])
intermediary:Merge(server, map, grouped:Export(server, map))
same(ordered, shuffled)
same(ordered, intermediary)
assert(ordered:Export(server, map)[6].createdAt == clock - 30,
    "claim origin and newest observation merge independently across multiple hops")

local changes = a:GetRevision(server, map)
clock = clock + 20
local known = a:Claim(key(111, server, map), server, map, 99, "Someone-Else", clock, clock)
assert(known.owner == "player-a" and known.preferredNumber == 1 and known.createdAt == clock - 30,
    "a direct observation renews an existing claim without replacing its origin")
assert(a:GetRevision(server, map) > changes and known.observedAt == clock, "direct observations advance registry freshness")
b:Merge(server, map, a:Export(server, map))
same(a, b)

local input = { row(333, 1, "C", clock - 5), row(444, 1, "D", clock - 4), row(555, 1, "E", clock - 3) }
local forward, reverse = client(), client()
assert(forward:Merge(server, map, input))
assert(reverse:Merge(server, map, { input[3], input[2], input[1] }))
same(forward, reverse)
local exported = forward:Export(server, map)
exported[1].owner, exported[1].number, exported[1].observedAt = "mutated", 88, 0
assert(forward:Export(server, map)[1].owner == "c", "exports cannot mutate the stored registry")
input[1].owner = "changed input"
assert(forward:Export(server, map)[1].owner == "c", "merged input tables are not retained")

local conflictA, conflictB = client(), client()
local conflict1, conflict2 = row(777, 9, "Owner", clock - 1), row(777, 4, "OWNER", clock - 1)
conflictA:Merge(server, map, { conflict1, conflict2 })
conflictB:Merge(server, map, { conflict2, conflict1 })
same(conflictA, conflictB)
assert(conflictA:GetNumber(key(777, server, map), server, map) == 4, "exact-claim conflicts have a deterministic final tie-break")
assert(conflictA:Claim(key(777, server + 1, map), server + 1, map, 2, "other server", clock, clock))
assert(conflictA:Claim(key(777, server, map + 1), server, map + 1, 3, "other map", clock, clock))
assert(conflictA:GetNumber(key(777, server, map), server, map) == 4
    and conflictA:GetNumber(key(777, server + 1, map), server + 1, map) == 2
    and conflictA:GetNumber(key(777, server, map + 1), server, map + 1) == 3, "server and zone map scopes are independent")

local relay = client()
local observedAt = clock
assert(relay:Merge(server, map, { row(888, 1, "old owner", clock - 10, observedAt) }))
clock = clock + 3599
assert(not relay:Merge(server, map, { row(888, 1, "old owner", observedAt - 10, observedAt) }),
    "forwarding an unchanged observation does not refresh its lifetime")
assert(relay:GetNumber(key(888, server, map), server, map) == 1)
clock = clock + 2
assert(relay:GetNumber(key(888, server, map), server, map) == nil, "entries expire one hour after the original direct observation")
assert(not relay:Merge(server, map, { row(888, 1, "old owner", observedAt - 10, observedAt) }),
    "expired relays cannot resurrect old layers")

local bounded = client()
for id = 1, 105 do assert(bounded:Claim(key(id, server, map), server, map, 1, "owner " .. id, clock - 100, clock - 200 + id)) end
assert(#bounded:Export(server, map) == 99 and not bounded:GetNumber(key(1, server, map), server, map)
    and bounded:GetNumber(key(105, server, map), server, map), "capacity evicts the oldest observations and retains at most 99 layers")
local unique = {}
for _, entry in ipairs(bounded:Export(server, map)) do
    assert(not unique[entry.number] and entry.number <= 99, "capacity never creates duplicate or out-of-range aliases")
    unique[entry.number] = true
end
assert(bounded:Claim(key(106, server, map), server, map, nil, "newest", clock, clock), "a full registry still accepts a fresh claim with an automatic preference")
assert(#bounded:Export(server, map) == 99)

local invalid = client()
for _, candidate in ipairs({ row(1, 0, "x"), row(1, 100, "x"), row(1, 1, ""),
    row(1, 1, "x", math.huge), row(1, 1, "x", clock + 301), row(1, 1, "x", clock, clock + 301),
    row(1, 1, "x", 0 / 0), row(1.5, 1, "x"), row(1, 1, secret) }) do
    assert(not invalid:Merge(server, map, { candidate }), "invalid, secret, non-finite, and far-future metadata are rejected")
end
assert(invalid:GetRevision(server, map) == 0 and #invalid:Export(server, map) == 0)
assert(not invalid:Claim(key(1, secret, map), secret, map, 1, "x", clock, clock), "secret scope identifiers are never used")
local store, beforeReload = {}, client()
assert(beforeReload:AttachStore(store))
assert(beforeReload:Claim(key(456, server, map), server, map, 2, "remembered owner", clock - 10, clock))
local afterReload = client()
assert(afterReload:AttachStore(store) and afterReload:GetNumber(key(456, server, map), server, map) == 2,
    "original claims and their assigned numbers survive a reload")
assert(afterReload:Export(server, map)[1].createdAt == clock - 10, "restoring a book never renews claim age")
local oldStore = { layerNumberBooks = { ["7098:1420"] = { rows = { [2] = { zoneUID = 2, preferredNumber = 1,
    owner = "old", createdAt = clock - 10, observedAt = clock } } } } }
local migrated = client()
assert(migrated:AttachStore(oldStore) and oldStore.layerNumberBooks == nil and #migrated:Export(7098, 1420) == 0,
    "client-local ZoneUID books are discarded rather than mixed with shared world references")
assert(not migrated:Claim(2, 7098, 1420, 1, "old", clock, clock), "old numeric keys cannot create a new reference")
assert(migrated:MakeKey(7098, 0, 1420) == "7098-0-1420", "the instance field may be zero")
assert(not migrated:MakeKey(7098, secret, 1420) and not migrated:MakeKey(7098, -1, 1420))
assert(not migrated:ValidateRows({ { identityKey = "7098-0-1421", preferredNumber = 1,
    owner = "wrong zone", createdAt = clock, observedAt = clock } }, 1420), "cross-zone snapshots are rejected")
local worlds = client()
assert(worlds:Claim("7098-0-1420", 7098, 1420, nil, "one", clock - 3, clock).number == 1)
assert(worlds:Claim("7099-0-1420", 7099, 1420, nil, "two", clock - 2, clock).number == 2)
assert(worlds:Claim("7098-1-1420", 7098, 1420, nil, "three", clock - 1, clock).number == 3)
assert(worlds:Claim("7098-0-1421", 7098, 1421, nil, "other zone", clock, clock).number == 1,
    "different servers and instances are distinct within a zone; another zone has its own numbering")
print("PASS: independent shared layer books, deterministic claim merging, collision-free numbers, scopes, TTL, bounded rows, and relay safety")

local currentScope = "s-18-3-10-0-pve"
local savedRulesets = {}
local isolated = client(nil, function() return currentScope end)
assert(isolated:AttachStore(savedRulesets))
assert(isolated:Claim(key(456, server, map), server, map, 2, "pve owner", clock - 10, clock))
currentScope = "s-18-3-11-0-pvp"
assert(isolated:GetNumber(key(456, server, map), server, map) == nil, "PvP cannot inherit saved PvE numbering")
assert(isolated:Claim(key(456, server, map), server, map, 4, "pvp owner", clock - 10, clock))
currentScope = "s-18-3-10-0-pve"
assert(isolated:GetNumber(key(456, server, map), server, map) == 2, "returning to PvE restores only its own book")
currentScope = nil
assert(#isolated:Export(server, map) == 0, "an unreadable ruleset cannot export another server's claims")
currentScope = "s-18-3-11-0-pvp"
local restored = client(nil, function() return currentScope end)
assert(restored:AttachStore(savedRulesets) and restored:GetNumber(key(456, server, map), server, map) == 4,
    "ruleset-specific layer books survive a reload")
print("PASS: saved numbering stays separate across server rulesets and unreadable startup state")
