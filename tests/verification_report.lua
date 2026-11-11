-- Test current/previous issue presentation and the real report frame binding.
unpack, date = table.unpack, os.date
function time() return 1800000100 end
function GetCoinTextureString(value) return tostring(value) .. "c" end
local addon = {
    Colors = setmetatable({}, { __index = function() return "" end }),
    FormatPlayerName = function(_, name) return name end,
    IsLiveAddonState = function(_, state) return state == "verified" end,
    Text = function(self, key, ...)
        local format = assert(self.L[key], "Missing report text: " .. key)
        return select("#", ...) > 0 and string.format(format, ...) or format
    end,
}
local private = { iRC = addon }
assert(loadfile("Localization/enUS.lua"))("iRC", private)
assert(loadfile("iRC_VerificationReport.lua"))("iRC", private)
local report = addon.VerificationReport
local member = { level = 15, verification = { state = "verified" }, selfFound = true }
local status = {
    tamperAt = 1800000100, clean = false, verified = true, rawVerified = false, rawClean = false,
    moneyBefore = 10, moneyAfter = 10, moneyBeforeAt = 1800000090, moneyAfterAt = 1800000100,
    discrepancyReason = "TRADE_BLOCK_BYPASS", gmTimestamp = 1800000050,
    gmVerified = true, gmClean = true, overrideSource = "Guild Master", cleanDecisionSuperseded = true,
    previousDiscrepancies = { { tamperAt = 1800000000, discrepancyReason = "MONEY_MISMATCH",
        moneyBefore = 0, moneyAfter = 6, moneyBeforeAt = 1799999985, moneyAfterAt = 1800000000 } },
}
local model = report:BuildModel("Crasling Vaelanar", member, status, "GUILD_FOUND")
assert(model.name == "Crasling Vaelanar" and model.tone == "danger" and model.badge == "REVIEW REQUIRED")
assert(model.issue:find("local acceptance", 1, true) and model.issueDetail:find("does not confirm", 1, true),
    "the main issue describes acceptance without claiming a completed transfer")
assert(model.details:find("Before: 0g 0s 10c    |    After: 0g 0s 10c    |    Change: 0g 0s 0c", 1, true))
local earlier = assert(model.details:find("Earlier records on this client", 1, true))
assert(model.details:find("Before: 0g 0s 0c", 1, true) > earlier, "the older zero balance is only shown under earlier records")
assert(model.details:find("|cffffcc66Guild Master|r", 1, true), "reviewer names are highlighted")
status.clean, status.cleanDecisionSuperseded, status.gmTimestamp = true, false, 1800000101
model = report:BuildModel("Crasling Vaelanar", member, status, "GUILD_FOUND")
assert(model.tone == "clean" and model.badge == "REVIEWED - CLEAN" and model.issueLabel == "LAST RECORDED ISSUE",
    "a reviewed clean discrepancy must not still appear as a current warning")
status.moneyBefore, status.moneyAfter, status.moneyAfterAt = 0, 6, 1799999000
model = report:BuildModel("Crasling Vaelanar", member, status, "GUILD_FOUND")
assert(model.details:find("No money snapshot is available for this issue.", 1, true),
    "already-mixed legacy evidence is not presented as the current incident's balance")
assert(model.details:find("Earlier money snapshot", 1, true), "legacy money samples remain available separately")
status.moneyBefore, status.moneyAfter, status.moneyAfterAt = 10, 10, 1800000100
status.tamperAt = 1800000115
model = report:BuildModel("Crasling Vaelanar", member, status, "GUILD_FOUND")
assert(model.details:find("Before: 0g 0s 10c", 1, true), "monotonic incident IDs ahead of wall time do not hide valid samples")
status.moneyBefore, status.moneyAfter = 5585, 11188
status.moneyBeforeAt = status.moneyAfterAt - (1148 * 60 + 43)
status.playedBefore, status.playedAfter = 1000, 1000 + 196 * 60 + 36
model = report:BuildModel("Drim Lumenrot", member, status, "GUILD_FOUND")
assert(model.details:find("Before: 0g 55s 85c    |    After: 1g 11s 88c    |    Change: +0g 56s 3c", 1, true))
assert(not model.details:find("Played-time check", 1, true),
    "a trade incident must not present an unrelated periodic played-time sample as its own evidence")
