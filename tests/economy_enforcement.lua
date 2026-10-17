-- Guild Found economy guards; no game, chat or network writes.
local accepted, sentMail, inboxItems, inboxMoney, autoLoot = 0, 0, 0, 0, 0
local tradePartner = "Outside"
local tradeOpen, exceptionEnabled, playerTradeLink = true, false, nil
local audits, discrepancies, frames = {}, {}, {}

local function control()
    return { enabled = true, SetEnabled = function(self, value) self.enabled = value and true or false end }
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
function GetPlayerTradeMoney() return 0 end
function GetTargetTradeMoney() return 0 end
function GetTradePlayerItemLink(slot) if slot == 1 then return playerTradeLink end end
function GetTradeTargetItemLink() end
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
assert(TradeFrameTradeButton.enabled == false, "external trade acceptance control is disabled")
assert(#notices == 1, "blocked trade explains the restriction in local chat")
eventFrame.OnEvent(nil, "TRADE_ACCEPT_UPDATE", 1, 0)
assert(discrepancies[#discrepancies] and discrepancies[#discrepancies].reason == "TRADE_BLOCK_BYPASS",
    "acceptance of a restricted trade creates monitoring discrepancy evidence")
eventFrame.OnEvent(nil, "TRADE_CLOSED")
tradePartner = "Guildie"
enforcement:UpdateTradeRestriction()
assert(TradeFrameTradeButton.enabled == true, "verified guild trade acceptance remains available")

tradePartner, exceptionEnabled, playerTradeLink = "Outside", true, "|Hitem:5350:0:0:0|h[Conjured Water]|h"
enforcement:UpdateTradeRestriction()
assert(TradeFrameTradeButton.enabled == true and TradeFrameTradeButton.iRCApprovedException,
    "an explicitly selected external exception item enables trade acceptance")
assert(enforcement:RecordApprovedTradeException(1), "accepting an external exception records its approval")
assert(#audits >= 1 and audits[#audits].action == "TRADE_EXCEPTION_APPROVED"
    and audits[#audits].target:find("Outside", 1, true), "approved exception audit identifies the partner")
assert(not enforcement:RecordApprovedTradeException(1), "the same trade approval is audited only once")
tradePartner, exceptionEnabled, playerTradeLink = "Guildie", false, nil

SendMailNameEditBox.text = "Outside"
enforcement:UpdateMailRestriction()
assert(SendMailMailButton.enabled == false, "external outgoing mail control is disabled")
assert(#notices == 2, "blocked outgoing mail explains the restriction in local chat")
SendMailNameEditBox.text = "Guildie"
enforcement:UpdateMailRestriction()
assert(SendMailMailButton.enabled == true, "verified guild outgoing mail remains available")

SendMailNameEditBox.text = "Outside"
enforcement:UpdateMailRestriction()
eventFrame.OnEvent(nil, "MAIL_SEND_SUCCESS")
assert(discrepancies[#discrepancies] and discrepancies[#discrepancies].reason == "MAIL_BLOCK_BYPASS",
    "a successful send to a blocked recipient creates monitoring discrepancy evidence")

OpenMailFrame.openMailID = 1
enforcement:UpdateInboxRestriction()
assert(OpenMailMoneyButton.enabled == false and OpenMailPackageButton.enabled == false
    and OpenMailAttachmentButton1.enabled == false, "external player mail controls are disabled")
TakeInboxItem(1, 1)
assert(discrepancies[#discrepancies] and discrepancies[#discrepancies].reason == "INBOX_BLOCK_BYPASS",
    "calling a protected inbox API for restricted mail creates discrepancy evidence")

OpenMailFrame.openMailID = 2
enforcement:UpdateInboxRestriction()
assert(OpenMailMoneyButton.enabled == true and OpenMailPackageButton.enabled == true
    and OpenMailAttachmentButton1.enabled == true, "guild mail controls remain available")

assert(AcceptTrade ~= nil and SendMail ~= nil and TakeInboxItem ~= nil and TakeInboxMoney ~= nil
    and AutoLootMailItem ~= nil, "Blizzard economy APIs remain untouched")
print("Guild Found economy enforcement tests passed.")
