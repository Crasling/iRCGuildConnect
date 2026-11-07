-- Guild Found economy guards; no game, chat or network writes.
local accepted, sentMail, inboxItems, inboxMoney, autoLoot = 0, 0, 0, 0, 0
local tradePartner = "Outside"
local tradeOpen, exceptionEnabled, playerTradeLink = true, false, nil
local targetTradeLink, playerOffer, targetOffer, typedOffer = nil, 0, 0, 0
local mailSubject, mailLookups, economyActive = "", 0, true
local outgoingMailEnabled, mailCOD = false, 0
function GetSendMailCOD() return mailCOD end
local audits, discrepancies, frames = {}, {}, {}
local completedInbox, completeOnTake, eventFrame = {}, {}, nil
local attachmentSender = "Guildie"

local function control()
    return { active = true, SetEnabled = function(self, value) self.active = value and true or false end,
        Enable = function(self) self.active = true end }
end

UIParent = {}
TradeFrame = { IsShown = function() return tradeOpen end }
TradeFrameTradeButton = control()
SendMailMailButton = control()
SendMailNameEditBox = { text = "", hooks = {}, GetText = function(self) return self.text end,
    HookScript = function(self, script, callback) self.hooks[script] = callback end }
function SendMailNameEditBox:SetText(text)
    self.text = text
    if self.hooks.OnTextChanged then self.hooks.OnTextChanged(self, true) end
