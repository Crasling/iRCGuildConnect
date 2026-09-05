local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local Enforcement = {}
iRC.Enforcement = Enforcement

local LANGUAGE_BY_RACE = {
    Human = 7, Orc = 1, Dwarf = 6, NightElf = 2, Scourge = 33, Tauren = 3, Gnome = 13, Troll = 14,
    BloodElf = 10, Draenei = 35,
}

local languageHooksInstalled = false
local applyingLanguage = false
local groupLeaving = false
local restrictedTradeCancelled = false
local lastMailRestrictionReason
local pendingGuildFoundTradePartners = {}

local warningFrame = CreateFrame("Frame", "iRCSelfFoundWarning", UIParent)
warningFrame:SetSize(620, 32)
warningFrame:SetPoint("TOP", UIParent, "TOP", 0, -170)
warningFrame.text = warningFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
warningFrame.text:SetAllPoints(warningFrame)
warningFrame.text:SetJustifyH("CENTER")
warningFrame.text:SetTextColor(1, 0.10, 0.10)
warningFrame:Hide()

local function isRuleEnabled(key)
    return iRC:IsInGuildConnection() and iRC:GetConnectionRules()[key] == true
end

local function isLevel60GuildFoundActive()
    return isRuleEnabled("selfFoundOnly") and isRuleEnabled("level60GuildFound")
        and (UnitLevel("player") or 0) >= 60 and not iRC:GetSelfFoundState()
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
    local rules = iRC:GetConnectionRules()
    local level60OrAbove = (UnitLevel("player") or 0) >= 60
    local exemptAtLevel60 = level60OrAbove and (rules.level60GuildFound or rules.allowLevel60WithoutSelfFound)
    local violation = isRuleEnabled("selfFoundOnly") and not exemptAtLevel60 and not iRC:GetSelfFoundState()
    warningFrame:SetShown(violation)
    if violation then
        warningFrame.text:SetText(iRC:Text("SELF_FOUND_REQUIRED_WARNING"))
    end
end

function Enforcement:ShowGuildFoundRestriction(message)
    iRC:Print(iRC.Colors.Red .. iRC:Text("GUILD_FOUND_RESTRICTION", message) .. iRC.Colors.Reset)
end

local function getTradePartnerName()
    local partnerName = GetUnitName and (GetUnitName("NPC", true) or GetUnitName("npc", true))
    if not partnerName and TradeFrameRecipientNameText and TradeFrameRecipientNameText.GetText then
        partnerName = TradeFrameRecipientNameText:GetText()
    end
    return partnerName
end

local function getMailRecipient()
    local field = _G.SendMailNameEditBox
        or (_G.MailFrame and _G.MailFrame.SendMailFrame and _G.MailFrame.SendMailFrame.RecipientEditBox)
    if not field or not field.GetText then return nil end
    local recipient = field:GetText()
    if type(recipient) ~= "string" then return nil end
    recipient = recipient:gsub("^%s+", ""):gsub("%s+$", "")
    return recipient ~= "" and recipient or nil
end

local function getSendMailButton()
    return _G.SendMailMailButton
        or (_G.MailFrame and _G.MailFrame.SendMailFrame and _G.MailFrame.SendMailFrame.SendMailButton)
end

function Enforcement:CheckTradeRestriction()
    if not isLevel60GuildFoundActive() or restrictedTradeCancelled then return end
    local partnerName = getTradePartnerName()
    if not partnerName then return end
    local allowed, reason = iRC:GetGuildFoundTradeStatus(partnerName)
    if allowed then return end

    -- Give a RaceLocked guildmate one short chance to answer its native TV
    -- handshake before cancelling. iRC never writes RaceLocked's roster.
    local partnerKey = iRC:NormalizeName(partnerName)
    if not iRC:FindConnectionProfile(partnerName) and iRC.RequestRaceLockedTradeVerification then
        local handshakeState = pendingGuildFoundTradePartners[partnerKey]
        if not handshakeState then
            pendingGuildFoundTradePartners[partnerKey] = "pending"
            iRC:RequestRaceLockedTradeVerification(partnerName)
            if C_Timer and C_Timer.After then
                C_Timer.After(1, function()
                    pendingGuildFoundTradePartners[partnerKey] = "attempted"
                    Enforcement:CheckTradeRestriction()
                end)
            else
                pendingGuildFoundTradePartners[partnerKey] = "attempted"
            end
            return
        elseif handshakeState == "pending" then
            return
        end
    end
    restrictedTradeCancelled = true
    self:ShowGuildFoundRestriction(iRC:Text("GUILD_FOUND_TRADE_CANCELLED", partnerName, reason or iRC:Text("GUILD_FOUND_TRADE_REASON")))
    if CancelTrade then CancelTrade() end
end

function Enforcement:UpdateMailRestriction()
    local button = getSendMailButton()
    if not button or not button.SetEnabled then return end
    if not isLevel60GuildFoundActive() then
        if button.iRCMailRestricted then button:SetEnabled(true) end
        button.iRCMailRestricted = nil
        lastMailRestrictionReason = nil
        return
    end

    local recipient = getMailRecipient()
    if not recipient then
        if button.iRCMailRestricted then button:SetEnabled(true) end
        button.iRCMailRestricted = nil
        lastMailRestrictionReason = nil
        return
    end
    local allowed, reason = iRC:GetGuildFoundTradeStatus(recipient)
    if not allowed and not iRC:FindConnectionProfile(recipient) and iRC.RequestRaceLockedTradeVerification then
        iRC:RequestRaceLockedTradeVerification(recipient)
    end
    if allowed then
        if button.iRCMailRestricted then button:SetEnabled(true) end
        button.iRCMailRestricted = nil
    else
        button.iRCMailRestricted = true
        button:SetEnabled(false)
    end
    if not allowed and reason ~= lastMailRestrictionReason then
        lastMailRestrictionReason = reason
        self:ShowGuildFoundRestriction(iRC:Text("GUILD_FOUND_MAIL_BLOCKED", recipient, reason or iRC:Text("GUILD_FOUND_MAIL_REASON")))
    elseif allowed then
        lastMailRestrictionReason = nil
    end
