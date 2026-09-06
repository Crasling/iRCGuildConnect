local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local Roleplay = {}
iRC.Roleplay = Roleplay

function Roleplay:GetPlayerSettings()
    iRCCharDB = iRCCharDB or {}
    iRCCharDB.roleplay = iRCCharDB.roleplay or {}
    if iRCCharDB.roleplay.trollTalk == nil then iRCCharDB.roleplay.trollTalk = false end
    if iRCCharDB.roleplay.taurenTalk == nil then iRCCharDB.roleplay.taurenTalk = false end
    return iRCCharDB.roleplay
end

function Roleplay:IsTroll()
    local _, raceFile = UnitRace("player")
    return string.upper(tostring(raceFile or "")) == "TROLL"
end

function Roleplay:IsTrollTalkEnabled()
    return self:IsTroll() and self:GetPlayerSettings().trollTalk and true or false
end

function Roleplay:IsTauren()
    local _, raceFile = UnitRace("player")
    return string.upper(tostring(raceFile or "")) == "TAUREN"
end

function Roleplay:IsTaurenTalkEnabled()
    return self:IsTauren() and self:GetPlayerSettings().taurenTalk and true or false
end

local phraseReplacements = {
    { "what are you doing", "what ya be doin'" },
    { "who are you", "who ya be" },
    { "get out", "get outta here" },
    { "come here", "come 'ere" },
    { "going to", "gonna" },
    { "want to", "wanna" },
    { "got to", "gotta" },
    { "have to", "hafta" },
    { "they are", "dey be" },
    { "we are", "we be" },
    { "you are", "ya be" },
    { "i am", "I be" },
}

local wordReplacements = {
    { "yourself", "yaself" },
    { "without", "wit'out" },
    { "brothers", "bruddas" },
    { "brother", "brudda" },
    { "everyone", "all o' ya" },
    { "something", "somethin'" },
    { "nothing", "nothin'" },
    { "fighting", "fightin'" },
    { "walking", "walkin'" },
    { "killing", "killin'" },
    { "talking", "talkin'" },
    { "trying", "tryin'" },
    { "because", "'cause" },
    { "before", "'fore" },
    { "doesn't", "don'" },
    { "didn't", "didn'" },
    { "aren't", "ain't" },
    { "isn't", "ain't" },
    { "cannot", "can't" },
    { "mother", "mudda" },
    { "father", "fadda" },
    { "friend", "fren'" },
    { "listen", "listen 'ere" },
    { "hurry", "get movin'" },
    { "hello", "hey" },
    { "their", "dere" },
    { "there", "dere" },
    { "these", "dese" },
    { "those", "dose" },
    { "thing", "ting" },
    { "think", "tink" },
    { "with", "wit" },
    { "them", "dem" },
    { "they", "dey" },
    { "then", "den" },
    { "than", "dan" },
    { "this", "dis" },
    { "that", "dat" },
    { "you're", "ya be" },
    { "don't", "don'" },
    { "want", "wanna" },
    { "look", "lookit" },
    { "leave", "be gone" },
    { "yes", "yah" },
    { "no", "nah" },
    { "you", "ya" },
    { "your", "ya" },
    { "the", "da" },
    { "are", "be" },
    { "is", "be" },
    { "and", "an'" },
    { "for", "fer" },
    { "of", "o'" },
    { "to", "ta" },
    { "man", "mon" },
    { "mate", "mon" },
    { "me", "me" },
    { "my", "me" },
}

-- Conservative substitutions keep ordinary Tauren chat readable.
local taurenPhraseReplacements = {
    { "thank you", "you have my gratitude" },
    { "good luck", "may the spirits guide you" },
    { "be careful", "walk with care" },
    { "follow me", "walk beside me" },
    { "stay here", "remain here" },
    { "help me", "lend me your strength" },
    { "i agree", "your words carry truth" },
    { "i disagree", "I do not share your path" },
    { "we must go", "our path leads onward" },
    { "prepare yourself", "steady your heart" },
    { "we are ready", "our hearts are prepared" },
    { "rest in peace", "rest with the spirits" },
}

