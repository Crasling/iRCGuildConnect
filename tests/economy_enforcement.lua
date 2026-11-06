-- Guild Found economy guards; no game, chat or network writes.
local accepted, sentMail, inboxItems, inboxMoney, autoLoot = 0, 0, 0, 0, 0
local tradePartner = "Outside"
local tradeOpen, exceptionEnabled, playerTradeLink = true, false, nil
local targetTradeLink, playerOffer, targetOffer, typedOffer = nil, 0, 0, 0
local audits, discrepancies, frames = {}, {}, {}

local function control()
    return { active = true, SetEnabled = function(self, value) self.active = value and true or false end }
end

UIParent = {}
TradeFrame = { IsShown = function() return tradeOpen end }
TradeFrameTradeButton = control()
SendMailMailButton = control()
SendMailNameEditBox = { text = "", GetText = function(self) return self.text end, HookScript = function(self, _, callback) self.onTextChanged = callback end }
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
function TakeInboxItem() inboxItems = inboxItems + 1 end
function TakeInboxMoney() inboxMoney = inboxMoney + 1 end
function AutoLootMailItem() autoLoot = autoLoot + 1 end
function hooksecurefunc(name, callback)
    local original = _G[name]
    _G[name] = function(...)
        local values = { original(...) }
        callback(...)
        return (table.unpack or unpack)(values)
    end
end
function GetInboxHeaderInfo(index)
    if index == 1 then return 1, nil, "Outside", nil, 0, 0, nil, true, nil, nil, nil, true, false end
    if index == 2 then return 1, nil, "Guildie", nil, 100, 0, nil, false, nil, nil, nil, true, false end
    if index == 3 then return 1, nil, "Quest NPC", nil, 0, 0, nil, true, nil, nil, nil, false, false end
    return 134939, nil, "Auction House", nil, 100, 0, nil, false, nil, nil, nil, false, false
end
function GetInboxInvoiceInfo(index) if index == 4 then return "seller" end end

local notices = {}
local iRC = {
    Colors = { Red = "", Reset = "", Yellow = "" },
    IsGuildConnectionActive = function() return true end,
    IsGuildFoundRequired = function() return true end,
    IsGuildFoundEconomyActive = function() return true end,
    GetProgressionMode = function() return "GUILD_FOUND" end,
    IsGuildMemberName = function(_, name) return name == "Guildie" end,
    GetConnectionRules = function() return { guildFoundOnly = true, guildFoundTradeExceptions = exceptionEnabled } end,
    GetGuildFoundTradeExceptionSettings = function()
        return { conjured = exceptionEnabled, items = { conjured = { [5350] = exceptionEnabled } } }
    end,
    GetSelfFoundState = function() return false end,
    GetGuildFoundTradeStatus = function(_, name) return name == "Guildie", name == "Guildie" and nil or "outside guild" end,
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
local eventFrame = frames[#frames]
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
priorNotices = #notices

SendMailNameEditBox.text = "Outside"
enforcement:UpdateMailRestriction()
assert(SendMailMailButton.active == false, "external outgoing mail control is disabled")
assert(#notices == priorNotices + 1, "blocked outgoing mail explains the restriction in local chat")
SendMailNameEditBox.text = "Guildie"
enforcement:UpdateMailRestriction()
assert(SendMailMailButton.active == true, "verified guild outgoing mail remains available")

SendMailNameEditBox.text = "Outside"
enforcement:UpdateMailRestriction()
eventFrame.OnEvent(nil, "MAIL_SEND_SUCCESS")
assert(discrepancies[#discrepancies] and discrepancies[#discrepancies].reason == "MAIL_BLOCK_BYPASS",
    "a successful send to a blocked recipient creates monitoring discrepancy evidence")

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
print("Guild Found economy enforcement tests passed.")
