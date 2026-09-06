-- Guild Found economy guards; no game, chat or network writes.
local accepted, sentMail, inboxItems, inboxMoney, autoLoot = 0, 0, 0, 0, 0
local tradePartner = "Outside"

UIParent = {}
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
    GetConnectionRules = function() return { selfFoundOnly = true, level60GuildFound = true } end,
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
assert(loadfile("iRacelockConnection_Enforcement.lua"))("iRacelockConnection", private)
local enforcement = assert(iRC.Enforcement)
enforcement:InstallTradeAPIGuard()
enforcement:InstallMailAPIGuards()

AcceptTrade()
assert(accepted == 0, "external trade acceptance is blocked")
assert(#notices == 1, "blocked trade explains the restriction in local chat")
tradePartner = "Guildie"
AcceptTrade()
assert(accepted == 1, "verified guild trade acceptance remains available")

SendMail("Outside", "Subject", "Body")
assert(#notices == 2, "blocked outgoing mail explains the restriction in local chat")
SendMail("Guildie", "Subject", "Body")
assert(sentMail == 1, "only verified guild outgoing mail reaches the game API")

TakeInboxItem(1, 1); TakeInboxMoney(1); AutoLootMailItem(1)
assert(inboxItems == 0 and inboxMoney == 0 and autoLoot == 0, "external player mail value is blocked")
assert(#notices == 5, "every blocked inbox collection explains the restriction in local chat")
TakeInboxMoney(2); TakeInboxItem(3, 1)
assert(inboxMoney == 1 and inboxItems == 1, "guild and game-generated mail remain collectible")
TakeInboxMoney(4)
assert(inboxMoney == 1, "Auction House proceeds are blocked")
assert(#notices == 6, "blocked Auction House mail explains the restriction in local chat")
print("Guild Found economy enforcement tests passed.")