local taurenWordReplacements = {
    { "ancestors", "honored ancestors" },
    { "everyone", "everyone gathered" },
    { "goodbye", "farewell" },
    { "hello", "greetings" },
    { "people", "tribe" },
    { "earth", "sacred earth" },
    { "nature", "Earth Mother" },
    { "world", "living world" },
    { "home", "homelands" },
    { "sun", "An'she" },
    { "moon", "Mu'sha" },
    { "gods", "spirits" },
    { "magic", "spirit power" },
    { "enemies", "foes" },
    { "enemy", "foe" },
    { "danger", "peril" },
    { "death", "final journey" },
    { "dead", "fallen" },
    { "kill", "strike down" },
    { "protect", "guard" },
    { "fight", "stand against" },
    { "win", "prevail" },
    { "lose", "fall" },
    { "strong", "steadfast" },
    { "brave", "courageous" },
    { "wise", "guided" },
    { "wait", "have patience" },
    { "hurry", "move swiftly" },
    { "listen", "hear me" },
    { "look", "behold" },
    { "understand", "see clearly" },
    { "remember", "honor" },
    { "perhaps", "maybe" },
}

local function caseInsensitivePattern(phrase)
    local pattern = {}
    for index = 1, #phrase do
        local character = phrase:sub(index, index)
        if character:match("%a") then
            pattern[#pattern + 1] = "[" .. string.lower(character) .. string.upper(character) .. "]"
        elseif character:match("[%^%$%(%)%%%.%[%]%*%+%-%?]") then
            pattern[#pattern + 1] = "%" .. character
        else
            pattern[#pattern + 1] = character
        end
    end
    return "%f[%a]" .. table.concat(pattern) .. "%f[%A]"
end

local function matchCapitalization(original, replacement)
    if original == string.upper(original) then return string.upper(replacement) end
    if original:sub(1, 1) == string.upper(original:sub(1, 1)) then
        return string.upper(replacement:sub(1, 1)) .. replacement:sub(2)
    end
    return replacement
end

local function applyReplacements(text, replacements)
    for _, entry in ipairs(replacements) do
        text = text:gsub(caseInsensitivePattern(entry[1]), function(original)
            return matchCapitalization(original, entry[2])
        end)
    end
    return text
end

function Roleplay:TransformTrollTalk(text)
    if type(text) ~= "string" or text == "" or text:match("^%s*/") then return text end
    text = text:gsub("’", "'")
    text = applyReplacements(text, phraseReplacements)
    text = applyReplacements(text, wordReplacements)
    return text
end

function Roleplay:TransformTaurenTalk(text)
    if type(text) ~= "string" or text == "" or text:match("^%s*/") then return text end
    text = text:gsub("â€™", "'")
    text = applyReplacements(text, taurenPhraseReplacements)
    text = applyReplacements(text, taurenWordReplacements)
    return text
end

local roleplayWrappers = setmetatable({}, { __mode = "k" })
local transformedEditBoxes = setmetatable({}, { __mode = "k" })

local function transformBeforeSend(editBox)
    if not editBox or not editBox.GetText or not editBox.SetText then return end
    if transformedEditBoxes[editBox] then return end
    if Roleplay:IsTrollTalkEnabled() then
        editBox:SetText(Roleplay:TransformTrollTalk(editBox:GetText()))
        transformedEditBoxes[editBox] = true
    elseif Roleplay:IsTaurenTalkEnabled() then
        editBox:SetText(Roleplay:TransformTaurenTalk(editBox:GetText()))
        transformedEditBoxes[editBox] = true
    end
end

local function installChatSendHook()
    local currentSend = ChatEdit_SendText
    if type(currentSend) ~= "function" or roleplayWrappers[currentSend] then return end
    local originalSend = currentSend
    local wrapper = function(editBox, addHistory)
        transformBeforeSend(editBox)
        local result = originalSend(editBox, addHistory)
        transformedEditBoxes[editBox] = nil
        return result
    end
    roleplayWrappers[wrapper] = true
    ChatEdit_SendText = wrapper
end

local function installChatEditBoxHooks()
    if not NUM_CHAT_WINDOWS then return end
    for index = 1, NUM_CHAT_WINDOWS do
        local editBox = _G["ChatFrame" .. index .. "EditBox"]
        local currentHandler = editBox and editBox.GetScript and editBox:GetScript("OnEnterPressed")
        if type(currentHandler) == "function" and not roleplayWrappers[currentHandler] then
            local originalHandler = currentHandler
            local wrapper = function(self, ...)
                transformBeforeSend(self)
                local results = { originalHandler(self, ...) }
                transformedEditBoxes[self] = nil
                return unpack(results)
            end
            roleplayWrappers[wrapper] = true
            editBox:SetScript("OnEnterPressed", wrapper)
        end
    end
end

local function installChatHooks()
    installChatSendHook()
    installChatEditBoxHooks()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    installChatHooks()
    if C_Timer and C_Timer.After then
        C_Timer.After(1, installChatHooks)
        C_Timer.After(5, installChatHooks)
    end
end)