status.discrepancyReason = "PLAYED_GAP"
model = report:BuildModel("Drim Lumenrot", member, status, "GUILD_FOUND")
assert(model.details:find("3h 16m 36s", 1, true), "played-time incidents retain their actual played-time change")
assert(model.details:find("Played-time check", 1, true) < model.details:find("Wallet at detection (not the cause)", 1, true),
    "played-time evidence comes first and the unchanged wallet is labeled as context")
assert(not model.details:find("Difference in time:", 1, true) and not model.details:find("19h 8m 43s", 1, true),
    "elapsed clock time, which includes time logged out, is not presented as audit activity")
assert(model.details:find(os.date("%Y-%m-%d %H:%M:%S", status.moneyBeforeAt), 1, true),
    "the original checkpoint timestamps remain available")
status.moneyBeforeAt = status.moneyAfterAt - 9
status.playedBeforeAt, status.playedAfterAt = status.moneyAfterAt - 30 * 60, status.moneyAfterAt
status.playedAfter = status.playedBefore + 29 * 60 + 59
model = report:BuildModel("Drim Lumenrot", member, status, "GUILD_FOUND")
assert(model.details:find("Played time gained since the earlier check: 0h 29m 59s", 1, true))
assert(model.details:find(os.date("%Y-%m-%d %H:%M:%S", status.playedBeforeAt), 1, true)
    and model.details:find(os.date("%Y-%m-%d %H:%M:%S", status.playedAfterAt), 1, true),
    "played-time evidence shows its own dates instead of implying it spans the nine-second money check")
status.discrepancyReason, status.playedAfter = "PLAYED_ROLLBACK", status.playedBefore - 5
model = report:BuildModel("Drim Lumenrot", member, status, "GUILD_FOUND")
assert(model.details:find("Played time dropped since the earlier check: 0h 0m 5s", 1, true),
    "a backwards played-time sample remains visible")
status.discrepancyReason = "TRADE_BLOCK_BYPASS"
model = report:BuildModel("Crasling Vaelanar", member, nil, "GUILD_FOUND")
assert(model.tone == "neutral" and model.issue:find("No verification report", 1, true))
model = report:BuildModel("Crasling Vaelanar", member, status, "SELF_FOUND")
assert(model.title == addon.L.SF_REPORT_TITLE and model.summary:find(addon.L.GF_SELF_FOUND_ACTIVE, 1, true))

local methods = {}
local function widget(parent)
    return setmetatable({ parent = parent }, { __index = function(_, key)
        return methods[key] or (key:match("^Set") and function() end)
    end })
end
function CreateFrame(_, _, parent) return widget(parent) end
function methods:CreateFontString() return widget(self) end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:EnableMouse(value) self.mouseEnabled = value end
function methods:SetWidth(width) self.width = width end
function methods:SetHeight(height) self.height = height end
function methods:GetWidth() return self.width or self.parent:GetWidth() end
function methods:GetHeight() return self.height or 768 end
function methods:SetText(text) self.text = text end
function methods:GetStringHeight() local _, breaks = self.text:gsub("\n", ""); return (breaks + 1) * 18 end
function methods:SetScrollChild(child) self.child = child end
function methods:SetVerticalScroll(value) self.scroll = value end
function methods:Hide() self.shown = false end
function methods:Show() self.shown = true end
function methods:Raise() end
UIParent = widget()
local frame = report:Create(UIParent)
assert(frame.mouseEnabled == true, "the report consumes clicks and hover instead of exposing controls underneath")
report:Show(frame, "Crasling Vaelanar", member, status, "GUILD_FOUND")
assert(frame.memberName.text == "Crasling Vaelanar" and frame.issueHeading.text:find("local acceptance", 1, true))
assert(frame.content.height > 300 and frame.scroll.child == frame.content and frame.scroll.scroll == 0,
    "long reports use a scrollable detail area instead of clipping")
report:Show(frame, "Another Member", member, nil, "GUILD_FOUND")
assert(frame.memberName.text == "Another Member" and not frame.body.text:find("Before: 0g 55s 85c", 1, true),
    "reopening the report for another member clears prior evidence")
print("Verification report tests passed: issue focus, names, review states, separate history, legacy evidence, and scrollable details.")
