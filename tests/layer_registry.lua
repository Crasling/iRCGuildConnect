-- Independent clients must derive the same display numbers after merging claims.
local clock, secret = 1800000000, {}
local function client(clockMode)
    local env, addon = {}, {}
    setmetatable(env, { __index = _G })
    env.GetServerTime = function() return clock end
    env.time = function() return clock + 999 end
    if clockMode then env.GetServerTime = false end
    if clockMode == "monotonic" then env.time = false end
    env.GetTime = function() return 100 end
    function addon:IsSecretValue(value) return value == secret end
    assert(loadfile("iRC_LayerRegistry.lua", "t", env))("iRC", { iRC = addon })
    return addon.LayerRegistry
end

local server, map = 4621, 1415
local fallback = client("time")
assert(fallback:Claim(1, server, map, 1, "fallback", clock + 999, clock + 999), "local epoch clock is used when server time is unavailable")
fallback = client("monotonic")
assert(fallback:Claim(1, server, map, 1, "fallback", 100, 100), "test clients can fall back to their monotonic clock")
local function row(id, preferred, owner, created, observed)
    return { zoneUID = id, preferredNumber = preferred, owner = owner,
        createdAt = created or clock, observedAt = observed or clock }
end
local function same(a, b)
    local first, second = a:Export(server, map), b:Export(server, map)
    assert(#first == #second, "merged books have the same membership")
    local used = {}
    for index, entry in ipairs(first) do
        local other = second[index]
        assert(entry.zoneUID == other.zoneUID and entry.preferredNumber == other.preferredNumber
            and entry.owner == other.owner and entry.createdAt == other.createdAt
            and entry.observedAt == other.observedAt and entry.number == other.number,
            "merged claim metadata and effective numbers are identical")
        assert(entry.number >= 1 and entry.number <= 99 and not used[entry.number], "raw identities never share a display number")
        used[entry.number] = true
    end
end

local a, b = client(), client()
assert(a:Claim(111, server, map, 1, "Player-A", clock - 10, clock))
assert(b:Claim(222, server, map, 1, "Player-B", clock - 20, clock))
assert(b:Claim(111, server, map, 2, "Player-B", clock - 5, clock))
local first, second = a:Export(server, map), b:Export(server, map)
assert(a:Merge(server, map, second) and b:Merge(server, map, first))
same(a, b)
assert(a:GetNumber(222, server, map) == 1 and a:GetNumber(111, server, map) == 2,
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
local known = a:Claim(111, server, map, 99, "Someone-Else", clock, clock)
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
assert(conflictA:GetNumber(777, server, map) == 4, "exact-claim conflicts have a deterministic final tie-break")
assert(conflictA:Claim(777, server + 1, map, 2, "other server", clock, clock))
assert(conflictA:Claim(777, server, map + 1, 3, "other map", clock, clock))
assert(conflictA:GetNumber(777, server, map) == 4
    and conflictA:GetNumber(777, server + 1, map) == 2
    and conflictA:GetNumber(777, server, map + 1) == 3, "server and zone map scopes are independent")

local relay = client()
local observedAt = clock
assert(relay:Merge(server, map, { row(888, 1, "old owner", clock - 10, observedAt) }))
clock = clock + 3599
assert(not relay:Merge(server, map, { row(888, 1, "old owner", observedAt - 10, observedAt) }),
    "forwarding an unchanged observation does not refresh its lifetime")
assert(relay:GetNumber(888, server, map) == 1)
clock = clock + 2
assert(relay:GetNumber(888, server, map) == nil, "entries expire one hour after the original direct observation")
assert(not relay:Merge(server, map, { row(888, 1, "old owner", observedAt - 10, observedAt) }),
    "expired relays cannot resurrect old layers")

local bounded = client()
for id = 1, 105 do assert(bounded:Claim(id, server, map, 1, "owner " .. id, clock - 100, clock - 200 + id)) end
assert(#bounded:Export(server, map) == 99 and not bounded:GetNumber(1, server, map)
    and bounded:GetNumber(105, server, map), "capacity evicts the oldest observations and retains at most 99 layers")
local unique = {}
for _, entry in ipairs(bounded:Export(server, map)) do
    assert(not unique[entry.number] and entry.number <= 99, "capacity never creates duplicate or out-of-range aliases")
    unique[entry.number] = true
end
assert(bounded:Claim(106, server, map, nil, "newest", clock, clock), "a full registry still accepts a fresh claim with an automatic preference")
assert(#bounded:Export(server, map) == 99)

local invalid = client()
for _, candidate in ipairs({ row(1, 0, "x"), row(1, 100, "x"), row(1, 1, ""),
    row(1, 1, "x", math.huge), row(1, 1, "x", clock + 301), row(1, 1, "x", clock, clock + 301),
    row(1, 1, "x", 0 / 0), row(1.5, 1, "x"), row(1, 1, secret) }) do
    assert(not invalid:Merge(server, map, { candidate }), "invalid, secret, non-finite, and far-future metadata are rejected")
end
assert(invalid:GetRevision(server, map) == 0 and #invalid:Export(server, map) == 0)
assert(not invalid:Claim(1, secret, map, 1, "x", clock, clock), "secret scope identifiers are never used")
local store, beforeReload = {}, client()
assert(beforeReload:AttachStore(store))
assert(beforeReload:Claim(456, server, map, 2, "remembered owner", clock - 10, clock))
local afterReload = client()
assert(afterReload:AttachStore(store) and afterReload:GetNumber(456, server, map) == 2,
    "original claims and their assigned numbers survive a reload")
assert(afterReload:Export(server, map)[1].createdAt == clock - 10, "restoring a book never renews claim age")
print("PASS: independent shared layer books, deterministic claim merging, collision-free numbers, scopes, TTL, bounded rows, and relay safety")