end
OpenMailFrame = {}
OpenMailMoneyButton = control()
OpenMailPackageButton = control()
OpenMailAttachmentButton1 = control()
ATTACHMENTS_MAX_RECEIVE = 1
function UnitLevel() return 60 end
function UnitClass() return "Rogue", "ROGUE" end
function time() return 1800000000 end
function GetMoney() return 12345 end
function CreateFrame()
    local frame = {}
    function frame:SetSize() end
    function frame:SetPoint() end
    function frame:Hide() end
    function frame:SetShown() end
    function frame:RegisterEvent() end
    function frame:SetScript(key, callback) self[key] = callback end
    function frame:CreateFontString()
        return { SetAllPoints = function() end, SetJustifyH = function() end, SetTextColor = function() end, SetText = function() end }
    end
    frames[#frames + 1] = frame
    return frame
end
function GetUnitName(unit) if unit == "NPC" then return tradePartner end end
function GetPlayerTradeMoney() return playerOffer end
function GetTargetTradeMoney() return targetOffer end
function GetTradePlayerItemLink(slot) if slot == 1 then return playerTradeLink end end
function GetTradeTargetItemLink(slot) if slot == 1 then return targetTradeLink end end
function AcceptTrade() accepted = accepted + 1 end
function SendMail() sentMail = sentMail + 1 end
local function finishPickup(index)
    if completeOnTake[index] then
        completedInbox[index] = true
        if completeOnTake[index] == "refresh-before-hook" then eventFrame.OnEvent(nil, "MAIL_INBOX_UPDATE") end
    end
end
function TakeInboxItem(index) inboxItems = inboxItems + 1; finishPickup(index) end
function TakeInboxMoney(index) inboxMoney = inboxMoney + 1; finishPickup(index) end
function AutoLootMailItem(index) autoLoot = autoLoot + 1; finishPickup(index) end
function hooksecurefunc(owner, method, callback)
    if type(owner) ~= "table" then owner, method, callback = _G, owner, method end
    local original = owner[method]
    owner[method] = function(...)
        local values = { original(...) }
        callback(...)
        return (table.unpack or unpack)(values)
    end
end
function GetInboxHeaderInfo(index)
    if completedInbox[index] then return end
    if index == 1 then return 1, nil, "Outside", nil, 0, 0, nil, true, nil, nil, nil, true, false end
    if index == 2 then return 1, nil, "Guildie", nil, 100, 0, nil, false, nil, nil, nil, true, false end
    if index == 3 then return 1, nil, "Quest NPC", nil, 0, 0, nil, true, nil, nil, nil, false, false end
    if index == 5 then return 1, nil, attachmentSender, nil, 0, 0, nil, 1, nil, nil, nil, true, false end
    if index == 6 then return 1, nil, nil, nil, 1, 0, nil, false, nil, nil, nil, true, false end
    if index == 7 then return 1, nil, "", nil, 0, 0, nil, true, nil, nil, nil, true, false end
    if index == 8 then return nil, nil, nil, nil, 0, 0, nil, 0 end
    return 134939, nil, "Auction House", nil, 100, 0, nil, false, nil, nil, nil, false, false
end
function GetInboxInvoiceInfo(index) if index == 4 then return "seller" end end

local notices = {}
local iRC = {
    Colors = { Red = "", Reset = "", Yellow = "" },
    IsGuildConnectionActive = function() return true end,
    IsGuildFoundRequired = function() return true end,
    IsGuildFoundEconomyActive = function() return economyActive end,
    GetProgressionMode = function() return "GUILD_FOUND" end,
    IsGuildMemberName = function(_, name) return name == "Guildie" end,
    GetConnectionRules = function() return { guildFoundOnly = true, guildFoundTradeExceptions = exceptionEnabled } end,
    GetGuildFoundTradeExceptionSettings = function()
        return { conjured = exceptionEnabled, outgoingMail = outgoingMailEnabled,
            items = { conjured = { [5350] = exceptionEnabled } } }
    end,
    GetSelfFoundState = function() return false end,
    GetGuildFoundTradeStatus = function(_, name, allowOffline)
        if allowOffline then mailLookups = mailLookups + 1 end
        return name == "Guildie", name == "Guildie" and nil or "outside guild"
    end,
    FindConnectionProfile = function() end,
    NormalizeName = function(_, name) return string.lower(name or "") end,
    FormatPlayerName = function(_, name) return tostring(name or "") end,
    Text = function(_, key, ...)
        local values = { ... }
        for index, value in ipairs(values) do values[index] = tostring(value) end
        return #values > 0 and key .. " " .. table.concat(values, " ") or key
    end,
    Print = function(_, message) notices[#notices + 1] = message end,
    RecordGuildFoundAudit = function(_, action, target)
        audits[#audits + 1] = { action = action, target = target }
        return true
    end,
    DebugMsg = function() end,
    IsSecretValue = function() return false end,
    RaceLockedSync = {
        FlagMonitoringDiscrepancy = function(_, reason, beforeMoney, afterMoney)
            discrepancies[#discrepancies + 1] = { reason = reason, beforeMoney = beforeMoney, afterMoney = afterMoney }
            return true
        end,
    },
    RecordSelfFoundState = function() end,
}
local private = { iRC = iRC }
assert(loadfile("iRC_Enforcement.lua"))("iRC", private)
local enforcement = assert(iRC.Enforcement)
eventFrame = frames[#frames]
enforcement:InstallMailAPIGuards()

enforcement:UpdateTradeRestriction()
assert(TradeFrameTradeButton.active == false, "external trade acceptance control is disabled")
assert(#notices == 1, "blocked trade explains the restriction in local chat")
eventFrame.OnEvent(nil, "TRADE_ACCEPT_UPDATE", 1, 0)
assert(discrepancies[#discrepancies] and discrepancies[#discrepancies].reason == "TRADE_BLOCK_BYPASS",
    "acceptance of a restricted trade creates monitoring discrepancy evidence")
eventFrame.OnEvent(nil, "TRADE_CLOSED")
tradePartner = "Guildie"
enforcement:UpdateTradeRestriction()
assert(TradeFrameTradeButton.active == true, "verified guild trade acceptance remains available")

tradePartner, exceptionEnabled, playerTradeLink = "Outside", true, "|Hitem:5350:0:0:0|h[Conjured Water]|h"
enforcement:UpdateTradeRestriction()
assert(TradeFrameTradeButton.active == true and TradeFrameTradeButton.iRCApprovedException,
    "an explicitly selected external exception item enables trade acceptance")
assert(enforcement:RecordApprovedTradeException(1), "accepting an external exception records its approval")
assert(#audits >= 1 and audits[#audits].action == "TRADE_EXCEPTION_APPROVED"
    and audits[#audits].target:find("Outside", 1, true), "approved exception audit identifies the partner")
assert(not enforcement:RecordApprovedTradeException(1), "the same trade approval is audited only once")
tradePartner, exceptionEnabled, playerTradeLink = "Guildie", false, nil

-- Reproduce the native order: iRC checks first, then Blizzard refreshes the
-- trade button or edits money. A disabled button must stay disabled afterward.
local nativeCalls, popup = {}, false
function TradeFrameTradeButton_Enable()
    nativeCalls.enable = (nativeCalls.enable or 0) + 1
    if popup then TradeFrameTradeButton.enabled = true
    else TradeFrameTradeButton:SetEnabled(true) end
end
function TradeFrameTradeButton_SetToEnabledState() TradeFrameTradeButton:SetEnabled(TradeFrameTradeButton.enabled) end
function TradeFrame_UpdateMoney()
    TradeFrameTradeButton_Enable()
    playerOffer = typedOffer
end
function TradeFrame_OnEvent(_, event)
    if event == "TRADE_UPDATE" or event == "TRADE_SHOW" then TradeFrameTradeButton_Enable() end
end
enforcement:InstallTradeGuards()
enforcement:InstallTradeGuards()
local priorNotices, priorAudits = #notices, #audits
tradePartner, exceptionEnabled = "Outside", true
eventFrame.OnEvent(nil, "TRADE_SHOW")
TradeFrame_OnEvent(TradeFrame, "TRADE_SHOW")
assert(not TradeFrameTradeButton.active, "native refresh cannot enable an empty exception trade")
assert(#audits == priorAudits and #notices == priorNotices + 1
    and notices[#notices]:find("GUILD_FOUND_TRADE_EXCEPTION_WAITING", 1, true),
    "an empty exception trade explains the waiting state once without a blocked audit")
playerTradeLink = "|Hitem:5350:0:0:0|h[Conjured Water]|h"
TradeFrame_OnEvent(TradeFrame, "TRADE_PLAYER_ITEM_CHANGED")
assert(TradeFrameTradeButton.active and TradeFrameTradeButton.iRCApprovedException,
    "adding an approved item enables an external exception trade")
TradeFrame_UpdateMoney()
assert(TradeFrameTradeButton.active, "a zero-money approved offer stays usable after native refresh")
typedOffer = 1
TradeFrame_UpdateMoney()
assert(not TradeFrameTradeButton.active and not TradeFrameTradeButton.iRCApprovedException,
    "typing one copper disables the approved exception after native money update")
assert(notices[#notices]:find("GUILD_FOUND_TRADE_EXCEPTION_REASON", 1, true),
    "the blocked offer explains exception limits rather than assuming all non-guild trades are forbidden")
local blockedAudits = #audits
TradeFrameTradeButton_Enable()
TradeFrameTradeButton.enabled = true
TradeFrameTradeButton_SetToEnabledState()
assert(not TradeFrameTradeButton.active and #audits == blockedAudits, "native enable and popup restore remain blocked without duplicate audits")
typedOffer = 0; TradeFrame_UpdateMoney()
assert(TradeFrameTradeButton.active, "removing offered money restores the allowed exception")
targetOffer = 1
TradeFrame_OnEvent(TradeFrame, "TRADE_UPDATE")
assert(not TradeFrameTradeButton.active, "incoming money also blocks an exception trade")
targetOffer = 0
targetTradeLink = "|Hitem:25:0:0:0|h[Worn Shortsword]|h"
TradeFrame_OnEvent(TradeFrame, "TRADE_TARGET_ITEM_CHANGED")
assert(not TradeFrameTradeButton.active, "an extra unapproved incoming item blocks the entire offer")
targetTradeLink, playerTradeLink = nil, "|Hitem:25:0:0:0|h[Worn Shortsword]|h"
TradeFrame_OnEvent(TradeFrame, "TRADE_PLAYER_ITEM_CHANGED")
assert(not TradeFrameTradeButton.active, "an unapproved outgoing item remains blocked")
popup = true
playerTradeLink = "|Hitem:5350:0:0:0|h[Conjured Water]|h"
TradeFrame_OnEvent(TradeFrame, "TRADE_PLAYER_ITEM_CHANGED")
assert(not TradeFrameTradeButton.active and not TradeFrameTradeButton.iRCRestricted,
    "an approved exception does not bypass Blizzard's own disabled confirmation button")
popup = false; TradeFrameTradeButton_Enable()
assert(TradeFrameTradeButton.active, "Blizzard can restore the approved offer after its confirmation")
tradePartner, exceptionEnabled, playerTradeLink = "Guildie", false, nil
TradeFrame_OnEvent(TradeFrame, "TRADE_UPDATE")
assert(TradeFrameTradeButton.active, "verified guild trades remain usable with the hooks installed")
local statusCheck = iRC.GetGuildFoundTradeStatus
iRC.GetGuildFoundTradeStatus = function() error("simulated unavailable trade status") end
TradeFrameTradeButton_Enable()
assert(not TradeFrameTradeButton.active, "a failed recheck does not leave native trade acceptance enabled")
iRC.GetGuildFoundTradeStatus = statusCheck
TradeFrameTradeButton_Enable()
assert(TradeFrameTradeButton.active, "a failed recheck resets the recursion guard so later updates can recover")
-- Native mail refresh can enable Send after every edit. Typing must stay
-- quiet and never count incomplete roster names as blocked send attempts.
function SendMailFrame_CanSend()
    SendMailMailButton:SetEnabled(SendMailNameEditBox.text ~= "" and mailSubject ~= "")
end
function SendMailFrame_EnableSendMailButton() SendMailMailButton:SetEnabled(true) end
MailFrame = { OnEvent = function(_, event)
    if event == "MAIL_SUCCESS" or event == "MAIL_FAILED" then SendMailMailButton:SetEnabled(true) end
end }
enforcement:InstallMailAPIGuards()
priorNotices, priorAudits = #notices, #audits
local priorLookups = mailLookups
mailSubject = "Test"
for index = 1, #"Guildie" do
    SendMailNameEditBox:SetText(("Guildie"):sub(1, index))
    SendMailFrame_CanSend()
    assert(not SendMailMailButton.active, "Send stays disabled while the recipient is being typed")
end
assert(mailLookups == priorLookups and #notices == priorNotices and #audits == priorAudits,
    "typing does not query partial roster names, warn, or create mail audit events")
SendMailNameEditBox.hooks.OnTabPressed()
assert(SendMailMailButton.active and mailLookups > priorLookups, "Tab finalizes and verifies the full guild recipient")
SendMailNameEditBox.hooks.OnEditFocusGained()
assert(not SendMailMailButton.active, "editing a finalized name locks Send again")
SendMailNameEditBox.hooks.OnEnterPressed()
assert(SendMailMailButton.active, "Enter finalizes a valid full recipient")
mailSubject = ""; SendMailFrame_CanSend()
assert(not SendMailMailButton.active, "recipient verification cannot bypass Blizzard's missing-subject restriction")
mailSubject = "Test"; SendMailFrame_CanSend()
SendMailNameEditBox:SetText("Outside")
SendMailNameEditBox.hooks.OnEditFocusLost()
SendMailFrame_CanSend(); SendMailFrame_EnableSendMailButton()
MailFrame:OnEvent("MAIL_SUCCESS"); MailFrame:OnEvent("MAIL_FAILED")
assert(not SendMailMailButton.active and #notices == priorNotices and #audits == priorAudits,
    "a finalized non-guild name remains disabled without inventing a send attempt")
for _, edit in ipairs({ "subject", "body", "money", "attachment" }) do
    SendMailMailButton:SetEnabled(true)
    assert(not SendMailMailButton.active, edit .. " updates cannot directly enable Send for an unverified recipient")
    SendMailMailButton:Enable()
    assert(not SendMailMailButton.active, edit .. " updates cannot use Enable to bypass recipient verification")
end
assert(#notices == priorNotices and #audits == priorAudits,
    "editing a restricted draft does not create warning or audit spam")
local normalGuildMembership = iRC.IsGuildMemberName
iRC.IsGuildMemberName = function(_, name) return name == "Unverified Guildie" or name == "Guildie" end
SendMailNameEditBox:SetText("Unverified Guildie"); SendMailNameEditBox.hooks.OnEditFocusLost()
SendMailMailButton:Enable(); SendMailMailButton:SetEnabled(true)
assert(not SendMailMailButton.active, "guild membership alone never enables Send without verification")
iRC.IsGuildMemberName = normalGuildMembership
SendMailNameEditBox:SetText("Outside"); SendMailNameEditBox.hooks.OnEditFocusLost()
local normalMailStatus = iRC.GetGuildFoundTradeStatus
iRC.GetGuildFoundTradeStatus = function() error("verification unavailable") end
SendMailMailButton:Enable()
assert(not SendMailMailButton.active, "an unreadable verification disables Send without recursive hooks")
iRC.GetGuildFoundTradeStatus = normalMailStatus
SendMailNameEditBox:SetText("Guildie"); SendMailNameEditBox.hooks.OnEditFocusLost()
SendMailMailButton:Enable()
assert(SendMailMailButton.active, "the guard recovers when the verified recipient becomes readable again")
SendMailNameEditBox:SetText("Outside"); SendMailNameEditBox.hooks.OnEditFocusLost()

-- Success belongs to the submitted recipient, not a field subsequently reset
-- by Blizzard or changed by the player before the reply arrives.
SendMail("Outside")
assert(#audits == priorAudits + 1 and audits[#audits].action == "MAIL_BLOCKED",
    "an actual forbidden API send attempt, unlike typing, records the blocked-mail audit")
SendMailNameEditBox:SetText("")
eventFrame.OnEvent(nil, "MAIL_SEND_SUCCESS")
assert(discrepancies[#discrepancies] and discrepancies[#discrepancies].reason == "MAIL_BLOCK_BYPASS",
    "successful restricted sends retain their evidence when Blizzard resets the name first")
local priorDiscrepancies = #discrepancies
SendMailNameEditBox:SetText("Guildie"); SendMailNameEditBox.hooks.OnEditFocusLost()
SendMail("Guildie")
SendMailNameEditBox:SetText("Outside")
eventFrame.OnEvent(nil, "MAIL_SEND_SUCCESS")
assert(#discrepancies == priorDiscrepancies, "typing a new name cannot turn a successful allowed send into a bypass")
SendMail("Outside"); eventFrame.OnEvent(nil, "MAIL_FAILED")
eventFrame.OnEvent(nil, "MAIL_SEND_SUCCESS")
assert(#discrepancies == priorDiscrepancies, "a failed send cannot leave stale evidence for a later success")
SendMailNameEditBox:SetText("Guildie"); SendMailNameEditBox.hooks.OnEditFocusLost()
SendMail("Guildie")
MailFrame:OnEvent("MAIL_FAILED")
eventFrame.OnEvent(nil, "MAIL_FAILED")
assert(SendMailMailButton.active, "an eligible recipient can retry after a native send failure in either event order")
-- The outgoing exception never authorizes incoming mail or ordinary trades.
exceptionEnabled, outgoingMailEnabled = true, true
SendMailNameEditBox:SetText("Outside")
assert(not SendMailMailButton.active, "the exception still waits for the recipient to be finalized")
SendMailNameEditBox.hooks.OnEditFocusLost()
assert(SendMailMailButton.active, "an enabled exception allows a finalized external recipient")
SendMailMailButton:SetEnabled(true); SendMailMailButton:Enable()
assert(SendMailMailButton.active, "direct mail refreshes preserve an approved outgoing exception")
SendMailCODButton = { GetChecked = function() return true end }
SendMailMailButton:Enable()
assert(not SendMailMailButton.active, "selecting C.O.D. blocks external sends before the typed amount reaches GetSendMailCOD")
SendMailCODButton = nil
SendMailFrame_CanSend()
assert(SendMailMailButton.active, "switching back to outgoing mail restores the approved exception")
local exceptionAuditCount, exceptionDiscrepancies = #audits, #discrepancies
SendMail("Outside")
assert(#audits == exceptionAuditCount and not SendMailMailButton.active, "approval is recorded on success, not submission")
SendMailNameEditBox:SetText("")
eventFrame.OnEvent(nil, "MAIL_CLOSED")
eventFrame.OnEvent(nil, "MAIL_SEND_SUCCESS")
assert(#discrepancies == exceptionDiscrepancies and #audits == exceptionAuditCount + 1
    and audits[#audits].action == "MAIL_EXCEPTION_APPROVED" and audits[#audits].target == "Outside",
    "success keeps the submitted exception recipient even after the mailbox closes")
SendMail("Outside"); eventFrame.OnEvent(nil, "MAIL_FAILED")
eventFrame.OnEvent(nil, "MAIL_SEND_SUCCESS")
assert(#audits == exceptionAuditCount + 1, "failure clears a pending exception approval")
SendMailNameEditBox:SetText("Outside"); SendMailNameEditBox.hooks.OnEditFocusLost()
mailSubject = ""; SendMailFrame_CanSend()
assert(not SendMailMailButton.active, "the exception preserves native subject checks")
mailSubject = "Test"; SendMailFrame_CanSend()
mailCOD = 100; eventFrame.OnEvent(nil, "MAIL_SEND_INFO_UPDATE")
assert(not SendMailMailButton.active, "C.O.D. cannot turn an outgoing exception into external income")
local normalCOD = GetSendMailCOD
GetSendMailCOD = function() error("unavailable mail value") end
enforcement:UpdateMailRestriction()
assert(not SendMailMailButton.active, "an unavailable C.O.D. value cannot authorize an exception")
GetSendMailCOD = function() return nil end
enforcement:UpdateMailRestriction()
assert(not SendMailMailButton.active, "an unreadable C.O.D. value keeps the external send disabled")
GetSendMailCOD = normalCOD
mailCOD = 0; eventFrame.OnEvent(nil, "MAIL_SEND_INFO_UPDATE")
assert(SendMailMailButton.active, "removing C.O.D. restores the allowed outgoing send")
exceptionEnabled = false; enforcement:UpdateMailRestriction()
assert(not SendMailMailButton.active, "the saved exception has no effect while the master rule is off")
exceptionEnabled = true; outgoingMailEnabled = false; enforcement:UpdateMailRestriction()
assert(not SendMailMailButton.active, "turning the exception off restores verified-recipient restrictions")
outgoingMailEnabled = true
tradePartner, playerTradeLink = "Outside", nil
enforcement:UpdateTradeRestriction()
assert(not TradeFrameTradeButton.active, "the outgoing-mail exception does not authorize trades")
OpenMailFrame.openMailID = 1; enforcement:UpdateInboxRestriction()
assert(not OpenMailAttachmentButton1.active, "the outgoing-mail exception does not authorize external incoming attachments")
exceptionEnabled, outgoingMailEnabled = false, false

economyActive = false
SendMailNameEditBox:SetText("Outside"); SendMailFrame_CanSend()
assert(SendMailMailButton.active, "characters outside Guild Found keep Blizzard's normal send behavior")
economyActive = true

OpenMailFrame.openMailID = 1
enforcement:UpdateInboxRestriction()
assert(OpenMailMoneyButton.active == false and OpenMailPackageButton.active == false
    and OpenMailAttachmentButton1.active == false, "external player mail controls are disabled")
TakeInboxItem(1, 1)
assert(discrepancies[#discrepancies] and discrepancies[#discrepancies].reason == "INBOX_BLOCK_BYPASS",
    "calling a protected inbox API for restricted mail creates discrepancy evidence")

OpenMailFrame.openMailID = 2
enforcement:UpdateInboxRestriction()
assert(OpenMailMoneyButton.active == true and OpenMailPackageButton.active == true
    and OpenMailAttachmentButton1.active == true, "guild mail controls remain available")

assert(AcceptTrade ~= nil and SendMail ~= nil and TakeInboxItem ~= nil and TakeInboxMoney ~= nil
    and AutoLootMailItem ~= nil, "Blizzard economy APIs remain untouched")

for _, ordering in ipairs({ "refresh-before-hook", "refresh-after-hook" }) do
  for _, pickup in ipairs({ { TakeInboxItem, 5 }, { TakeInboxMoney, 2 }, { AutoLootMailItem, 5 } }) do
    local index = pickup[2]
    eventFrame.OnEvent(nil, "MAIL_CLOSED")
    completedInbox[index], completeOnTake[index] = nil, ordering
    OpenMailFrame.openMailID = index
    enforcement:UpdateInboxRestriction()
    assert(OpenMailAttachmentButton1.active, "verified guild attachments remain collectable")
    local beforeNotices, beforeAudits, beforeFlags = #notices, #audits, #discrepancies
    pickup[1](index, 1)
    eventFrame.OnEvent(nil, "MAIL_INBOX_UPDATE")
    assert(#notices == beforeNotices and #audits == beforeAudits and #discrepancies == beforeFlags,
        "the last authorized attachment becoming an empty header cannot warn, audit or flag the player: " .. ordering)
    assert(not OpenMailAttachmentButton1.active, "unavailable header data stays disabled during the transition")
  end
end
completedInbox[5], attachmentSender, OpenMailFrame.openMailID = nil, "Outside", 5
enforcement:UpdateInboxRestriction()
assert(not OpenMailAttachmentButton1.active and enforcement:IsInboxMailRestricted(5),
    "a new restricted mail reusing the same inbox slot cannot inherit the previous sender's approval")
attachmentSender = "Guildie"
eventFrame.OnEvent(nil, "MAIL_CLOSED")
OpenMailFrame.openMailID = 8
local beforeNotices, beforeAudits = #notices, #audits
enforcement:UpdateInboxRestriction()
assert(not OpenMailAttachmentButton1.active and #notices == beforeNotices and #audits == beforeAudits,
    "an empty pending header is blocked silently; numeric zero is not an attachment")
for _, index in ipairs({ 6, 7 }) do
    OpenMailFrame.openMailID = index
    enforcement:UpdateInboxRestriction()
    assert(enforcement:IsInboxMailRestricted(index) and not OpenMailAttachmentButton1.active,
        "unknown senders with actual money or attachments remain restricted")
end
eventFrame.OnEvent(nil, "MAIL_CLOSED")
OpenMailFrame.openMailID = 1
enforcement:UpdateInboxRestriction()
local beforeFlags = #discrepancies
completeOnTake[1] = "refresh-before-hook"
TakeInboxItem(1, 1)
assert(#discrepancies == beforeFlags + 1 and discrepancies[#discrepancies].reason == "INBOX_BLOCK_BYPASS",
    "a restricted-mail bypass still retains its evidence when the native header disappears before the post-hook")
beforeFlags = #discrepancies
economyActive = false
TakeInboxMoney(1)
assert(#discrepancies == beforeFlags, "old inbox evidence cannot enforce restrictions after Guild Found is paused")
economyActive = true
eventFrame.OnEvent(nil, "MAIL_CLOSED")
OpenMailFrame.openMailID = nil
InboxFrame = { OpenAllMail = control() }
function GetInboxNumItems() return 1 end
local inboxHeader = GetInboxHeaderInfo
GetInboxHeaderInfo = function() return nil, nil, nil, nil, 0, 0, nil, 0 end
beforeNotices, beforeAudits = #notices, #audits
enforcement:UpdateInboxRestriction()
assert(not InboxFrame.OpenAllMail.active and #notices == beforeNotices and #audits == beforeAudits,
    "Open All stays blocked without warnings while an inbox header is unavailable")
completedInbox[2] = nil
GetInboxHeaderInfo = function() return inboxHeader(2) end
enforcement:UpdateInboxRestriction()
assert(InboxFrame.OpenAllMail.active, "Open All becomes available once the actual verified sender returns")
GetInboxHeaderInfo = inboxHeader
print("PASS: completed guild-mail pickups stay quiet in either event order; pending mail stays disabled and real bypass evidence remains")
print("Guild Found economy enforcement tests passed.")
