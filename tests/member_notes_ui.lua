local fixture = assert(loadfile("tests/member_notes.lua"))()
local a, roles = fixture.clients["Guild Master"], fixture.roles
local env, widgets = a.env, {}
local make
local methods = {}
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:GetWidth() return self.width or 270 end
function methods:GetHeight() return self.height or 350 end
function methods:GetFont() return "font", 12, "" end
function methods:GetNumLines() return select(2, (self.text or ""):gsub("\n", "")) + 1 end
function methods:GetStringHeight() return self:GetNumLines() * 12 end
function methods:SetText(value, ...)
    assert(select("#", ...) == 0, "SetText gets only its text argument")
    self.text = tostring(value or "")
    if self.OnTextChanged then self:OnTextChanged() end
end
function methods:GetText() return self.text or "" end
function methods:SetScript(event, callback) self[event] = callback end
function methods:HookScript(event, callback)
    local old = self[event]
    self[event] = function(self, ...) if old then old(self, ...) end; callback(self, ...) end
end
function methods:GetParent() return self.parent end
function methods:Show() self.shown = true end
function methods:Hide()
    local shown = self.shown; self.shown = false
    if shown and self.OnHide then self:OnHide() end
end
function methods:IsShown() return self.shown end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:SetEnabled(value) assert(type(value) == "boolean"); self.enabled = value end
function methods:IsEnabled() return self.enabled end
function methods:EnableMouse(value) self.mouseEnabled = value end
function methods:EnableKeyboard(value) self.keyboardEnabled = value end
function methods:SetBlinkSpeed(value) self.blinkSpeed = value end
function methods:SetTextColor(...) self.textColor = {...} end
function methods:SetJustifyH(value) self.justifyH = value end
function methods:Click() if self.enabled ~= false and self.OnClick then self:OnClick() end end
function methods:SetChecked(value) self.checked = value end
function methods:GetChecked() return self.checked end
function methods:HasFocus() return self.focused end
function methods:SetFocus() self.focused = true; if self.OnEditFocusGained then self:OnEditFocusGained() end end
function methods:ClearFocus() self.focused = false; if self.OnEditFocusLost then self:OnEditFocusLost() end end
function methods:SetFrameLevel(value) self.frameLevel = value end
function methods:GetFrameLevel() return self.frameLevel or (self.parent and self.parent:GetFrameLevel() + 1) or 1 end
function methods:SetFrameStrata(value) self.strata = value end
function methods:GetFrameStrata() return self.strata or (self.parent and self.parent:GetFrameStrata()) or "MEDIUM" end
function methods:GetScale() return 1 end
function methods:GetRegions() return end
function methods:GetVerticalScroll() return self.scroll or 0 end
function methods:SetVerticalScroll(value) self.scroll = value end
function methods:CreateFontString() return make("FontString", nil, self) end
function methods:CreateTexture() return make("Texture", nil, self) end
make = function(kind, name, parent, template)
    local item = { kind = kind, name = name, parent = parent, shown = true, enabled = true }
    setmetatable(item, { __index = function(_, key)
        if methods[key] then return methods[key] end
        if key:match("^Set") or key:match("^Enable") or key:match("^Register") or key:match("^Clear")
            or key == "StartMoving" or key == "StopMovingOrSizing" or key == "Raise" or key == "UpdateScrollChildRect" then return function() end end
    end })
    if template == "UICheckButtonTemplate" then item.Text = make("FontString", nil, item) end
    widgets[#widgets + 1] = item
    return item
end
env.CreateFrame, env.UIParent, env.UISpecialFrames = make, make("Frame"), {}
env.ChatFontNormal, env.unpack, env.date = "font", table.unpack, os.date
function a:StyleScrollFrame() end
local coreFile = assert(io.open("iRC_Core.lua"))
local coreSource = coreFile:read("*a"); coreFile:close()
local searchStyle = assert(coreSource:match("(function iRC:StyleSearchBox%b().-\nend)"))
assert(load("local iRC = ...\n" .. searchStyle, "shared search style", "t", env))(a)
local nameStyle = assert(coreSource:match("(function iRC:FormatInviteContactName%b().-\nend)"))
assert(load("local iRC = ...\n" .. nameStyle, "shared name formatting", "t", env))(a)
function a:IsMouseOverFrame() return false end
roles[a.name] = { notesView = true, notesAdd = true, notesManage = true }
a.MemberNotes:GetStore(true).operations = {}
a.MemberNotes:GetStore(true).count = 0
assert(loadfile("iRC_MemberNotesUI.lua", "t", env))("iRC", { iRC = a })
local ui = a.MemberNotes.UI
a.MainUI = { frame = make("Frame") }
a.MainUI.frame:SetFrameStrata("DIALOG")
a.MainUI.frame:SetFrameLevel(30)
assert(ui:Open())
local frame = assert(ui.frame)
assert(frame:GetFrameStrata() == "FULLSCREEN_DIALOG" and frame:GetFrameLevel() > a.MainUI.frame:GetFrameLevel(),
    "member notes stay above the main iRC panel")
for _, edit in ipairs({frame.search, frame.member, frame.titleInput, frame.body, frame.reason}) do
    assert(edit.blinkSpeed == 0.5 and edit.mouseEnabled and edit.keyboardEnabled,
        "every text field supports a blinking cursor and keyboard entry")
    edit:ClearFocus(); edit:OnMouseDown()
    assert(edit:HasFocus(), "clicking an input focuses its text cursor")
    edit:ClearFocus()
end
assert(not frame.strike:GetChecked(), "new notes do not count as strikes by default")
frame.member:SetFocus(); frame.member:SetText("Reg")
assert(frame.suggestions:IsShown(), "member entry autocompletes roster names")
assert(#frame.suggestions.buttons == 5 and frame.suggestions.buttons[1].text.justifyH == "LEFT"
    and frame.suggestions.buttons[1].highlight, "suggestions use compact left-aligned rows with the usual hover highlight")
frame.member:SetText("Member")
assert(frame.suggestions:IsShown(), "roster suggestions also match surnames")
frame.member:OnEscapePressed()
assert(not frame.suggestions:IsShown() and not frame.member:HasFocus(), "Escape dismisses the dropdown")
frame.member:SetFocus()
assert(frame.suggestions:IsShown(), "refocusing reopens suggestions for the existing text")
frame.member:SetText("Reg")
frame.suggestions.buttons[1]:Click()
assert(frame.member:GetText() == "Regular Member")
frame.titleInput:SetText("Raid availability")
frame.body:SetText("Available on weekends.\nPrefers healing.")
frame.save:Click()
assert(frame.selected and not frame.selected.strike and frame.selected.body:find("\n", 1, true))
local saved = frame.selected
local lowerCaseNote = {}
for key, value in pairs(saved) do lowerCaseNote[key] = value end
lowerCaseNote.member, lowerCaseNote.createdBy, lowerCaseNote.author = "regular member", "guild master", "officer two"
lowerCaseNote.revision = 2
ui:Select(lowerCaseNote)
assert(frame.member:GetText() == "Regular Member" and frame.heading:GetText() == "Regular Member"
    and frame.meta:GetText():find("By Guild Master", 1, true) and frame.meta:GetText():find("Edited by Officer Two", 1, true),
    "stored lowercase names are capitalised for display without changing the record")
frame.records = {lowerCaseNote}
ui:RenderRows()
assert(frame.rows[1].name:GetText() == "Regular Member" and lowerCaseNote.member == "regular member")
ui:Select(saved)
frame.history:Click()
assert(ui.history:IsShown() and ui.history.text:GetText():find("Available on weekends.", 1, true))
assert(ui.history:GetFrameLevel() > frame:GetFrameLevel(), "history remains above the notes editor")
frame.add:Click()
frame.member:SetText("Regular Member")
frame.titleInput:SetText("First warning")
frame.body:SetText("Discussed with the member.")
frame.strike:SetChecked(true)
frame.save:Click()
assert(frame.selected.strike and frame.resolve.enabled)
frame.resolve:Click()
assert(frame.feedback:GetText():find("reason", 1, true), "resolving asks for a reason")
frame.reason:SetText("Resolved after discussion")
frame.resolve:Click()
assert(frame.selected.status == "RESOLVED" and not frame.resolve.enabled)
frame.revoke:Click()
assert(frame.selected.status == "RESOLVED", "a new status change requires its own reason")
frame.reason:SetText("Entered by mistake")
frame.revoke:Click()
assert(frame.selected.status == "REVOKED")
assert(select(2, a.MemberNotes:GetCounts()) == 0)
ui:Select(saved)
local incoming = assert(a.MemberNotes:Save(saved.member, "Edited elsewhere", saved.body, false, saved.noteID, saved.id))
frame.titleInput:SetText("Unsaved local edit")
frame.save:Click()
assert(frame.feedback:GetText():find("changed", 1, true) and frame.titleInput:GetText() == "Unsaved local edit",
    "an incoming edit cannot erase the local draft or be overwritten silently")
ui:Select(incoming)
frame.reason:SetText("No longer needed")
frame.remove:Click()
assert(a.MemberNotes:GetRecord(saved.noteID).status == "DELETED")
assert(#a.MemberNotes:GetRecords() == 1, "removed notes disappear from the normal list")
frame.filters[4]:Click()
assert(#frame.records == 1 and frame.records[1].status == "DELETED", "removed notes remain available for review")
ui:Select(frame.records[1])
assert(not frame.save.enabled and frame.history.enabled, "removed notes have a readable history but cannot be edited")
frame.filters[1]:Click()

-- A large note list reuses the same visible rows.
for index = 1, 100 do
    assert(a.MemberNotes:Save("Regular Member", "Note " .. index, "Details", false))
end
ui:RefreshIfShown()
assert(#frame.rows < 15, "the list creates only visible rows")
local rowCount = #frame.rows
frame.scroll:SetVerticalScroll(62 * 60)
ui:RenderRows()
assert(#frame.rows == rowCount and frame.rows[1].record, "scrolling reuses pooled rows")
frame.search:SetText("First warning")
assert(#frame.records == 1, "search narrows the notes list")
assert(frame.search.iRCSearchClear:IsShown())
frame.search.iRCSearchClear:Click()
assert(frame.search:GetText() == "" and frame.search.hint:IsShown(), "the shared clear button restores the search hint")
frame.search:SetFocus(); frame.search:SetText("regular")
assert(frame.search.noteSuggestions:IsShown() and frame.search.noteSuggestions.buttons[1].value == "Regular Member",
    "the note search bar suggests roster members")
frame.search:OnEnterPressed()
assert(frame.search:GetText() == "Regular Member" and not frame.search.noteSuggestions:IsShown()
    and #frame.records > 0, "Enter selects the first suggestion and filters the notes")
frame.search:SetFocus(); frame.search:SetText("First warn")
assert(frame.search.noteSuggestions:IsShown() and frame.search.noteSuggestions.buttons[1].value == "First warning",
    "note titles are suggested too")
frame.search.noteSuggestions.buttons[1]:Click()
assert(frame.search:GetText() == "First warning" and #frame.records == 1)
frame.search.iRCSearchClear:Click()
assert(not frame.search.noteSuggestions:IsShown(), "clearing the search dismisses suggestions")
local managementSearch, notesActive = make("EditBox", nil, a.MainUI.frame), true
ui:AttachSearchSuggestions(managementSearch, a.MainUI.frame, function() return notesActive end)
managementSearch:SetFocus(); managementSearch:SetText("Regular")
assert(managementSearch.noteSuggestions:IsShown(), "the Management notes search uses the same dropdown")
notesActive = false; managementSearch.noteSuggestions:Refresh()
assert(not managementSearch.noteSuggestions:IsShown(), "switching away from notes closes the dropdown")
frame:Hide(); assert(ui:Open("Regular Member"), "the window reopens on a chosen member")
roles[a.name] = { notesView = true }
ui:RefreshIfShown()
assert(not frame.save.enabled and not frame.add.enabled and not frame.strike.enabled, "view permission cannot write or assign strikes")
roles[a.name] = {}
notesActive = true; managementSearch.noteSuggestions:Refresh()
assert(not managementSearch.noteSuggestions:IsShown(), "search suggestions require notes-view permission")
ui:RefreshIfShown()
assert(not frame:IsShown() and frame.body:GetText() == "", "revoking view access hides the report and clears displayed text")
roles[a.name] = { notesView = true, notesAdd = true, notesManage = true }
ui:Open()
roles[a.name].incidents = true
assert(ui:OpenFromIncident({ id = "incident-123", reason = "Challenge rule review", instanceName = "Dungeon",
    players = "Regular Member", occurredAt = a.env.time() }))
assert(frame.member:GetText() == "" and not frame.strike:GetChecked(), "a violation draft requires choosing its member and strike flag")
frame.member:SetText("Regular Member")
frame.save:Click()
assert(frame.selected.reference == "incident-123", "the saved note retains its original challenge-violation reference")
a.scope = "s-18-3-2-0-pvp"
ui:RefreshIfShown()
assert(not frame:IsShown(), "switching server scope closes the old private notes")
print("PASS: note editor, roster autocomplete, optional strikes, status reasons, history, draft conflicts, virtual rows, reopening and permission changes")
