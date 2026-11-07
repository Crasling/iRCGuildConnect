local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

-- Active gameplay safeguards for guild rules
--
-- This module reacts to trade, mail, auction-house, language, and group state.
-- It blocks unsafe actions locally and reports confirmed group violations, but
-- never performs guild kicks or rank changes.

local Enforcement = {}
iRC.Enforcement = Enforcement

local LANGUAGE_BY_RACE = {
    Human = 7, Orc = 1, Dwarf = 6, NightElf = 2, Scourge = 33, Tauren = 3, Gnome = 13, Troll = 14,
    BloodElf = 10, Draenei = 35,
}

local languageHooksInstalled = false
local applyingLanguage = false
local groupLeaving = false
local groupSafety = { sameRace = false, guildOnly = false }
local pendingUnsafeGroupReason
local pendingGroupViolation
local pendingGroupViolationKey
local pendingGroupLeaveConfirmation
local observedGroupRestrictions
local initialGroupProtectionPending = true
local restrictedTradeCancelled = false
local approvedTradeExceptionRecorded = false
local protectedTradeEvidence
local restrictedMailEvidence
local approvedMailExceptionRecipient
local finalizedMailRecipient
local mailSendPending = false
local mailHooksInstalled = {}
local refreshingMailGuard = false
local inboxHooksInstalled = {}
local refreshingInboxGuard = false
local restrictedInboxBypassKey
local protectedInboxEvidence
local lastTradeRestrictionReason
local tradeHooksInstalled = {}
local refreshingTradeGuard = false
local lastInboxRestrictionKey
local CONJURED_ITEMS = { [5350]=true,[2288]=true,[2136]=true,[3772]=true,[8077]=true,[8078]=true,[8079]=true,[5349]=true,[1113]=true,[1114]=true,[1487]=true,[8075]=true,[8076]=true,[22895]=true }
local HEALTHSTONE_ITEMS = { [5512]=true,[19004]=true,[19005]=true,[5511]=true,[19006]=true,[19007]=true,[5509]=true,[19008]=true,[19009]=true,[5510]=true,[19010]=true,[19011]=true,[9421]=true,[19012]=true,[19013]=true }
local QUEST_ITEMS = { [7740]=true,[7741]=true }
local LOCKBOX_ITEMS = { [16882]=true,[16883]=true,[16884]=true,[16885]=true,[4632]=true,[4633]=true,[4634]=true,[4636]=true,[4637]=true,[4638]=true,[5758]=true,[5759]=true,[5760]=true,[6354]=true,[6355]=true,[6712]=true,[12033]=true,[13875]=true,[13918]=true }

local warningFrame = CreateFrame("Frame", "iRCSelfFoundWarning", UIParent)
warningFrame:SetSize(620, 32)
warningFrame:SetPoint("TOP", UIParent, "TOP", 0, -170)
warningFrame.text = warningFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
warningFrame.text:SetAllPoints(warningFrame)
warningFrame.text:SetJustifyH("CENTER")
warningFrame.text:SetTextColor(1, 0.10, 0.10)
warningFrame:Hide()

local groupWarningFrame = CreateFrame("Frame", "iRCUnsafeGroupWarning", UIParent)
groupWarningFrame:SetSize(760, 42)
groupWarningFrame:SetPoint("TOP", warningFrame, "BOTTOM", 0, -8)
groupWarningFrame.text = groupWarningFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
groupWarningFrame.text:SetAllPoints(groupWarningFrame)
groupWarningFrame.text:SetJustifyH("CENTER")
groupWarningFrame.text:SetTextColor(1, 0.10, 0.10)
groupWarningFrame:Hide()

-- Native-language enforcement ----------------------------------------------

local function isRuleEnabled(key)
    local rules = iRC:GetConnectionRules()
    if (key == "nativeTongueOnly" or key == "sameRaceGroupsOnly" or key == "allowLevel60MixedRaceGroups")
        and rules.raceLock ~= true then return false end
    return iRC:IsGuildConnectionActive() and rules[key] == true
end

local function isGuildFoundEconomyActive()
    return iRC:IsGuildFoundEconomyActive()
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

-- Self-Found and economy restrictions --------------------------------------

function Enforcement:UpdateSelfFoundWarning()
    local rules = iRC:GetConnectionRules()
    local level60OrAbove = (UnitLevel("player") or 0) >= 60
    local exemptAtLevel60 = level60OrAbove and (rules.level60GuildFound or rules.allowLevel60WithoutSelfFound)
    local personalBank = iRC.Identity and iRC.Identity:IsPersonalBank(iRC:GetPlayerName())
    local violation = iRC:IsGuildConnectionActive() and iRC:GetProgressionMode(rules) == "SELF_FOUND"
        and not exemptAtLevel60 and not personalBank and not iRC:GetSelfFoundState()
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

local function isTradeWindowOpen()
    return TradeFrame and TradeFrame.IsShown and TradeFrame:IsShown() or false
end

