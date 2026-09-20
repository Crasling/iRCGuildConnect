-- Guild Found economy guards; no game, chat or network writes.
local accepted, sentMail, inboxItems, inboxMoney, autoLoot = 0, 0, 0, 0, 0
local tradePartner = "Outside"

local function control()
    return { enabled = true, SetEnabled = function(self, value) self.enabled = value and true or false end }
end

UIParent = {}
TradeFrameTradeButton = control()
SendMailMailButton = control()
SendMailNameEditBox = { text = "", GetText = function(self) return self.text end, HookScript = function(self, _, callback) self.onTextChanged = callback end }
OpenMailFrame = {}
OpenMailMoneyButton = control()
OpenMailPackageButton = control()
OpenMailAttachmentButton1 = control()
ATTACHMENTS_MAX_RECEIVE = 1
function UnitLevel() return 60 end
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
    return frame
end
function GetUnitName(unit) if unit == "NPC" then return tradePartner end end
function AcceptTrade() accepted = accepted + 1 end
function SendMail() sentMail = sentMail + 1 end
function TakeInboxItem() inboxItems = inboxItems + 1 end
function TakeInboxMoney() inboxMoney = inboxMoney + 1 end
function AutoLootMailItem() autoLoot = autoLoot + 1 end
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
    GetProgressionMode = function() return "GUILD_FOUND" end,
    IsGuildBankException = function() return false end,
    IsGuildMemberName = function(_, name) return name == "Guildie" end,
    GetConnectionRules = function() return { guildFoundOnly = true, guildFoundTradeExceptions = false } end,
    GetGuildFoundTradeExceptionSettings = function() return { items = {} } end,
    GetSelfFoundState = function() return false end,
    GetGuildFoundTradeStatus = function(_, name) return name == "Guildie", name == "Guildie" and nil or "outside guild" end,
    FindConnectionProfile = function() end,
    NormalizeName = function(_, name) return string.lower(name or "") end,
    Text = function(_, key, ...)
        local values = { ... }
        for index, value in ipairs(values) do values[index] = tostring(value) end
        return #values > 0 and key .. " " .. table.concat(values, " ") or key
    end,
    Print = function(_, message) notices[#notices + 1] = message end,
    RecordSelfFoundState = function() end,
}
local private = { iRC = iRC }
assert(loadfile("iRC_Enforcement.lua"))("iRC", private)
local enforcement = assert(iRC.Enforcement)
enforcement:InstallMailAPIGuards()

enforcement:UpdateTradeRestriction()
assert(TradeFrameTradeButton.enabled == false, "external trade acceptance control is disabled")
assert(#notices == 1, "blocked trade explains the restriction in local chat")
tradePartner = "Guildie"
enforcement:UpdateTradeRestriction()
assert(TradeFrameTradeButton.enabled == true, "verified guild trade acceptance remains available")

SendMailNameEditBox.text = "Outside"
enforcement:UpdateMailRestriction()
assert(SendMailMailButton.enabled == false, "external outgoing mail control is disabled")
assert(#notices == 2, "blocked outgoing mail explains the restriction in local chat")
SendMailNameEditBox.text = "Guildie"
enforcement:UpdateMailRestriction()
assert(SendMailMailButton.enabled == true, "verified guild outgoing mail remains available")

OpenMailFrame.openMailID = 1
enforcement:UpdateInboxRestriction()
assert(OpenMailMoneyButton.enabled == false and OpenMailPackageButton.enabled == false
    and OpenMailAttachmentButton1.enabled == false, "external player mail controls are disabled")

OpenMailFrame.openMailID = 2
enforcement:UpdateInboxRestriction()
assert(OpenMailMoneyButton.enabled == true and OpenMailPackageButton.enabled == true
    and OpenMailAttachmentButton1.enabled == true, "guild mail controls remain available")

assert(AcceptTrade ~= nil and SendMail ~= nil and TakeInboxItem ~= nil and TakeInboxMoney ~= nil
    and AutoLootMailItem ~= nil, "Blizzard economy APIs remain untouched")
print("Guild Found economy enforcement tests passed.")