end

function Enforcement:InstallMailRecipientGuard()
    local field = _G.SendMailNameEditBox
        or (_G.MailFrame and _G.MailFrame.SendMailFrame and _G.MailFrame.SendMailFrame.RecipientEditBox)
    if not field or field.iRCMailGuardHooked or not field.HookScript then return end
    field.iRCMailGuardHooked = true
    field:HookScript("OnTextChanged", function()
        Enforcement:UpdateMailRestriction()
    end)
end

function Enforcement:CloseRestrictedAuctionHouse()
    if not isLevel60GuildFoundActive() then return end
    self:ShowGuildFoundRestriction(iRC:Text("GUILD_FOUND_AUCTION_HOUSE_CLOSED"))
    local closeAuctionHouse = function()
        if not isLevel60GuildFoundActive() then return end
        if CloseAuctionHouse then
            CloseAuctionHouse()
        elseif AuctionHouseFrame and AuctionHouseFrame:IsShown() then
            AuctionHouseFrame:Hide()
        elseif AuctionFrame and AuctionFrame:IsShown() then
            AuctionFrame:Hide()
        end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.1, closeAuctionHouse) else closeAuctionHouse() end
end

local function leaveCurrentGroup(reason)
    if groupLeaving then return end
    groupLeaving = true
    local channel = IsInRaid and IsInRaid() and "RAID" or "PARTY"
    if SendChatMessage then SendChatMessage(reason, channel) end
    if C_PartyInfo and C_PartyInfo.LeaveParty then
        C_PartyInfo.LeaveParty()
    elseif LeaveParty then
        LeaveParty()
    end
    if C_Timer and C_Timer.After then C_Timer.After(1, function() groupLeaving = false end) else groupLeaving = false end
end

function Enforcement:CheckGroup()
    if groupLeaving then return end
    local _, playerRace = UnitRace("player")
    if not playerRace then return end
    local inRaid = IsInRaid and IsInRaid()
    local memberCount = inRaid and (GetNumGroupMembers and GetNumGroupMembers() or 0) or (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0)
    local rules = iRC:GetConnectionRules()
    local level60SameRaceException = rules.allowLevel60MixedRaceGroups and (UnitLevel("player") or 0) >= 60
    if isRuleEnabled("sameRaceGroupsOnly") and not level60SameRaceException then
        for index = 1, memberCount do
            local unit = inRaid and "raid" .. index or "party" .. index
            if not UnitIsUnit or not UnitIsUnit(unit, "player") then
                local _, memberRace = UnitRace(unit)
                if memberRace and memberRace ~= playerRace then
                    leaveCurrentGroup(iRC:Text("SAME_RACE_GROUP_LEAVE"))
                    return
                end
            end
        end
    end
    if isLevel60GuildFoundActive() and memberCount > 0 and not iRC:IsGuildOnlyGroup() then
        leaveCurrentGroup(iRC:Text("GUILD_FOUND_GROUP_LEAVE"))
    end
end

function Enforcement:Refresh()
    installLanguageHooks()
    iRC:RecordSelfFoundState()
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
frame:RegisterEvent("TRADE_SHOW")
frame:RegisterEvent("TRADE_UPDATE")
frame:RegisterEvent("TRADE_CLOSED")
frame:RegisterEvent("AUCTION_HOUSE_SHOW")
frame:RegisterEvent("MAIL_SHOW")
frame:RegisterEvent("MAIL_CLOSED")
frame:RegisterEvent("MAIL_SEND_SUCCESS")
frame:SetScript("OnEvent", function(_, event, unit)
    if event == "TRADE_CLOSED" then
        restrictedTradeCancelled = false
        pendingGuildFoundTradePartners = {}
    elseif event == "TRADE_SHOW" or event == "TRADE_UPDATE" then
        Enforcement:CheckTradeRestriction()
    elseif event == "AUCTION_HOUSE_SHOW" then
        Enforcement:CloseRestrictedAuctionHouse()
    elseif event == "MAIL_SHOW" then
        Enforcement:InstallMailRecipientGuard()
        Enforcement:UpdateMailRestriction()
    elseif event == "MAIL_SEND_SUCCESS" then
        Enforcement:UpdateMailRestriction()
    elseif event == "MAIL_CLOSED" then
        lastMailRestrictionReason = nil
    elseif event == "UNIT_AURA" and unit ~= "player" then
        return
    elseif event == "GROUP_ROSTER_UPDATE" then
        if C_Timer and C_Timer.After then C_Timer.After(0, function() Enforcement:CheckGroup() end) else Enforcement:CheckGroup() end
    else
        Enforcement:Refresh()
    end
end)

local mailUpdateElapsed = 0
frame:SetScript("OnUpdate", function(_, elapsed)
    mailUpdateElapsed = mailUpdateElapsed + elapsed
    if mailUpdateElapsed < 0.20 then return end
    mailUpdateElapsed = 0
    if (MailFrame and MailFrame:IsShown()) or (MailFrameTab2 and MailFrameTab2:IsShown()) then
        Enforcement:UpdateMailRestriction()
    end
end)
