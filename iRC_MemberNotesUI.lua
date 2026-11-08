local _, private = ...
local iRC = private and private.iRC
if not iRC or not iRC.MemberNotes then return end
local Notes, UI = iRC.MemberNotes, {}
Notes.UI = UI
local GOLD, RED, GRAY = {1, 0.66, 0.16}, {1, 0.3, 0.22}, {0.65, 0.65, 0.65}
local BACKDROP = { bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 1 }

local function plain(value)
    return (tostring(value or ""):gsub("|", "||"))
end

local function memberName(value)
    return iRC:FormatInviteContactName(value or "")
end

local function surface(frame, strong)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(0.025, 0.022, 0.018, 0.99)
    frame:SetBackdropBorderColor(strong and 0.66 or 0.30, strong and 0.43 or 0.24, 0.12, 1)
end

local function label(parent, value, x, y, font)
    local result = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    result:SetPoint("TOPLEFT", x, y)
    result:SetJustifyH("LEFT")
    result:SetText(value)
    return result
end

local function button(parent, value, width, callback)
    local result = CreateFrame("Button", nil, parent, "BackdropTemplate")
    result:SetSize(width, 26)
    surface(result)
    result.text = label(result, value, 0, 0)
    result.text:ClearAllPoints()
    result.text:SetPoint("CENTER")
    result.text:SetTextColor(unpack(GOLD))
    result:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    result:SetScript("OnClick", callback)
    result:HookScript("OnEnable", function(self) self:SetAlpha(1) end)
    result:HookScript("OnDisable", function(self) self:SetAlpha(0.4) end)
    return result
end

local function setupTextInput(result)
    result:SetAutoFocus(false)
    result:EnableMouse(true)
    result:EnableKeyboard(true)
    result:SetFontObject(ChatFontNormal)
    result:SetTextColor(1, 1, 1, 1)
    result:SetBlinkSpeed(0.5)
    result:HookScript("OnMouseDown", function(self) if self:IsEnabled() then self:SetFocus() end end)
    result:HookScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(unpack(GOLD)) end)
    result:HookScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(0.30, 0.24, 0.12, 1) end)
    result:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
end

local function input(parent, width, maximum)
    local result = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    result:SetSize(width, 26)
    surface(result)
    setupTextInput(result)
    result:SetTextInsets(7, 7, 0, 0)
    result:SetMaxLetters(maximum)
    if result.SetMaxBytes then result:SetMaxBytes(maximum) end
    result:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return result
end

local function suggestionMenu(parent, edit, choose)
    local menu = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    menu:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", 0, -2)
    menu:SetPoint("TOPRIGHT", edit, "BOTTOMRIGHT", 0, -2)
    menu:SetHeight(127)
    menu:SetFrameLevel(parent:GetFrameLevel() + 25)
    menu:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    menu:SetBackdropColor(0.03, 0.03, 0.03, 0.98)
    menu:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.85)
    menu.buttons = {}
    for index = 1, 5 do
        local option = CreateFrame("Button", nil, menu)
        option:SetHeight(23)
        option:SetPoint("TOPLEFT", 7, -6 - (index - 1) * 23)
        option:SetPoint("TOPRIGHT", -7, -6 - (index - 1) * 23)
        option.text = label(option, "", 7, 0)
        option.text:ClearAllPoints()
        option.text:SetPoint("LEFT", 7, 0)
        option.text:SetPoint("RIGHT", -7, 0)
        option.text:SetWordWrap(false)
        option.highlight = option:CreateTexture(nil, "HIGHLIGHT")
        option.highlight:SetAllPoints()
        option.highlight:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.18)
        option:SetScript("OnClick", choose)
        menu.buttons[index] = option
    end
    menu:Hide()
    return menu
end