local function itemIdFromLink(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

local function externalTradeExceptionAllowed(partnerName)
    local rules = iRC:GetConnectionRules()
    if not rules.guildFoundTradeExceptions then return false, nil end
    local settings = iRC:GetGuildFoundTradeExceptionSettings()
    local selectedItems = settings.items or {}
    if (GetPlayerTradeMoney and GetPlayerTradeMoney() or 0) > 0
        or (GetTargetTradeMoney and GetTargetTradeMoney() or 0) > 0 then return false, nil end
    local playerItems, targetItems, itemCount = {}, {}, 0
    local serviceSlot = TRADE_ENCHANT_SLOT or MAX_TRADE_ITEMS or 7
    local transferableSlots = math.max(1, serviceSlot - 1)
    for slot = 1, transferableSlots do
        local playerId = itemIdFromLink(GetTradePlayerItemLink and GetTradePlayerItemLink(slot))
        local targetId = itemIdFromLink(GetTradeTargetItemLink and GetTradeTargetItemLink(slot))
        if playerId then playerItems[#playerItems + 1], itemCount = playerId, itemCount + 1 end
        if targetId then targetItems[#targetItems + 1], itemCount = targetId, itemCount + 1 end
    end
    local playerServiceId = itemIdFromLink(GetTradePlayerItemLink and GetTradePlayerItemLink(serviceSlot))
    local targetServiceId = itemIdFromLink(GetTradeTargetItemLink and GetTradeTargetItemLink(serviceSlot))
    if playerServiceId then itemCount = itemCount + 1 end
    if targetServiceId then itemCount = itemCount + 1 end
    if itemCount == 0 then return false, nil, true end
    local _, playerClass = UnitClass("player")
    local usedCategories, usedCategoryLookup = {}, {}
    local function useCategory(label)
        if not usedCategoryLookup[label] then
            usedCategoryLookup[label] = true
            usedCategories[#usedCategories + 1] = label
        end
    end
    local function allowedTransferItem(itemId)
        if settings.conjured and CONJURED_ITEMS[itemId] and selectedItems.conjured and selectedItems.conjured[itemId] then
            useCategory("Conjured Food / Water"); return true
        end
        if settings.healthstones and HEALTHSTONE_ITEMS[itemId] and selectedItems.healthstones and selectedItems.healthstones[itemId] then
            useCategory("Healthstones"); return true
        end
        if settings.questItems and QUEST_ITEMS[itemId] and selectedItems.questItems and selectedItems.questItems[itemId] then
            useCategory("Quest Items"); return true
        end
        return false
    end
    for _, itemId in ipairs(playerItems) do if not allowedTransferItem(itemId) then return false, nil end end
    for _, itemId in ipairs(targetItems) do if not allowedTransferItem(itemId) then return false, nil end end
    local incomingLockboxes = selectedItems.lockpickIncoming or {}
    local outgoingLockboxes = selectedItems.lockpickOutgoing or {}
    if playerServiceId and not (settings.lockpickIncoming and LOCKBOX_ITEMS[playerServiceId]
        and incomingLockboxes[playerServiceId]) then return false, nil end
    if playerServiceId then useCategory("Lockpicking (Incoming)") end
    if targetServiceId and not (settings.lockpickOutgoing and playerClass == "ROGUE"
        and LOCKBOX_ITEMS[targetServiceId] and outgoingLockboxes[targetServiceId]) then return false, nil end
    if targetServiceId then useCategory("Lockpicking (Outgoing)") end
    return true, table.concat(usedCategories, ", ")
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
    -- Refresh also runs during login/reload. Forever may retain a recipient
    -- name in the trade widgets while the trade window is hidden, which must
    -- never be treated as an active trade.
    if not isTradeWindowOpen() or not isGuildFoundEconomyActive() or restrictedTradeCancelled then return end
    local partnerName = getTradePartnerName()
    if not partnerName then return end
    local allowed, reason = iRC:GetGuildFoundTradeStatus(partnerName)
    if allowed then return end
    if iRC:GetConnectionRules().guildFoundTradeExceptions and not iRC:IsGuildMemberName(partnerName) then
        -- Keep the trade window open so approved exception items can be
        -- inspected. The protected accept path performs the final check.
        return
    end

    restrictedTradeCancelled = true
    iRC:RecordGuildFoundAudit("TRADE_BLOCKED", partnerName)
    self:ShowGuildFoundRestriction(iRC:Text("GUILD_FOUND_TRADE_CANCELLED", partnerName, reason or iRC:Text("GUILD_FOUND_TRADE_REASON")))
    if CancelTrade then CancelTrade() end
end

local function getTradeAcceptButton()
    return _G.TradeFrameTradeButton or (_G.TradeFrame and (_G.TradeFrame.TradeButton or _G.TradeFrame.AcceptButton))
end

local function releaseTradeButton(button)
    if not button.iRCRestricted then return end
    button.iRCRestricted = nil
    if isTradeWindowOpen() and TradeFrame.acceptState == 1 then return end
    -- Let Blizzard retain control of its confirmation-dialog state.
    if TradeFrameTradeButton_Enable then TradeFrameTradeButton_Enable() else button:SetEnabled(true) end
end

local function flagProtectedInteraction(reason, evidence)
    if not iRC.RaceLockedSync or not iRC.RaceLockedSync.FlagMonitoringDiscrepancy then return false end
    local currentMoney = GetMoney and GetMoney() or nil
    local flagged = iRC.RaceLockedSync:FlagMonitoringDiscrepancy(reason,
        evidence and evidence.money, currentMoney, evidence and evidence.startedAt)
    if flagged then iRC:DebugMsg(iRC:Text("GUILD_FOUND_MONITORING_DISCREPANCY", reason), 2) end
    return flagged
end

local function captureProtectedTradeEvidence()
    if not isTradeWindowOpen() or not isGuildFoundEconomyActive() then
        protectedTradeEvidence = nil
        return
    end
    local partnerName = getTradePartnerName()
    local button = getTradeAcceptButton()
    if not partnerName or not button then return end
    local restricted = button.iRCRestricted == true
    local exception = button.iRCApprovedException
    if not restricted and not exception then
        protectedTradeEvidence = nil
        return
    end
    if not protectedTradeEvidence or protectedTradeEvidence.partner ~= partnerName then
        protectedTradeEvidence = {
            partner = partnerName,
            money = GetMoney and GetMoney() or nil,
            startedAt = time(),
        }
    end
    protectedTradeEvidence.restricted = restricted
    protectedTradeEvidence.exception = exception
end

function Enforcement:UpdateTradeRestriction()
    local button = getTradeAcceptButton()
    if not button or not button.SetEnabled then return end
    if not isTradeWindowOpen() then
        releaseTradeButton(button)
        button.iRCRestricted, button.iRCApprovedException = nil, nil
        lastTradeRestrictionReason = nil
        protectedTradeEvidence = nil
        return
    end
    if not isGuildFoundEconomyActive() then
        releaseTradeButton(button)
        button.iRCRestricted, button.iRCApprovedException, lastTradeRestrictionReason = nil, nil, nil
        protectedTradeEvidence = nil
        return
    end

    local partnerName = getTradePartnerName()
    local allowed, reason
    if partnerName then allowed, reason = iRC:GetGuildFoundTradeStatus(partnerName) end
    local exceptionNote, waitingForItems
    if not allowed and partnerName and not iRC:IsGuildMemberName(partnerName) then
        allowed, exceptionNote, waitingForItems = externalTradeExceptionAllowed(partnerName)
        if iRC:GetConnectionRules().guildFoundTradeExceptions then
            reason = iRC:Text("GUILD_FOUND_TRADE_EXCEPTION_REASON")
        end
    end
    if allowed then
        releaseTradeButton(button)
        button.iRCRestricted, lastTradeRestrictionReason = nil, nil
        button.iRCApprovedException = exceptionNote
    else
        button.iRCRestricted = true
        button.iRCApprovedException = nil
        -- Blizzard also remembers this state while a trade confirmation is open.
        button.enabled = false
        button:SetEnabled(false)
        local restrictionKey = tostring(partnerName or "") .. ":" .. tostring(reason or "") .. ":" .. tostring(waitingForItems == true)
        if restrictionKey ~= lastTradeRestrictionReason then
            lastTradeRestrictionReason = restrictionKey
            if waitingForItems then
                iRC:Print(iRC.Colors.Yellow .. iRC:Text("GUILD_FOUND_TRADE_EXCEPTION_WAITING", partnerName) .. iRC.Colors.Reset)
            else
                iRC:RecordGuildFoundAudit("TRADE_BLOCKED", partnerName)
                self:ShowGuildFoundRestriction(iRC:Text("GUILD_FOUND_TRADE_BLOCKED",
                    partnerName or iRC:Text("GUILD_FOUND_UNKNOWN_PLAYER"), reason or iRC:Text("GUILD_FOUND_TRADE_REASON")))
            end
        end
    end
    captureProtectedTradeEvidence()
end

function Enforcement:InstallTradeGuards()
    if type(hooksecurefunc) ~= "function" then return end
    local function recheck()
        if refreshingTradeGuard then return end
        refreshingTradeGuard = true
        local ok, err = pcall(self.UpdateTradeRestriction, self)
        refreshingTradeGuard = false
        if not ok then
            local button = getTradeAcceptButton()
            if button and isTradeWindowOpen() and isGuildFoundEconomyActive() then
                button.iRCRestricted, button.iRCApprovedException, button.enabled = true, nil, false
                button:SetEnabled(false)
            end
            iRC:DebugMsg("Guild Found trade check failed: " .. tostring(err), 1)
        end
    end
    -- Native money edits, item updates and confirmation dialogs can re-enable
    -- Trade after our event handler. Recheck after their work, in either order.
    local installed = 0
    for _, name in ipairs({ "TradeFrameTradeButton_Enable", "TradeFrameTradeButton_SetToEnabledState",
        "TradeFrame_UpdateMoney", "TradeFrame_OnEvent" }) do
        if not tradeHooksInstalled[name] and type(_G[name]) == "function" then
            local ok, err = pcall(hooksecurefunc, name, recheck)
            if ok then installed = installed + 1
            elseif tradeHooksInstalled[name] == nil then
                iRC:DebugMsg("Could not protect trade control " .. name .. ": " .. tostring(err), 2)
            end
            tradeHooksInstalled[name] = ok
        end
    end
    if installed > 0 then iRC:DebugMsg("Installed " .. installed .. " Guild Found trade control guard(s).", 3) end
end

function Enforcement:RecordApprovedTradeException(playerAccepted)
    if playerAccepted ~= true and playerAccepted ~= 1 then return false end
    self:UpdateTradeRestriction()
    local button = getTradeAcceptButton()
    local note = button and button.iRCApprovedException
    if approvedTradeExceptionRecorded or not note then return false end
    local partnerName = getTradePartnerName()
    if not partnerName then return false end
    if protectedTradeEvidence then
        protectedTradeEvidence.playerAccepted = true
        protectedTradeEvidence.exception = note
    end
    approvedTradeExceptionRecorded = true
    iRC:RecordGuildFoundAudit("TRADE_EXCEPTION_APPROVED",
        partnerName .. " (" .. tostring(note) .. ")")
    return true
end

local function canSendGuildFoundMail(recipient)
    if not recipient or iRC:NormalizeName(recipient) == "" then return false end
    local allowed, reason = iRC:GetGuildFoundTradeStatus(recipient, true)
    if allowed then return true end
    local rules = iRC:GetConnectionRules()
    local settings = iRC:GetGuildFoundTradeExceptionSettings()
    if rules.guildFoundTradeExceptions == true and settings.outgoingMail == true then
        -- C.O.D. would bring payment back from an external player. This
        -- exception only permits items and money to leave the guild.
        -- The typed amount is not copied into GetSendMailCOD until Send is
        -- clicked, so check the selected C.O.D. mode while editing too.
        local codButton = _G.SendMailCODButton
        if codButton and type(codButton.GetChecked) == "function" then
            local checked, selected = pcall(codButton.GetChecked, codButton)
            if not checked or iRC:IsSecretValue(selected) or selected then
                return false, iRC:Text("GUILD_FOUND_MAIL_COD_RESTRICTED")
            end
        end
        local ok, cod = false, nil
        if type(GetSendMailCOD) == "function" then ok, cod = pcall(GetSendMailCOD) end
        if ok and not (iRC.HasSecretValues and iRC:HasSecretValues(cod))
            and type(cod) == "number" and cod == 0 then
            return true, nil, true
        end
        return false, iRC:Text("GUILD_FOUND_MAIL_COD_RESTRICTED")
    end
    return false, reason
end

function Enforcement:UpdateMailRestriction()
    local button = getSendMailButton()
    if not button or not button.SetEnabled then return end
    if mailSendPending then
        button.iRCMailRestricted = true
        button:SetEnabled(false)
        return false
    end
    if not isGuildFoundEconomyActive() then
        local wasRestricted = button.iRCMailRestricted
        button.iRCMailRestricted = nil
        if wasRestricted then
            if SendMailFrame_CanSend then SendMailFrame_CanSend() else button:SetEnabled(true) end
        end
        return true
    end

    local recipient = getMailRecipient()
    local allowed, reason = false, nil
    if recipient and finalizedMailRecipient == iRC:NormalizeName(recipient) then
        allowed, reason = canSendGuildFoundMail(recipient)
    end
    if allowed then
        local wasRestricted = button.iRCMailRestricted
        button.iRCMailRestricted = nil
        if wasRestricted then
            if SendMailFrame_CanSend then SendMailFrame_CanSend() else button:SetEnabled(true) end
        end
    else
        button.iRCMailRestricted = true
        button:SetEnabled(false)
    end
    return allowed, reason
end

function Enforcement:FinalizeMailRecipient()
    local recipient = getMailRecipient()
    finalizedMailRecipient = recipient and iRC:NormalizeName(recipient) or nil
    return self:UpdateMailRestriction()
end

function Enforcement:InstallMailRecipientGuard()
    local field = _G.SendMailNameEditBox
        or (_G.MailFrame and _G.MailFrame.SendMailFrame and _G.MailFrame.SendMailFrame.RecipientEditBox)
    if not field or field.iRCMailGuardHooked or not field.HookScript then return end
    field.iRCMailGuardHooked = true
    local function editing()
        finalizedMailRecipient = nil
        Enforcement:UpdateMailRestriction()
    end
    field:HookScript("OnTextChanged", editing)
    field:HookScript("OnEditFocusGained", editing)
    for _, script in ipairs({ "OnEditFocusLost", "OnEnterPressed", "OnTabPressed" }) do
        field:HookScript(script, function() Enforcement:FinalizeMailRecipient() end)
    end
end

function Enforcement:InstallMailSendGuards()
    if type(hooksecurefunc) ~= "function" then return end
    local function recheck()
        if refreshingMailGuard then return end
        refreshingMailGuard = true
        local ok, err = pcall(self.UpdateMailRestriction, self)
        if not ok then
            local button = getSendMailButton()
            if button and isGuildFoundEconomyActive() then
                button.iRCMailRestricted = true
                pcall(button.SetEnabled, button, false)
            end
            iRC:DebugMsg("Guild Found mail check failed: " .. tostring(err), 1)
        end
        refreshingMailGuard = false
    end
    -- Some mail edits enable the button directly, bypassing Blizzard's named
    -- refresh helpers. Apply the same recipient check after either method.
    local button = getSendMailButton()
    if button then
        button.iRCMailEnableGuards = button.iRCMailEnableGuards or {}
        for _, method in ipairs({ "Enable", "SetEnabled" }) do
            if not button.iRCMailEnableGuards[method] and type(button[method]) == "function" then
                local ok, err = pcall(hooksecurefunc, button, method, recheck)
                button.iRCMailEnableGuards[method] = ok
                if ok then iRC:DebugMsg("Installed Guild Found mail button guard: " .. method .. ".", 3)
                else iRC:DebugMsg("Could not protect the mail button's " .. method .. ": " .. tostring(err), 2) end
            end
        end
    end
    -- Blizzard refreshes Send after name, subject, attachment and money edits.
    -- A native refresh must not enable an unfinished or restricted recipient.
    for _, name in ipairs({ "SendMailFrame_CanSend", "SendMailFrame_EnableSendMailButton" }) do
        if not mailHooksInstalled[name] and type(_G[name]) == "function" then
            mailHooksInstalled[name] = pcall(hooksecurefunc, name, recheck)
        end
    end
    local mailFrame = _G.MailFrame
    if mailFrame and not mailFrame.iRCMailSendGuardHooked and type(mailFrame.OnEvent) == "function" then
        mailFrame.iRCMailSendGuardHooked = pcall(hooksecurefunc, mailFrame, "OnEvent", recheck)
    end
    if not mailHooksInstalled.SendMail and type(SendMail) == "function" then
        mailHooksInstalled.SendMail = pcall(hooksecurefunc, "SendMail", function(recipient)
            if not isGuildFoundEconomyActive() then return end
            mailSendPending, restrictedMailEvidence, approvedMailExceptionRecipient = true, nil, nil
            local allowed, reason, mailException = canSendGuildFoundMail(recipient)
            if mailException then approvedMailExceptionRecipient = recipient end
            if not allowed then
                -- Bind evidence to the submitted name, never to text that may
                -- change or be reset before MAIL_SEND_SUCCESS arrives.
                restrictedMailEvidence = { recipient = recipient, money = GetMoney and GetMoney() or nil, startedAt = time() }
                iRC:RecordGuildFoundAudit("MAIL_BLOCKED", recipient)
                self:ShowGuildFoundRestriction(iRC:Text("GUILD_FOUND_MAIL_BLOCKED", recipient,
                    reason or iRC:Text("GUILD_FOUND_MAIL_REASON")))
            end
            recheck()
        end)
    end
end

local function getInboxRestriction(index, statusCache)
    if not isGuildFoundEconomyActive() or not GetInboxHeaderInfo then return false end
    local packageIcon, _, sender, _, money, codAmount, _, hasItem, _, _, _, canReply, isGameMaster = GetInboxHeaderInfo(index)
    if iRC.HasSecretValues and iRC:HasSecretValues(packageIcon, sender, money, codAmount, hasItem, canReply, isGameMaster) then return true, nil, true end
    local containsValue = (tonumber(money) or 0) > 0 or (tonumber(codAmount) or 0) > 0
        or hasItem == true or type(hasItem) == "number" and hasItem > 0
    -- Blizzard briefly clears the header after the final attachment is
    -- collected. Keep unavailable mail disabled, without treating that
    -- empty transition as a new forbidden delivery.
    if not sender or sender == "" then return true, nil, not containsValue end

    -- Auction House proceeds and purchases are external economy even though
    -- their sender is a system entity rather than a player character.
    if packageIcon == 134939 then return true, sender end
    if GetInboxInvoiceInfo then
        local invoiceType = GetInboxInvoiceInfo(index)
        if invoiceType then return true, sender end
    end

    local allowed = statusCache and statusCache[sender]
    if allowed == nil then
        allowed = iRC:GetGuildFoundTradeStatus(sender, true) == true
        if statusCache then statusCache[sender] = allowed end
    end
    if allowed then return false end
    if not containsValue then return false end

    -- Quest rewards and other game-generated deliveries remain usable. They
    -- cannot be replied to; ordinary player mail can.
    if canReply == false or isGameMaster then return false end
    return true, sender
end

local function currentInboxIndex(index)
    return tonumber(index)
        or (_G.OpenMailFrame and (_G.OpenMailFrame.openMailID or _G.OpenMailFrame.mailIndex))
        or (_G.InboxFrame and _G.InboxFrame.openMailID)
end

local function recordRestrictedInboxBypass(action, index)
    if not isGuildFoundEconomyActive() then return end
    index = currentInboxIndex(index)
    local blocked, sender, pending
    if index then blocked, sender, pending = getInboxRestriction(index) end
    if pending then blocked = false end
    if not blocked and protectedInboxEvidence and protectedInboxEvidence.index == index then
        blocked, sender = true, protectedInboxEvidence.sender
    end
    if not blocked then return end
    local key = tostring(index) .. ":" .. tostring(sender or "")
    if restrictedInboxBypassKey == key then return end
    restrictedInboxBypassKey = key
    local currentMoney = GetMoney and GetMoney() or nil
    flagProtectedInteraction("INBOX_BLOCK_BYPASS", {
        money = protectedInboxEvidence and protectedInboxEvidence.money or currentMoney,
        startedAt = protectedInboxEvidence and protectedInboxEvidence.startedAt or time(),
    })
    iRC:RecordGuildFoundAudit("INBOX_BLOCKED", tostring(sender or "") .. " (" .. action .. ")")
end

function Enforcement:InstallInboxAPIGuards()
    if not hooksecurefunc then return end
    for _, functionName in ipairs({ "TakeInboxMoney", "TakeInboxItem", "AutoLootMailItem" }) do
        local hookedName = functionName
        if not inboxHooksInstalled[hookedName] and type(_G[hookedName]) == "function" then
            local hooked = pcall(hooksecurefunc, hookedName, function(index)
                recordRestrictedInboxBypass(hookedName, index)
            end)
            if hooked then
                inboxHooksInstalled[hookedName] = true
            else
                iRC:DebugMsg("Guild Found could not monitor the modern " .. hookedName .. " mail API.", 2)
            end
        end
    end
    local function recheck()
        if refreshingInboxGuard then return end
        refreshingInboxGuard = true
        local ok, err = pcall(self.UpdateInboxRestriction, self)
        refreshingInboxGuard = false
        if not ok then iRC:DebugMsg("Guild Found inbox check failed: " .. tostring(err), 1) end
    end
    for _, owner in pairs({ _G.OpenMailFrame, _G.InboxFrame, _G.MailFrame and _G.MailFrame.InboxFrame }) do
        owner.iRCInboxControlHooks = owner.iRCInboxControlHooks or {}
        for _, method in ipairs({ "Update", "FocusGamepad", "RefreshFooter" }) do
            if not owner.iRCInboxControlHooks[method] and type(owner[method]) == "function" then
                owner.iRCInboxControlHooks[method] = pcall(hooksecurefunc, owner, method, recheck)
            end
        end
        local bulk = owner.OpenAllMail
        if bulk and not bulk.iRCStopHooked and type(bulk.StopOpening) == "function" then
            bulk.iRCStopHooked = pcall(hooksecurefunc, bulk, "StopOpening", recheck)
        end
    end
end

function Enforcement:IsInboxMailRestricted(index)
    return getInboxRestriction(index)
end

function Enforcement:ShowInboxRestriction(index, sender)
    iRC:RecordGuildFoundAudit("INBOX_BLOCKED", sender)
    self:ShowGuildFoundRestriction(iRC:Text("GUILD_FOUND_INBOX_BLOCKED", sender and iRC:FormatPlayerName(sender) or iRC:Text("GUILD_FOUND_UNKNOWN_SENDER")))
end

local function setControlRestricted(control, restricted)
    if not control or not control.SetEnabled then return end
    if restricted then
        control.iRCRestricted = true
        control:SetEnabled(false)
    elseif control.iRCRestricted then
        control.iRCRestricted = nil
        control:SetEnabled(true)
    end
end

local function restrictInboxFooter(owner, restricted)
    local footer = owner and owner.gamepadFooter
    if not footer then return end
    if restricted and footer.HideAndDeactivateBindings then
        footer:HideAndDeactivateBindings()
        owner.iRCInboxFooterRestricted = true
    elseif owner.iRCInboxFooterRestricted then
        owner.iRCInboxFooterRestricted = nil
        if InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()
            and owner.IsShown and owner:IsShown() and footer.ShowAndActivateBindings then
            footer:ShowAndActivateBindings()
        end
    end
end

function Enforcement:UpdateInboxRestriction()
    local index = (_G.OpenMailFrame and (_G.OpenMailFrame.openMailID or _G.OpenMailFrame.mailIndex))
        or (_G.InboxFrame and _G.InboxFrame.openMailID)
    local blocked, sender, pending = false, nil, false
    if index then blocked, sender, pending = getInboxRestriction(index) end
    setControlRestricted(_G.OpenMailMoneyButton, blocked)
    setControlRestricted(_G.OpenMailPackageButton, blocked)
    setControlRestricted(_G.OpenMailLetterButton, blocked)
    for slot = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
        setControlRestricted(_G["OpenMailAttachmentButton" .. slot], blocked)
    end
    local restrictionKey = blocked and not pending and tostring(index) .. ":" .. tostring(sender or "") or nil
    if pending then
        -- Preserve a previously blocked action for the API post-hook, even
        -- when its header disappears before that hook runs.
        if protectedInboxEvidence and protectedInboxEvidence.index ~= tonumber(index) then protectedInboxEvidence = nil end
    elseif blocked and (not protectedInboxEvidence or protectedInboxEvidence.key ~= restrictionKey) then
        protectedInboxEvidence = {
            key = restrictionKey,
            index = tonumber(index),
            sender = sender,
            money = GetMoney and GetMoney() or nil,
            startedAt = time(),
        }
    elseif not blocked then
        protectedInboxEvidence = nil
    end
    if not pending then
        if restrictionKey and restrictionKey ~= lastInboxRestrictionKey then
            self:ShowInboxRestriction(index, sender)
        end
        lastInboxRestrictionKey = restrictionKey
    end
    restrictInboxFooter(_G.OpenMailFrame, blocked)
    local inbox = _G.InboxFrame or (_G.MailFrame and _G.MailFrame.InboxFrame)
    local bulk = inbox and inbox.OpenAllMail
    if bulk then
        local bulkBlocked = false
        if isGuildFoundEconomyActive() then
            local count = GetInboxNumItems and GetInboxNumItems()
            if type(count) ~= "number" or iRC.HasSecretValues and iRC:HasSecretValues(count) then
                bulkBlocked = true
            else
                local statuses = {}
                for mailIndex = 1, count do
                    if getInboxRestriction(mailIndex, statuses) then bulkBlocked = true; break end
                end
            end
        end
        if bulkBlocked and bulk.timeUntilNextRetrieval ~= nil and type(bulk.StopOpening) == "function" then bulk:StopOpening() end
        setControlRestricted(bulk, bulkBlocked)
        restrictInboxFooter(inbox, bulkBlocked)
    end
end

function Enforcement:InstallMailAPIGuards()
    -- Restrict Blizzard's controls instead of replacing protected global APIs.
    self:InstallInboxAPIGuards()
    self:InstallMailRecipientGuard()
    self:InstallMailSendGuards()
    self:UpdateMailRestriction()
    self:UpdateInboxRestriction()
end

function Enforcement:CloseRestrictedAuctionHouse()
    if not isGuildFoundEconomyActive() then return end
    iRC:RecordGuildFoundAudit("AUCTION_HOUSE_BLOCKED", "")
    self:ShowGuildFoundRestriction(iRC:Text("GUILD_FOUND_AUCTION_HOUSE_CLOSED"))
    local closeAuctionHouse = function()
        if not isGuildFoundEconomyActive() then return end
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

-- Group-rule protection and incident reporting -----------------------------

local function canSafelyLeaveGroup()
    if InCombatLockdown and InCombatLockdown() then return false end
    if UnitAffectingCombat and UnitAffectingCombat("player") then return false end
    if IsInInstance then
        local inInstance = IsInInstance()
        if inInstance then return false end
    end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return false end
    if UnitOnTaxi and UnitOnTaxi("player") then return false end
    return true
end

local function clearUnsafeGroupWarning()
    local wasActive = pendingUnsafeGroupReason ~= nil
    pendingUnsafeGroupReason = nil
    pendingGroupViolationKey = nil
    pendingGroupLeaveConfirmation = nil
    groupWarningFrame:Hide()
    if wasActive and iRC.SendHello then iRC:SendHello() end
end

function Enforcement:IsCurrentGroupViolation()
    return pendingUnsafeGroupReason ~= nil
end

local function reportPendingGroupViolation()
    if not pendingGroupViolation or pendingGroupViolation.reported then return end
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then return end
    if iRC.SendGroupViolation and iRC:SendGroupViolation(pendingGroupViolation) then
        pendingGroupViolation.reported = true
    elseif C_Timer and C_Timer.After then
        C_Timer.After(30, reportPendingGroupViolation)
    end
end

function iRC:MarkGroupViolationReported(violationId)
    if not violationId or violationId == "" then return end
    local connection = self:GetConnection()
    for _, record in ipairs(connection and connection.groupViolations or {}) do
        if record.id == violationId then record.reported = true end
    end
    if pendingGroupViolation and pendingGroupViolation.id == violationId then
        pendingGroupViolation.reported = true
    end
end

local function recordGroupViolation(reason, players)
    local names = {}
    for _, name in ipairs(players or {}) do if name and name ~= "" then names[#names + 1] = name end end
    if #names == 0 then names[1] = iRC:Text("GROUP_VIOLATION_UNKNOWN_PLAYER") end
    table.sort(names)
    local key = reason .. "|" .. table.concat(names, ",")
    if pendingGroupViolationKey == key then reportPendingGroupViolation(); return end
    local instanceName = GetInstanceInfo and GetInstanceInfo() or nil
    if not instanceName or instanceName == "" then instanceName = GetZoneText and GetZoneText() or iRC:Text("GROUP_VIOLATION_UNKNOWN_LOCATION") end
    local record = {
        occurredAt = time(), instanceName = instanceName, players = names,
        reason = reason, reported = false,
    }
    local connection = iRC:GetConnection()
    if connection then
        connection.groupViolations = connection.groupViolations or {}
        connection.groupViolations[#connection.groupViolations + 1] = record
        while #connection.groupViolations > 100 do table.remove(connection.groupViolations, 1) end
    end
    pendingGroupViolation, pendingGroupViolationKey = record, key
    reportPendingGroupViolation()
end

local function leaveCurrentGroup(reason)
    if groupLeaving then return true end
    if not canSafelyLeaveGroup() then return false end
    groupLeaving = true
    local channel = IsInRaid and IsInRaid() and "RAID" or "PARTY"
    if SendChatMessage then SendChatMessage(reason, channel) end
    iRC:Print(iRC.Colors.Red .. iRC:Text("GROUP_AUTO_LEFT_LOCAL", reason) .. iRC.Colors.Reset)
    if C_PartyInfo and C_PartyInfo.LeaveParty then
        C_PartyInfo.LeaveParty()
    end
    clearUnsafeGroupWarning()
    if C_Timer and C_Timer.After then C_Timer.After(1, function() groupLeaving = false end) else groupLeaving = false end
    return true
end

local function handleInvalidGroup(reason, players)
    local confirmationPlayers = {}
    for _, name in ipairs(players or {}) do
        if name and name ~= "" then confirmationPlayers[#confirmationPlayers + 1] = name end
    end
    table.sort(confirmationPlayers)
    local confirmationKey = reason .. "|" .. table.concat(confirmationPlayers, ",")
    local now = time()

    -- Never leave on the first roster reading. Group data can be incomplete
    -- immediately after login, reload, zoning, invites, or roster updates.
    -- The same violation must still exist after the confirmation window.
    if not pendingGroupLeaveConfirmation or pendingGroupLeaveConfirmation.key ~= confirmationKey then
        pendingGroupLeaveConfirmation = { key = confirmationKey, readyAt = now + 5 }
        groupWarningFrame.text:SetText(iRC:Text("GROUP_CONFIRMING_WARNING"))
        groupWarningFrame:Show()
        iRC:Print(iRC.Colors.Red .. iRC:Text("GROUP_CONFIRMING_NOTICE") .. iRC.Colors.Reset)
        if C_Timer and C_Timer.After then
            C_Timer.After(5, function()
                if pendingGroupLeaveConfirmation and pendingGroupLeaveConfirmation.key == confirmationKey then
                    Enforcement:CheckGroup()
                end
            end)
        end
        return
    end
    if now < pendingGroupLeaveConfirmation.readyAt then return end

    -- Record and report only after the second reading confirmed the violation.
    recordGroupViolation(reason, players)
    if leaveCurrentGroup(reason) then return end
    if pendingUnsafeGroupReason ~= reason then
        iRC:Print(iRC.Colors.Red .. iRC:Text("GROUP_UNSAFE_DEFERRED") .. iRC.Colors.Reset)
    end
    local becameActive = pendingUnsafeGroupReason == nil
    pendingUnsafeGroupReason = reason
    groupWarningFrame.text:SetText(iRC:Text("GROUP_UNSAFE_WARNING"))
    groupWarningFrame:Show()
    if becameActive and iRC.SendHello then iRC:SendHello() end
end

local function getCurrentGroupSize()
    if IsInRaid and IsInRaid() then return GetNumGroupMembers and GetNumGroupMembers() or 0 end
    return GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
end

local function clearGroupSafety()
    groupSafety.sameRace, groupSafety.guildOnly = false, false
    clearUnsafeGroupWarning()
end

local function protectExistingGroup(allRules, newLevel)
    if getCurrentGroupSize() < 1 then return end
    local rules, protected = iRC:GetConnectionRules(), false
    local previousLevel = newLevel and math.max(0, newLevel - 1) or nil
    local sameRaceLevel = math.max(1, math.min(60, math.floor(tonumber(rules.sameRaceMinimumLevel) or 1)))
    local guildOnlyLevel = math.max(1, math.min(60, math.floor(tonumber(rules.guildGroupsMinimumLevel) or 1)))
    if (allRules and rules.sameRaceGroupsOnly)
        or (rules.sameRaceGroupsOnly and previousLevel < sameRaceLevel and newLevel >= sameRaceLevel) then
        groupSafety.sameRace, protected = true, true
    end
    if (allRules and rules.guildGroupsOnly)
        or (rules.guildGroupsOnly and previousLevel < guildOnlyLevel and newLevel >= guildOnlyLevel) then
        groupSafety.guildOnly, protected = true, true
    end
    if protected then iRC:Print(iRC.Colors.Yellow .. iRC:Text("GROUP_SAFETY_ACTIVE") .. iRC.Colors.Reset) end
end

local function protectNewlyActivatedRestrictions()
    local rules, level = iRC:GetConnectionRules(), UnitLevel("player") or 0
    local sameRaceLevel = math.max(1, math.min(60, math.floor(tonumber(rules.sameRaceMinimumLevel) or 1)))
    local guildOnlyLevel = math.max(1, math.min(60, math.floor(tonumber(rules.guildGroupsMinimumLevel) or 1)))
    local current = {
        sameRace = isRuleEnabled("sameRaceGroupsOnly") and level >= sameRaceLevel
            and not (rules.allowLevel60MixedRaceGroups and level >= 60),
        guildOnly = isRuleEnabled("guildGroupsOnly") and level >= guildOnlyLevel,
    }
    local protected = false
    if observedGroupRestrictions and getCurrentGroupSize() > 0 then
        for key, active in pairs(current) do
            if active and not observedGroupRestrictions[key] and not groupSafety[key] then
                groupSafety[key], protected = true, true
            end
        end
    end
    observedGroupRestrictions = current
    if protected then iRC:Print(iRC.Colors.Yellow .. iRC:Text("GROUP_SAFETY_ACTIVE") .. iRC.Colors.Reset) end
end

function Enforcement:CheckGroup()
    if groupLeaving then return end
    -- Forever protects group unit fields during encounters. The roster is
    -- checked again on PLAYER_REGEN_ENABLED, so never inspect it while secret.
    if iRC:IsForeverClient() and ((InCombatLockdown and InCombatLockdown())
        or (UnitAffectingCombat and UnitAffectingCombat("player"))) then return end
    local _, playerRace = UnitRace("player")
    if not playerRace then return end
    local inRaid = IsInRaid and IsInRaid()
    local memberCount = inRaid and (GetNumGroupMembers and GetNumGroupMembers() or 0) or (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0)
    if memberCount < 1 then clearGroupSafety(); return end
    local rules = iRC:GetConnectionRules()
    local playerLevel = UnitLevel("player") or 0
    local sameRaceMinimumLevel = math.max(1, math.min(60, math.floor(tonumber(rules.sameRaceMinimumLevel) or 1)))
    local level60SameRaceException = rules.allowLevel60MixedRaceGroups and (UnitLevel("player") or 0) >= 60
    if isRuleEnabled("sameRaceGroupsOnly") and playerLevel >= sameRaceMinimumLevel and not level60SameRaceException and not groupSafety.sameRace then
        local wrongRacePlayers = {}
        for index = 1, memberCount do
            local unit = inRaid and "raid" .. index or "party" .. index
            if not UnitIsUnit or not UnitIsUnit(unit, "player") then
                local _, memberRace = UnitRace(unit)
                if memberRace and memberRace ~= playerRace then
                    wrongRacePlayers[#wrongRacePlayers + 1] = GetUnitName and GetUnitName(unit, true) or UnitName(unit)
                end
            end
        end
        if #wrongRacePlayers > 0 then
            handleInvalidGroup(iRC:Text("SAME_RACE_GROUP_LEAVE"), wrongRacePlayers)
            return
        end
    end
    local guildGroupsMinimumLevel = math.max(1, math.min(60, math.floor(tonumber(rules.guildGroupsMinimumLevel) or 1)))
    if isRuleEnabled("guildGroupsOnly") and playerLevel >= guildGroupsMinimumLevel and not groupSafety.guildOnly and not iRC:IsGuildOnlyGroup() then
        local nonGuildPlayers = {}
        for index = 1, memberCount do
            local unit = inRaid and "raid" .. index or "party" .. index
            if (not UnitIsUnit or not UnitIsUnit(unit, "player")) then
                local name = GetUnitName and GetUnitName(unit, true) or UnitName(unit)
                if name and not iRC:IsGuildMemberName(name) then nonGuildPlayers[#nonGuildPlayers + 1] = name end
            end
        end
        handleInvalidGroup(iRC:Text("GUILD_GROUP_ONLY_LEAVE"), nonGuildPlayers)
        return
    end
    clearUnsafeGroupWarning()
end

-- Event-driven refresh ------------------------------------------------------

function Enforcement:Refresh()
    if iRC.RaceLockedSync then iRC.RaceLockedSync:RefreshMoneyMonitoring() end
    installLanguageHooks()
    iRC:RecordSelfFoundState()
    scheduleLanguageApply()
    self:UpdateSelfFoundWarning()
    self:InstallTradeGuards()
    self:UpdateTradeRestriction()
    self:UpdateMailRestriction()
    self:UpdateInboxRestriction()
    protectNewlyActivatedRestrictions()
    if C_Timer and C_Timer.After then C_Timer.After(0, function() Enforcement:CheckGroup() end) else self:CheckGroup() end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("LANGUAGE_LIST_CHANGED")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_ALIVE")
frame:RegisterEvent("PLAYER_CONTROL_GAINED")
frame:RegisterEvent("TRADE_SHOW")
frame:RegisterEvent("TRADE_UPDATE")
if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid("TRADE_ACCEPT_UPDATE") then
    frame:RegisterEvent("TRADE_ACCEPT_UPDATE")
end
frame:RegisterEvent("TRADE_CLOSED")
frame:RegisterEvent("AUCTION_HOUSE_SHOW")
frame:RegisterEvent("MAIL_SHOW")
frame:RegisterEvent("MAIL_INBOX_UPDATE")
frame:RegisterEvent("MAIL_SEND_INFO_UPDATE")
frame:RegisterEvent("SEND_MAIL_COD_CHANGED")
frame:RegisterEvent("SEND_MAIL_MONEY_CHANGED")
frame:RegisterEvent("MAIL_CLOSED")
frame:RegisterEvent("MAIL_SEND_SUCCESS")
frame:RegisterEvent("MAIL_FAILED")
frame:RegisterEvent("MAIL_SUCCESS")
frame:SetScript("OnEvent", function(_, event, unit, targetAccepted)
    if event == "PLAYER_LOGIN" then
        initialGroupProtectionPending = true
        protectExistingGroup(true)
        Enforcement:InstallMailAPIGuards()
        Enforcement:Refresh()
        local connection = iRC:GetConnection()
        for index = #(connection and connection.groupViolations or {}), 1, -1 do
            local record = connection.groupViolations[index]
            if not record.reported then pendingGroupViolation = record; break end
        end
        reportPendingGroupViolation()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- A full login can expose the saved group one event later than
        -- PLAYER_LOGIN. Protect it once here as well. Do not repeat this on
        -- later zone/instance transitions, which could otherwise grandfather
        -- a newly formed invalid group.
        if initialGroupProtectionPending then
            initialGroupProtectionPending = false
            protectExistingGroup(true)
        end
        iRC.SelfFoundAuraReady = false
        Enforcement:Refresh()
        if C_Timer and C_Timer.After then
            C_Timer.After(3, function()
                iRC.SelfFoundAuraReady = true
                Enforcement:Refresh()
            end)
        else
            iRC.SelfFoundAuraReady = true
        end
    elseif event == "TRADE_CLOSED" then
        local evidence = protectedTradeEvidence
        protectedTradeEvidence = nil
        if evidence and evidence.playerAccepted and (evidence.restricted or evidence.exception)
            and C_Timer and C_Timer.After then
            C_Timer.After(0.5, function()
                local currentMoney = GetMoney and GetMoney() or nil
                if evidence.money ~= nil and currentMoney ~= nil and evidence.money ~= currentMoney then
                    flagProtectedInteraction(evidence.exception and "TRADE_EXCEPTION_MONEY" or "TRADE_BLOCK_BYPASS", evidence)
                end
            end)
        end
        restrictedTradeCancelled = false
        approvedTradeExceptionRecorded = false
        lastTradeRestrictionReason = nil
    elseif event == "TRADE_ACCEPT_UPDATE" then
        Enforcement:UpdateTradeRestriction()
        captureProtectedTradeEvidence()
        if protectedTradeEvidence then
            protectedTradeEvidence.playerAccepted = unit == true or unit == 1
            protectedTradeEvidence.targetAccepted = targetAccepted == true or targetAccepted == 1
            if protectedTradeEvidence.playerAccepted and protectedTradeEvidence.restricted
                and not protectedTradeEvidence.violationRecorded then
                protectedTradeEvidence.violationRecorded = flagProtectedInteraction("TRADE_BLOCK_BYPASS", protectedTradeEvidence)
            end
        end
        Enforcement:RecordApprovedTradeException(unit)
    elseif event == "TRADE_SHOW" or event == "TRADE_UPDATE" then
        Enforcement:InstallTradeGuards()
        Enforcement:CheckTradeRestriction()
        Enforcement:UpdateTradeRestriction()
    elseif event == "AUCTION_HOUSE_SHOW" then
        Enforcement:CloseRestrictedAuctionHouse()
    elseif event == "MAIL_SHOW" then
        Enforcement:InstallMailAPIGuards()
        Enforcement:InstallMailRecipientGuard()
        Enforcement:UpdateMailRestriction()
    elseif event == "MAIL_INBOX_UPDATE" then
        Enforcement:InstallMailAPIGuards()
        Enforcement:UpdateInboxRestriction()
    elseif event == "MAIL_SEND_INFO_UPDATE" or event == "SEND_MAIL_COD_CHANGED" or event == "SEND_MAIL_MONEY_CHANGED" then
        Enforcement:InstallMailAPIGuards()
        Enforcement:UpdateMailRestriction()
    elseif event == "MAIL_SEND_SUCCESS" then
        if restrictedMailEvidence then flagProtectedInteraction("MAIL_BLOCK_BYPASS", restrictedMailEvidence) end
        if approvedMailExceptionRecipient then
            iRC:RecordGuildFoundAudit("MAIL_EXCEPTION_APPROVED", approvedMailExceptionRecipient)
        end
        restrictedMailEvidence, mailSendPending, approvedMailExceptionRecipient = nil, false, nil
        Enforcement:UpdateMailRestriction()
    elseif event == "MAIL_FAILED" then
        restrictedMailEvidence, mailSendPending, approvedMailExceptionRecipient = nil, false, nil
        Enforcement:UpdateMailRestriction()
    elseif event == "MAIL_SUCCESS" then
        Enforcement:UpdateMailRestriction()
    elseif event == "MAIL_CLOSED" then
        finalizedMailRecipient = nil
        restrictedInboxBypassKey = nil
        protectedInboxEvidence = nil
        lastInboxRestrictionKey = nil
    elseif event == "UNIT_AURA" and unit ~= "player" then
        return
    elseif event == "PLAYER_LEVEL_UP" then
        protectExistingGroup(false, tonumber(unit) or UnitLevel("player") or 0)
        Enforcement:Refresh()
    elseif event == "GROUP_ROSTER_UPDATE" then
        if getCurrentGroupSize() < 1 then clearGroupSafety() end
        if C_Timer and C_Timer.After then C_Timer.After(0, function() Enforcement:CheckGroup() end) else Enforcement:CheckGroup() end
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ALIVE" or event == "PLAYER_CONTROL_GAINED" then
        reportPendingGroupViolation()
        Enforcement:CheckGroup()
    else
        Enforcement:Refresh()
    end
end)

