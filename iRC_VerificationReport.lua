local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local Report = {}
iRC.VerificationReport = Report
local GOLD, WHITE, GRAY = "|cffffcc66", "|cffffffff", "|cffaaaaaa"
local RED, GREEN, RESET = "|cffff7777", "|cff66dd88", "|r"
local REASONS = {
    MONEY_MISMATCH = "GF_REASON_MONEY_MISMATCH", SNAPSHOT_MISMATCH = "GF_REASON_SNAPSHOT_MISMATCH",
    PLAYED_GAP = "GF_REASON_PLAYED_GAP", PLAYED_ROLLBACK = "GF_REASON_PLAYED_ROLLBACK",
    TRADE_BLOCK_BYPASS = "GF_REASON_TRADE_BLOCK_BYPASS", TRADE_EXCEPTION_MONEY = "GF_REASON_TRADE_EXCEPTION_MONEY",
    INBOX_BLOCK_BYPASS = "GF_REASON_INBOX_BLOCK_BYPASS", MAIL_BLOCK_BYPASS = "GF_REASON_MAIL_BLOCK_BYPASS",
}
local function reason(code)
    return iRC:Text(REASONS[code] or "GF_REASON_LEGACY")
end
local function stamp(value)
    value = tonumber(value) or 0
    return value > 0 and date("%Y-%m-%d %H:%M:%S", value) or iRC:Text("RL_STATUS_UNKNOWN")
end
local function duration(value)
    value = math.max(0, math.floor(tonumber(value) or 0))
    return string.format("%dh %dm %ds", math.floor(value / 3600), math.floor(value % 3600 / 60), value % 60)
end
local function money(value)
    value = math.max(0, math.floor(tonumber(value) or 0))
    return iRC:Text("GF_REPORT_MONEY_FORMAT", math.floor(value / 10000), math.floor(value % 10000 / 100), value % 100)
end
local function word(value, yes, no)
    if value == nil then return GRAY .. iRC:Text("RL_STATUS_UNKNOWN") .. RESET end
    return (value and GREEN or RED) .. iRC:Text(value and yes or no) .. RESET
end
local function highlightedName(name)
    return GOLD .. iRC:FormatPlayerName(name or iRC:Text("RL_STATUS_UNKNOWN")) .. RESET
end
local function hasMixedEvidence(status)
    -- Older clients retained an earlier delta when recording a new incident.
    -- Do not pass that old money sample off as evidence for the newer reason.
    local afterAt, detectedAt = tonumber(status.moneyAfterAt), tonumber(status.tamperAt)
    return afterAt and detectedAt and afterAt > 0 and math.min(detectedAt, time()) - afterAt > 5
end