-- Both notes searches suggest member names and note titles. Typing still
-- searches freely; choosing a suggestion just fills the existing search box.
function UI:AttachSearchSuggestions(edit, parent, active, onChoose)
    if edit.noteSuggestions then return edit.noteSuggestions end
    local menu
    menu = suggestionMenu(parent, edit, function(self)
        if not Notes:CanView() or active and not active() or not self.value then return end
        if onChoose then onChoose() end
        edit:SetText(self.value)
        edit:ClearFocus()
        menu:Hide()
    end)
    edit.noteSuggestions = menu
    function menu:Refresh()
        local query = edit:GetText():lower():match("^%s*(.-)%s*$")
        if not Notes:CanView() or active and not active() or not edit:HasFocus() or query == "" then self:Hide(); return end
        local matches, seen = {}, {}
        local function add(value, member)
            local key = value:lower()
            local position = key:find(query, 1, true)
            if position and not seen[key] then
                seen[key] = true
                matches[#matches + 1] = { value = value, starts = position == 1, member = member }
            end
        end
        for _, row in ipairs(iRC:GetGuildRosterSnapshot() or {}) do add(memberName(row.name), true) end
        for _, record in ipairs(Notes:GetRecords(nil, true)) do
            add(memberName(record.member), true)
            add(record.title, false)
        end
        table.sort(matches, function(a, b)
            if a.starts ~= b.starts then return a.starts end
            if a.member ~= b.member then return a.member end
            return a.value:lower() < b.value:lower()
        end)
        local found = math.min(#matches, #self.buttons)
        for index, option in ipairs(self.buttons) do
            option.value = matches[index] and matches[index].value or nil
            if option.value then option.text:SetText(plain(option.value)) end
            option:SetShown(index <= found)
        end
        self:SetHeight(found * 23 + 12)
        self:SetShown(found > 0)
    end
    edit:HookScript("OnTextChanged", function() menu:Refresh() end)
    edit:HookScript("OnEditFocusGained", function() menu:Refresh() end)
    edit:HookScript("OnEditFocusLost", function()
        C_Timer.After(0, function() if not iRC:IsMouseOverFrame(menu) then menu:Hide() end end)
    end)
    edit:HookScript("OnEscapePressed", function(self) self:ClearFocus(); menu:Hide() end)
    edit:SetScript("OnEnterPressed", function(self)
        if menu:IsShown() and menu.buttons[1].value then menu.buttons[1]:Click() else self:ClearFocus() end
    end)
    edit:HookScript("OnHide", function() menu:Hide() end)
    return menu
end

local function status(record)
    if record.status == "DELETED" then return "Removed" end
    if record.strike then
        return record.status == "ACTIVE" and "Active strike" or record.status == "RESOLVED" and "Resolved strike" or "Revoked strike"
    end
    return "Note"
end

local function feedback(frame, message, warning)
    frame.feedback:SetTextColor(warning and 1 or GRAY[1], warning and 0.1 or GRAY[2], warning and 0.1 or GRAY[3])
    frame.feedback:SetText(message)
end

function UI:ShowHistory()
    local frame = self.frame
    if not frame or not frame.selected or not Notes:CanView() then return end
    if not self.history then
        local history = CreateFrame("Frame", "iRCMemberNoteHistory", UIParent, "BackdropTemplate")
        history:SetSize(660, 480)
        history:SetPoint("CENTER")
        history:SetFrameStrata("FULLSCREEN_DIALOG")
        history:EnableMouse(true)
        history:SetClampedToScreen(true)
        surface(history, true)
        label(history, "Note history", 18, -15, "GameFontNormalLarge")
        local close = CreateFrame("Button", nil, history, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 0, 0)
        close:SetScript("OnClick", function() history:Hide() end)
        local scroll = CreateFrame("ScrollFrame", nil, history, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 18, -46)
        scroll:SetPoint("BOTTOMRIGHT", -34, 18)
        iRC:StyleScrollFrame(scroll)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(600, 1)
        scroll:SetScrollChild(content)
        history.text = label(content, "", 0, 0)
        history.text:SetWidth(590)
        history.content, history.scroll = content, scroll
        self.history = history
        UISpecialFrames[#UISpecialFrames + 1] = "iRCMemberNoteHistory"
    end
    local lines, records = {}, Notes:GetHistory(frame.selected.noteID)
    for index = #records, math.max(1, #records - 19), -1 do
        local record = records[index]
        lines[#lines + 1] = "|cFFFFC34D" .. plain(memberName(record.author)) .. "|r  |cFFAAAAAA"
            .. date("%Y-%m-%d %H:%M", record.at) .. "|r"
        lines[#lines + 1] = record.action .. " · " .. status(record)
        lines[#lines + 1] = plain(record.title)
        lines[#lines + 1] = plain(record.body)
        if record.reason ~= "" then lines[#lines + 1] = "Change reason: " .. plain(record.reason) end
        lines[#lines + 1] = " "
    end
    if #records > 20 then lines[#lines + 1] = "Showing the 20 most recent changes." end
    self.history.text:SetText(table.concat(lines, "\n"))
    self.history.content:SetHeight(math.max(1, self.history.text:GetStringHeight() + 12))
    self.history.scroll:SetVerticalScroll(0)
    self.history:SetFrameLevel(frame:GetFrameLevel() + 40)
    self.history:Show()
    self.history:Raise()
end

function UI:Select(record)
    local frame = self.frame
    if not frame or not Notes:CanView() then return end
    frame.selected = record
    frame.reference = record and record.reference or ""
    frame.member:SetText(memberName(record and record.member or frame.memberFilter))
    frame.member:SetEnabled(record == nil)
    frame.titleInput:SetText(record and record.title or "")
    frame.body:SetText(record and record.body or "")
    frame.reason:SetText("")
    frame.strike:SetChecked(record and record.strike or false)
    frame.heading:SetText(record and plain(memberName(record.member)) or "New member note")
    feedback(frame, "")
    if self.history then self.history:Hide() end
    self:RefreshIfShown()
end

function UI:Save(action)
    local frame = self.frame
    if not frame then return end
    local current = frame.selected
    local record, err = Notes:Save(frame.member:GetText(), frame.titleInput:GetText(), frame.body:GetText(),
        frame.strike:GetChecked(), current and current.noteID, current and current.id, frame.reason:GetText(), action, frame.reference)
    if not record then feedback(frame, err or "The note could not be saved.", true); return end
    self:Select(record.status ~= "DELETED" and record or nil)
    feedback(frame, record.status == "DELETED" and "Note removed. Its history is retained." or "Saved. Your changes sync directly with authorised members online.")
end

function UI:RenderRows()
    local frame = self.frame
    if not frame or not Notes:CanView() then return end
    local first = math.floor(frame.scroll:GetVerticalScroll() / 62) + 1
    local visible = math.min(#frame.records - first + 1, math.ceil(frame.scroll:GetHeight() / 62) + 1)
    for slot = 1, math.max(0, visible) do
        local record = frame.records[first + slot - 1]
        local row = frame.rows[slot]
        if not row then
            row = CreateFrame("Button", nil, frame.list, "BackdropTemplate")
            row:SetHeight(58)
            surface(row)
            row.name = label(row, "", 9, -6)
            row.name:SetWidth(252)
            row.name:SetWordWrap(false)
            row.title = label(row, "", 9, -23, "GameFontHighlightSmall")
            row.title:SetWidth(252)
            row.title:SetWordWrap(false)
            row.status = label(row, "", 9, -39, "GameFontDisableSmall")
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            row:SetScript("OnClick", function(self) UI:Select(self.record) end)
            frame.rows[slot] = row
        end
        row.record = record
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(first + slot - 2) * 62)
        row:SetPoint("TOPRIGHT", 0, -(first + slot - 2) * 62)
        row.name:SetText(plain(memberName(record.member)))
        row.name:SetTextColor(unpack(GOLD))
        row.title:SetText(plain(record.title))
        row.status:SetText(status(record) .. " · " .. date("%d %b", record.at))
        row:SetBackdropBorderColor(unpack(record.strike and record.status == "ACTIVE" and RED or {0.30, 0.24, 0.12}))
        row:Show()
    end
    for slot = math.max(0, visible) + 1, #frame.rows do frame.rows[slot]:Hide() end
end

function UI:RefreshIfShown()
    local frame = self.frame
    if not frame or not frame:IsShown() then return end
    if not Notes:CanView() or frame.scope ~= Notes:GetScope() then
        frame:Hide()
        frame.body:SetText("")
        frame.titleInput:SetText("")
        if self.history then self.history:Hide() end
        return
    end
    local query = (frame.search:GetText() or ""):lower()
    frame.records = {}
    for _, record in ipairs(Notes:GetRecords(frame.memberFilter, frame.filter == "REMOVED")) do
        if (frame.filter == "ALL" or frame.filter == "STRIKES" and record.strike or frame.filter == "NOTES" and not record.strike
            or frame.filter == "REMOVED" and record.status == "DELETED")
            and (query == "" or (memberName(record.member) .. " " .. record.title .. " " .. record.body):lower():find(query, 1, true)) then
            frame.records[#frame.records + 1] = record
        end
    end
    local count, strikes = Notes:GetCounts(frame.memberFilter)
    frame.summary:SetText(count .. " notes · " .. strikes .. " active strikes")
    frame.allMembers:SetShown(frame.memberFilter ~= nil)
    frame.list:SetHeight(math.max(1, #frame.records * 62))
    frame.scroll:SetVerticalScroll(math.min(frame.scroll:GetVerticalScroll(), math.max(0, frame.list:GetHeight() - frame.scroll:GetHeight())))
    frame.empty:SetShown(#frame.records == 0)
    local manage, add = Notes:Can("notesManage"), Notes:Can("notesAdd")
    local editable = frame.selected and manage and frame.selected.status ~= "DELETED" or not frame.selected and (add or manage)
    for _, filter in ipairs(frame.filters) do
        filter:SetBackdropBorderColor(unpack(filter.filterKey == frame.filter and GOLD or GRAY))
    end
    frame.add:SetEnabled(add or manage)
    frame.strike:SetEnabled(manage and editable)
    frame.titleInput:SetEnabled(editable)
    frame.body:SetEnabled(editable)
    frame.reason:SetEnabled(editable)
    frame.save:SetEnabled(editable)
    frame.resolve:SetEnabled(manage and frame.selected ~= nil and frame.selected.strike and frame.selected.status == "ACTIVE")
    frame.revoke:SetEnabled(editable and frame.selected ~= nil and frame.selected.strike and frame.selected.status ~= "REVOKED")
    frame.remove:SetEnabled(editable and frame.selected ~= nil)
    frame.history:SetEnabled(frame.selected ~= nil)
    frame.meta:SetText(frame.selected and ("By " .. plain(memberName(frame.selected.createdBy)) .. " · " .. date("%Y-%m-%d %H:%M", frame.selected.createdAt)
        .. "\n" .. status(frame.selected) .. (frame.selected.revision > 1 and " · Edited by " .. plain(memberName(frame.selected.author)) or "")
        .. (frame.selected.reference ~= "" and " · Linked violation" or "")) or "Private guild notes · Visible to authorised members only")
    self:RenderRows()
end

function UI:Create()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", "iRCMemberNotesFrame", UIParent, "BackdropTemplate")
    self.frame = frame
    frame:SetSize(840, 610)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    surface(frame, true)
    label(frame, "Member Notes", 18, -15, "GameFontNormalLarge")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame:SetScript("OnHide", function()
        if UI.history then UI.history:Hide() end
        if frame.suggestions then frame.suggestions:Hide() end
        if frame.search.noteSuggestions then frame.search.noteSuggestions:Hide() end
        frame.search:ClearFocus()
        frame.member:ClearFocus(); frame.titleInput:ClearFocus(); frame.body:ClearFocus(); frame.reason:ClearFocus()
    end)
    UISpecialFrames[#UISpecialFrames + 1] = "iRCMemberNotesFrame"
    frame.summary = label(frame, "", 18, -42, "GameFontDisableSmall")
    frame.search = input(frame, 278, 120)
    frame.search:SetPoint("TOPLEFT", 18, -65)
    frame.search.hint = frame.search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.search.hint:SetText("Search members and notes...")
    frame.search:SetScript("OnTextChanged", function(self)
        self.hint:SetShown(self:GetText() == "")
        UI:RefreshIfShown()
    end)
    iRC:StyleSearchBox(frame.search, frame.search.hint)
    frame.filter = "ALL"
    frame.filters = {}
    for index, option in ipairs({{"ALL", "All"}, {"NOTES", "Notes"}, {"STRIKES", "Strikes"}, {"REMOVED", "Removed"}}) do
        local filterKey = option[1]
        local filter = button(frame, option[2], 64, function()
            frame.filter = filterKey
            frame.scroll:SetVerticalScroll(0)
            UI:RefreshIfShown()
        end)
        filter:SetPoint("TOPLEFT", 18 + (index - 1) * 70, -101)
        filter.filterKey = option[1]
        frame.filters[#frame.filters + 1] = filter
    end
    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", 18, -140)
    frame.scroll:SetPoint("BOTTOMLEFT", 18, 84)
    frame.scroll:SetWidth(270)
    iRC:StyleScrollFrame(frame.scroll)
    frame.list = CreateFrame("Frame", nil, frame.scroll)
    frame.list:SetSize(270, 1)
    frame.scroll:SetScrollChild(frame.list)
    frame.rows, frame.records = {}, {}
    frame.scroll:HookScript("OnVerticalScroll", function() UI:RenderRows() end)
    frame.empty = label(frame.list, "No notes match this view.", 6, -8, "GameFontDisableSmall")
    frame.add = button(frame, "Add note", 132, function() UI:Select(nil) end)
    frame.add:SetPoint("BOTTOMLEFT", 18, 46)
    local refresh = button(frame, "Refresh notes", 132, function()
        local sent = Notes:Announce(true)
        feedback(frame, sent and "Requested private updates from authorised members." or "Please wait before refreshing again.", not sent)
    end)
    refresh:SetPoint("LEFT", frame.add, "RIGHT", 12, 0)
    frame.allMembers = button(frame, "Show all members", 276, function()
        frame.memberFilter = nil
        UI:RefreshIfShown()
    end)
    frame.allMembers:SetPoint("BOTTOMLEFT", 18, 12)

    local editor = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    editor:SetPoint("TOPLEFT", 326, -48)
    editor:SetPoint("BOTTOMRIGHT", -18, 16)
    surface(editor)
    frame.heading = label(editor, "New member note", 14, -12, "GameFontNormalLarge")
    frame.heading:SetWidth(460)
    frame.heading:SetWordWrap(false)
    label(editor, "Member", 14, -45, "GameFontDisableSmall")
    frame.member = input(editor, 460, 120)
    frame.member:SetPoint("TOPLEFT", 14, -61)
    label(editor, "Title", 14, -96, "GameFontDisableSmall")
    frame.titleInput = input(editor, 460, 120)
    frame.titleInput:SetPoint("TOPLEFT", 14, -112)
    label(editor, "Note", 14, -148, "GameFontDisableSmall")
    local bodyScroll = CreateFrame("ScrollFrame", nil, editor, "UIPanelScrollFrameTemplate")
    bodyScroll:SetPoint("TOPLEFT", 14, -168)
    bodyScroll:SetPoint("BOTTOMRIGHT", -32, 197)
    iRC:StyleScrollFrame(bodyScroll)
    frame.body = CreateFrame("EditBox", nil, bodyScroll, "BackdropTemplate")
    frame.body:SetMultiLine(true)
    setupTextInput(frame.body)
    frame.body:SetWidth(430)
    frame.body:SetHeight(150)
    frame.body:SetTextInsets(6, 6, 6, 6)
    frame.body:SetMaxLetters(2048)
    if frame.body.SetMaxBytes then frame.body:SetMaxBytes(2048) end
    surface(frame.body)
    bodyScroll:SetScrollChild(frame.body)
    frame.body:SetScript("OnTextChanged", function(self)
        local _, height = self:GetFont()
        self:SetHeight(math.max(bodyScroll:GetHeight(), self:GetNumLines() * height + 16))
        bodyScroll:UpdateScrollChildRect()
    end)
    bodyScroll:EnableMouse(true)
    bodyScroll:SetScript("OnMouseDown", function() if frame.body:IsEnabled() then frame.body:SetFocus() end end)
    if ScrollingEdit_OnCursorChanged then frame.body:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged) end
    frame.strike = CreateFrame("CheckButton", nil, editor, "UICheckButtonTemplate")
    frame.strike:SetPoint("BOTTOMLEFT", 10, 160)
    frame.strike.Text:SetText("Count as strike")
    local reasonLabel = label(editor, "Reason for this change (required to resolve, revoke or remove)", 14, 0, "GameFontDisableSmall")
    reasonLabel:ClearAllPoints()
    reasonLabel:SetPoint("BOTTOMLEFT", 14, 139)
    frame.reason = input(editor, 460, 240)
    frame.reason:SetPoint("BOTTOMLEFT", 14, 105)
    frame.meta = label(editor, "", 14, -437, "GameFontDisableSmall")
    frame.meta:ClearAllPoints()
    frame.meta:SetPoint("TOPLEFT", frame.reason, "BOTTOMLEFT", 0, -8)
    frame.meta:SetWidth(460)
    frame.meta:SetWordWrap(true)
    frame.save = button(editor, "Save note", 90, function() UI:Save() end)
    frame.save:SetPoint("BOTTOMLEFT", 14, 47)
    frame.resolve = button(editor, "Resolve", 76, function() UI:Save("RESOLVE") end)
    frame.resolve:SetPoint("LEFT", frame.save, "RIGHT", 6, 0)
    frame.revoke = button(editor, "Revoke", 76, function() UI:Save("REVOKE") end)
    frame.revoke:SetPoint("LEFT", frame.resolve, "RIGHT", 6, 0)
    frame.remove = button(editor, "Remove", 76, function() UI:Save("DELETE") end)
    frame.remove:SetPoint("LEFT", frame.revoke, "RIGHT", 6, 0)
    frame.history = button(editor, "History", 76, function() UI:ShowHistory() end)
    frame.history:SetPoint("LEFT", frame.remove, "RIGHT", 6, 0)
    frame.feedback = label(editor, "", 14, -503, "GameFontDisableSmall")
    frame.feedback:SetWidth(460)
    frame.feedback:SetWordWrap(true)
    frame.suggestions = CreateFrame("Frame", nil, editor, "BackdropTemplate")
    frame.suggestions:SetPoint("TOPLEFT", frame.member, "BOTTOMLEFT", 0, -2)
    frame.suggestions:SetPoint("TOPRIGHT", frame.member, "BOTTOMRIGHT", 0, -2)
    frame.suggestions:SetHeight(127)
    frame.suggestions:SetFrameLevel(editor:GetFrameLevel() + 15)
    frame.suggestions:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame.suggestions:SetBackdropColor(0.03, 0.03, 0.03, 0.98)
    frame.suggestions:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.85)
    frame.suggestions.buttons = {}
    for index = 1, 5 do
        local suggestion = CreateFrame("Button", nil, frame.suggestions)
        suggestion:SetHeight(23)
        suggestion:SetPoint("TOPLEFT", 7, -6 - (index - 1) * 23)
        suggestion:SetPoint("TOPRIGHT", -7, -6 - (index - 1) * 23)
        suggestion.text = label(suggestion, "", 7, 0)
        suggestion.text:ClearAllPoints()
        suggestion.text:SetPoint("LEFT", 7, 0)
        suggestion.text:SetPoint("RIGHT", -7, 0)
        suggestion.text:SetWordWrap(false)
        suggestion.highlight = suggestion:CreateTexture(nil, "HIGHLIGHT")
        suggestion.highlight:SetAllPoints()
        suggestion.highlight:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.18)
        suggestion:SetScript("OnClick", function(self)
            frame.member:SetText(memberName(self.memberName))
            frame.member:ClearFocus()
            frame.suggestions:Hide()
        end)
        frame.suggestions.buttons[index] = suggestion
    end
    local function updateMemberSuggestions(self)
        local query = self:GetText():lower():match("^%s*(.-)%s*$")
        if not self:HasFocus() or query == "" or frame.selected then frame.suggestions:Hide(); return end
        local matches = {}
        for _, member in ipairs(iRC:GetGuildRosterSnapshot() or {}) do
            local position = memberName(member.name):lower():find(query, 1, true)
            if position then
                matches[#matches + 1] = { name = member.name, starts = position == 1 }
            end
        end
        table.sort(matches, function(a, b)
            if a.starts ~= b.starts then return a.starts end
            return a.name:lower() < b.name:lower()
        end)
        local found = math.min(#matches, #frame.suggestions.buttons)
        for index, suggestion in ipairs(frame.suggestions.buttons) do
            if index <= found then
                suggestion.memberName = matches[index].name
                suggestion.text:SetText(plain(memberName(matches[index].name)))
            end
            suggestion:SetShown(index <= found)
        end
        frame.suggestions:SetHeight(found * 23 + 12)
        frame.suggestions:SetShown(found > 0)
    end
    frame.member:SetScript("OnTextChanged", updateMemberSuggestions)
    frame.member:HookScript("OnEditFocusGained", updateMemberSuggestions)
    frame.member:SetScript("OnEscapePressed", function(self) self:ClearFocus(); frame.suggestions:Hide() end)
    frame.member:SetScript("OnEnterPressed", function(self)
        if frame.suggestions:IsShown() then frame.suggestions.buttons[1]:Click() else self:ClearFocus() end
    end)
    frame.member:HookScript("OnEditFocusLost", function()
        C_Timer.After(0, function() if not iRC:IsMouseOverFrame(frame.suggestions) then frame.suggestions:Hide() end end)
    end)
    frame.suggestions:Hide()
    self:AttachSearchSuggestions(frame.search, frame, nil, function() frame.memberFilter = nil end)
    frame:Hide()
    return frame
end

function UI:Open(member, noteID)
    if not Notes:CanView() then return false end
    local frame = self:Create()
    frame.scope, frame.memberFilter = Notes:GetScope(), member
    local main = iRC.MainUI and iRC.MainUI.frame
    if main then frame:SetScale(main:GetScale()) end
    -- Keep the editor above the main window even after its member menu is raised.
    frame:SetFrameLevel((main and main:GetFrameLevel() or 0) + 80)
    frame.search:SetText("")
    frame.scroll:SetVerticalScroll(0)
    frame:Show()
    self:Select(noteID and Notes:GetRecord(noteID) or nil)
    frame:Raise()
    Notes:Announce()
    return true
end

function UI:OpenFromIncident(incident)
    if type(incident) ~= "table" or not iRC:HasGuildPermission("incidents")
        or not (Notes:Can("notesAdd") or Notes:Can("notesManage")) or not self:Open() then return false end
    local frame = self.frame
    frame.reference = tostring(incident.id or "")
    frame.titleInput:SetText("Challenge violation")
    frame.body:SetText(table.concat({ tostring(incident.reason or "Review this challenge violation."),
        "Location: " .. tostring(incident.instanceName or "Unknown"),
        "Reported: " .. date("%Y-%m-%d %H:%M", tonumber(incident.occurredAt) or time()),
        "Players: " .. tostring(incident.players or "Unknown") }, "\n"))
    frame.member:SetFocus()
    return true
end
