-- Run from the iRC directory with: lua tests/roleplay_links.lua
local private = { iRC = {} }
function CreateFrame()
    return { RegisterEvent = function() end, SetScript = function() end }
end
assert(loadfile("iRC_Roleplay.lua"))("iRC", private)

local roleplay = private.iRC.Roleplay
local item = "|cff1eff00|Hitem:12713::::::::60:::::|h[Formula: Smoking Heart of the Mountain]|h|r"
assert(roleplay:TransformTrollTalk(item) == item, "item hyperlink must stay byte-for-byte intact")
assert(roleplay:TransformTrollTalk("The " .. item .. " is for you") == "Da " .. item .. " be fer ya",
    "only speech surrounding an item link should change")
assert(roleplay:TransformTaurenTalk("Hello " .. item) == "Greetings " .. item,
    "other RP styles must also preserve item links")

assert(roleplay:TransformUndeadSpeak("Hello friend, we are ready") == "Well met ally, the Forsaken stand ready")
assert(roleplay:TransformUndeadSpeak("On my way! I need healing.") == "These old bones are on the move! These bones require mending.")
assert(roleplay:TransformUndeadSpeak("Don't attack. I need mana.") == "Stay your blade. My mana reserves run dry.",
    "dungeon requests preserve their intent and sentence capitalization")
assert(roleplay:TransformUndeadSpeak("WE SURVIVED!") == "THE GRAVE HAS BEEN DENIED AGAIN!")
assert(roleplay:TransformUndeadSpeak("Thank you, friend") == "You have my gratitude, ally",
    "the short thanks phrase does not rewrite the longer thank-you replacement")
assert(roleplay:TransformUndeadSpeak("the weekend is already busy") == "the weekend is already busy",
    "phrase matching never rewrites part of a longer word")
assert(roleplay:TransformUndeadSpeak("Hello " .. item .. ", on my way")
    == "Well met " .. item .. ", these old bones are on the move", "Undead Speak preserves full item markup")
assert(roleplay:TransformUndeadSpeak("/run print('hello friend')") == "/run print('hello friend')")
assert(roleplay:TransformUndeadSpeak("Maybe we need help with this strange quest.")
    == "Perhaps we require aid with this peculiar quest.")
assert(roleplay:TransformUndeadSpeak("Okay, I think we should wait.") == "Very well, I suspect we should linger.")
assert(roleplay:TransformUndeadSpeak("He needs help, but we need to leave.") == "He requires aid, but we have to leave.",
    "noun and infinitive uses of need keep grammatical wording")
assert(roleplay:TransformUndeadSpeak("I wanted to buy this, but she wants another.")
    == "I wished to purchase this, but she wishes for another.", "wanting an item and wanting to act remain distinct")
assert(roleplay:TransformUndeadSpeak("No thanks, I don't know.") == "I must decline, I cannot say.",
    "a polite refusal takes priority over the shorter thanks replacement")
local fullMessage = string.rep("On my way! ", 23)
assert(#fullMessage <= 255 and roleplay:TransformUndeadSpeak(fullMessage) == fullMessage,
    "extra RP wording cannot truncate an already-full chat message")
function UnitRace() return "Undead", "SCOURGE" end
iRCCharDB = { roleplay = { undeadSpeak = true } }
assert(roleplay:TransformChatText("Maybe we need help") == "Perhaps we require aid",
    "the shared outgoing transformation uses this character's enabled voice")
iRCCharDB.roleplay.undeadSpeak = false
assert(roleplay:TransformChatText("Maybe we need help") == "Maybe we need help",
    "disabled RP returns ordinary chat unchanged")
print("Roleplay checks passed: Undead flavor, dungeon intent, case, boundaries, hyperlinks, commands and chat length")