function Report:BuildModel(name, member, status, progression)
    member = member or {}
    local selfFoundReport = (tonumber(member.level) or 0) < 60 and progression == "SELF_FOUND"
    local hasIssue = status and (tonumber(status.tamperAt) or 0) > 0
    local needsReview = status and (status.clean == false or status.cleanDecisionSuperseded == true)
    local model = {
        name = iRC:FormatPlayerName(name),
        title = iRC:Text(selfFoundReport and "SF_REPORT_TITLE" or "GF_REPORT_TITLE"),
        tone = needsReview and "danger" or status and status.clean == true and "clean" or "neutral",
        badge = iRC:Text(needsReview and "GF_REPORT_REVIEW_REQUIRED"
            or hasIssue and status.clean == true and "GF_REPORT_REVIEWED_CLEAN"
            or status and status.clean == true and "RL_CLEAN" or "RL_STATUS_UNKNOWN"),
        issueLabel = iRC:Text(hasIssue and (needsReview and "GF_REPORT_CURRENT_ISSUE" or "GF_REPORT_LAST_ISSUE")
            or "GF_REPORT_MONITORING"),
        issue = hasIssue and reason(status.discrepancyReason)
            or iRC:Text(status and (needsReview and "GF_REPORT_MANUAL_FLAG" or "GF_REPORT_NO_ISSUE") or "GF_REPORT_WAITING"),
    }
    model.summary = selfFoundReport and iRC:Text("GF_REPORT_SELF_FOUND",
        not iRC:IsLiveAddonState(member.verification and member.verification.state) and iRC:Text("GF_SELF_FOUND_UNKNOWN")
            or iRC:Text(member.selfFound and "GF_SELF_FOUND_ACTIVE" or "GF_SELF_FOUND_INACTIVE"))
        or status and iRC:Text("GF_REPORT_EFFECTIVE_VERIFIED", word(status.verified, "RL_VERIFIED", "RL_UNVERIFIED")) or ""
    if status then
        model.summary = model.summary .. "    |    " .. iRC:Text("GF_REPORT_EFFECTIVE_CLEAN", word(status.clean, "RL_CLEAN", "RL_FLAGGED"))
    end
    model.issueDetail = hasIssue and iRC:Text("GF_REPORT_DISCREPANCY", stamp(status.tamperAt)) or ""
    if hasIssue and status.discrepancyReason == "TRADE_BLOCK_BYPASS" then
        model.issueDetail = model.issueDetail .. "\n" .. iRC:Text("GF_REPORT_ACCEPTANCE_ONLY")
    end
    local lines = {}
    local function section(key)
        if #lines > 0 then lines[#lines + 1] = "" end
        lines[#lines + 1] = GOLD .. iRC:Text(key) .. RESET
    end
    local function moneyLine(evidence)
        return iRC:Text("GF_REPORT_BALANCES", money(evidence.moneyBefore), money(evidence.moneyAfter),
            (evidence.moneyAfter > evidence.moneyBefore and "+" or evidence.moneyAfter < evidence.moneyBefore and "-" or "")
                .. money(math.abs(evidence.moneyAfter - evidence.moneyBefore)))
    end
    if hasIssue then
        section("GF_REPORT_ISSUE_MONEY")
        if not hasMixedEvidence(status) and status.moneyBefore ~= nil and status.moneyAfter ~= nil then
            lines[#lines + 1] = WHITE .. moneyLine(status) .. RESET
            lines[#lines + 1] = GRAY .. iRC:Text("GF_REPORT_SAMPLES", stamp(status.moneyBeforeAt), stamp(status.moneyAfterAt)) .. RESET
            if status.moneyBeforeAt and status.moneyAfterAt then
                lines[#lines + 1] = iRC:Text("GF_REPORT_TIME_DIFF", duration(status.moneyAfterAt - status.moneyBeforeAt))
            end
            if status.playedBefore and status.playedAfter and status.playedAfter >= status.playedBefore then
                lines[#lines + 1] = iRC:Text("GF_REPORT_PLAYED_INCREASE", duration(status.playedAfter - status.playedBefore))
            end
        else
            lines[#lines + 1] = GRAY .. iRC:Text("GF_REPORT_ISSUE_MONEY_UNAVAILABLE") .. RESET
        end
    end
    if status then
        section("GF_REPORT_REVIEW_SECTION")
        if status.gmTimestamp then
            local verified = status.gmVerified == nil and iRC:Text("RL_OVERRIDE_RESET") or word(status.gmVerified, "RL_VERIFIED", "RL_UNVERIFIED")
            local clean = status.gmClean == nil and iRC:Text("RL_OVERRIDE_RESET") or word(status.gmClean, "RL_CLEAN", "RL_FLAGGED")
            lines[#lines + 1] = iRC:Text("GF_REPORT_DECISION_VALUES", verified, clean)
            lines[#lines + 1] = iRC:Text("GF_REPORT_DECISION_SOURCE", highlightedName(status.overrideSource), stamp(status.gmTimestamp))
            if status.cleanDecisionSuperseded then lines[#lines + 1] = RED .. iRC:Text("GF_REPORT_DECISION_SUPERSEDED") .. RESET end
        else lines[#lines + 1] = GRAY .. iRC:Text("GF_REPORT_NO_REVIEW") .. RESET end
        section("GF_REPORT_MEMBER_SECTION")
        if not selfFoundReport then lines[#lines + 1] = iRC:Text("GF_REPORT_RAW_VERIFIED", word(status.rawVerified, "GF_HISTORY_VERIFIED", "GF_HISTORY_UNVERIFIED")) end
        lines[#lines + 1] = iRC:Text("GF_REPORT_RAW_CLEAN", word(status.rawClean, "GF_GOLD_CLEAN", "GF_GOLD_FLAGGED"))
        local records = status.previousDiscrepancies or {}
        if #records > 0 or hasMixedEvidence(status) then
            section("GF_REPORT_EARLIER_SECTION")
            if hasMixedEvidence(status) and status.moneyBefore ~= nil and status.moneyAfter ~= nil then
                lines[#lines + 1] = iRC:Text("GF_REPORT_OLDER_SAMPLE", stamp(status.moneyAfterAt))
                lines[#lines + 1] = GRAY .. moneyLine(status) .. RESET
            end
            for index = #records, math.max(1, #records - 4), -1 do
                local record = records[index]
                lines[#lines + 1] = stamp(record.tamperAt) .. "  -  " .. reason(record.discrepancyReason)
                if record.moneyBefore ~= nil and record.moneyAfter ~= nil then
                    lines[#lines + 1] = GRAY .. (hasMixedEvidence(record) and iRC:Text("GF_REPORT_OLDER_SAMPLE", stamp(record.moneyAfterAt)) .. "\n" or "") .. moneyLine(record) .. RESET
                end
            end
        end
    end
    section("GF_REPORT_INFO_SECTION")
    lines[#lines + 1] = iRC:Text("GF_REPORT_SOURCE", status and status.source or member.source or iRC:Text("RL_STATUS_UNKNOWN"))
    lines[#lines + 1] = iRC:Text("GF_REPORT_RECEIVED", stamp(status and status.lastSeen))
    model.details = table.concat(lines, "\n")
    return model
end

function Report:Create(parent)
    local frame = CreateFrame("Frame", "iRCGuildFoundReportFrame", parent, "BackdropTemplate")
    frame:SetSize(720, 570)
    frame:SetPoint("CENTER", parent, "CENTER", 0, 0)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
    frame:SetBackdropColor(0.018, 0.015, 0.012, 0.99)
    frame:SetBackdropBorderColor(0.8, 0.5, 0.16, 1)
    local function text(parentFrame, template, x, y)
        local label = parentFrame:CreateFontString(nil, "OVERLAY", template)
        label:SetPoint("TOPLEFT", x, y)
        label:SetPoint("TOPRIGHT", -x, y)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(true)
        return label
    end
    frame.title = text(frame, "GameFontNormal", 20, -17)
    frame.memberName = text(frame, "GameFontNormalHuge", 20, -42)
    frame.memberName:SetTextColor(1, 0.82, 0.4)
    frame.summary = text(frame, "GameFontHighlight", 20, -74)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 3, 3)
    frame.issue = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.issue:SetPoint("TOPLEFT", 18, -103)
    frame.issue:SetPoint("TOPRIGHT", -18, -103)
    frame.issue:SetHeight(125)
    frame.issue:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 1 })
    frame.issueLabel = text(frame.issue, "GameFontNormalSmall", 14, -12)
    frame.issueHeading = text(frame.issue, "GameFontNormalLarge", 14, -32)
    frame.issueDetail = text(frame.issue, "GameFontHighlightSmall", 14, -77)
    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", 22, -243)
    frame.scroll:SetPoint("BOTTOMRIGHT", -40, 20)
    frame.content = CreateFrame("Frame", nil, frame.scroll)
    frame.scroll:SetScrollChild(frame.content)
    frame.body = text(frame.content, "GameFontHighlight", 0, 0)
    frame.body:SetSpacing(4)
    frame:Hide()
    return frame
end

function Report:Show(frame, name, member, status, progression)
    local model = self:BuildModel(name, member, status, progression)
    local height = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 768
    frame:SetHeight(math.max(380, math.min(570, height - 60)))
    frame.title:SetText(model.title)
    frame.memberName:SetText(model.name)
    frame.summary:SetText(model.summary)
    local color = model.tone == "danger" and { 1, 0.35, 0.3 } or model.tone == "clean" and { 0.4, 0.85, 0.5 } or { 1, 0.75, 0.3 }
    frame.issue:SetBackdropColor(color[1] * 0.07, color[2] * 0.07, color[3] * 0.07, 1)
    frame.issue:SetBackdropBorderColor(color[1], color[2], color[3], 0.8)
    frame.issueLabel:SetText(model.issueLabel .. "  |  " .. model.badge)
    frame.issueLabel:SetTextColor(unpack(color))
    frame.issueHeading:SetText(model.issue)
    frame.issueHeading:SetTextColor(unpack(color))
    frame.issueDetail:SetText(model.issueDetail)
    frame.content:SetWidth(frame:GetWidth() - 64)
    frame.body:SetText(model.details)
    frame.content:SetHeight(math.max(1, frame.body:GetStringHeight() + 16))
    frame.scroll:SetVerticalScroll(0)
    frame:Show()
    frame:Raise()
end
