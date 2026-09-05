local iRL = _G.iRaceLocked
if not iRL then return end

local Enforcement = {}
iRL.Enforcement = Enforcement

local LANGUAGE_BY_RACE = {
    Human = 7, Orc = 1, Dwarf = 6, NightElf = 2, Scourge = 33, Tauren = 3, Gnome = 13, Troll = 14,
    BloodElf = 10, Draenei = 35,
}

local languageHooksInstalled = false
local applyingLanguage = false
local groupLeaving = false

local warningFrame = CreateFrame("Frame", "iRCSelfFoundWarning", UIParent)
warningFrame:SetSize(620, 32)
warningFrame:SetPoint("TOP", UIParent, "TOP", 0, -170)
warningFrame.text = warningFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
warningFrame.text:SetAllPoints(warningFrame)
warningFrame.text:SetJustifyH("CENTER")
warningFrame.text:SetTextColor(1, 0.10, 0.10)
warningFrame:Hide()

local function isRuleEnabled(key)
    return iRL:IsInGuildConnection() and iRL:GetConnectionRules()[key] == true
end

local function getNativeLanguage()
    local _, raceFile, raceId = UnitRace("player")
    local languageId = LANGUAGE_BY_RACE[raceFile]
    if not languageId or not GetNumLanguages or not GetLanguageByIndex then return nil, nil end
    for index = 1, GetNumLanguages() do
        local languageName, knownLanguageId = GetLanguageByIndex(index)
        if knownLanguageId == languageId then return languageName, languageId end
    end
    return nil, nil
end

function Enforcement:ApplyNativeLanguage()
    if applyingLanguage or not isRuleEnabled("nativeTongueOnly") or not NUM_CHAT_WINDOWS then return end
    local languageName, languageId = getNativeLanguage()
    if not languageName then return end
    applyingLanguage = true
    for index = 1, NUM_CHAT_WINDOWS do
        local editBox = _G["ChatFrame" .. index .. "EditBox"]
        if editBox then
            editBox.language = languageName
            editBox.languageID = languageId
        end
    end
    applyingLanguage = false
end

local function scheduleLanguageApply()
    if C_Timer and C_Timer.After then C_Timer.After(0, function() Enforcement:ApplyNativeLanguage() end) else Enforcement:ApplyNativeLanguage() end
end

local function installLanguageHooks()
    if languageHooksInstalled or type(hooksecurefunc) ~= "function" then return end
    for _, functionName in ipairs({ "ChatEdit_OnLanguageChanged", "ChatFrame_ChatEdit_OnLanguageChanged" }) do
        if type(_G[functionName]) == "function" then hooksecurefunc(functionName, scheduleLanguageApply) end
    end
    languageHooksInstalled = true
end

function Enforcement:UpdateSelfFoundWarning()
    local rules = iRL:GetConnectionRules()
    local exemptAtLevel60 = rules.allowLevel60WithoutSelfFound and (UnitLevel("player") or 0) >= 60
    local violation = isRuleEnabled("selfFoundOnly") and not exemptAtLevel60 and not iRL:GetSelfFoundState()
    warningFrame:SetShown(violation)
    if violation then
        warningFrame.text:SetText("SELF-FOUND REQUIRED: This character is not in Self-Found mode.")
    end
end

local function leaveCurrentGroup()
    if groupLeaving then return end
    groupLeaving = true
    local channel = IsInRaid and IsInRaid() and "RAID" or "PARTY"
    if SendChatMessage then SendChatMessage("I am race-locked and must leave this group because Same-race groups only is active.", channel) end
    if C_PartyInfo and C_PartyInfo.LeaveParty then
        C_PartyInfo.LeaveParty()
    elseif LeaveParty then
        LeaveParty()
    end
    if C_Timer and C_Timer.After then C_Timer.After(1, function() groupLeaving = false end) else groupLeaving = false end
end

function Enforcement:CheckGroup()
    if not isRuleEnabled("sameRaceGroupsOnly") or groupLeaving then return end
    local _, playerRace = UnitRace("player")
    if not playerRace then return end
    local inRaid = IsInRaid and IsInRaid()
    local memberCount = inRaid and (GetNumGroupMembers and GetNumGroupMembers() or 0) or (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0)
    for index = 1, memberCount do
        local unit = inRaid and "raid" .. index or "party" .. index
        if not UnitIsUnit or not UnitIsUnit(unit, "player") then
            local _, memberRace = UnitRace(unit)
            if memberRace and memberRace ~= playerRace then
                leaveCurrentGroup()
                return
            end
        end
    end
end

function Enforcement:Refresh()
    installLanguageHooks()
    scheduleLanguageApply()
    self:UpdateSelfFoundWarning()
    if C_Timer and C_Timer.After then C_Timer.After(0, function() Enforcement:CheckGroup() end) else self:CheckGroup() end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("LANGUAGE_LIST_CHANGED")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" and unit ~= "player" then return end
    if event == "GROUP_ROSTER_UPDATE" then
        if C_Timer and C_Timer.After then C_Timer.After(0, function() Enforcement:CheckGroup() end) else Enforcement:CheckGroup() end
    else
        Enforcement:Refresh()
    end
end)
