-- Run from the addon directory. No game, network or saved-variable writes.
local private = { iRC = {} }
assert(loadfile("iRC_Profanity.lua"))("iRC", private)

local iRC = private.iRC
assert(not iRC:ContainsProfanity("A friendly social guild for new players."))
assert(iRC:ContainsProfanity("This contains ABUSE."), "English matching is case-insensitive")
assert(not iRC:ContainsProfanity("Classic raiding"), "short blocked words require word boundaries")
assert(iRC:ContainsProfanity("HÅRD"), "non-ASCII case folding is applied")
assert(iRC:ContainsProfanity("これはグループ・セックスです"), "CJK terms are detected inside unspaced text")

print("Profanity filter tests passed: clean text, boundaries, ASCII case, Unicode case and CJK fragments.")
