-- Run the actual homepage editor with saved-state and WoW-widget mocks.
unpack = table.unpack
local methods = {}
local function widget(parent)
    local object = { parent = parent, scripts = {}, hooks = {}, shown = true, enabled = true, points = {} }
    setmetatable(object, { __index = function(_, key)
        if methods[key] then return methods[key] end
        if key:match("^Set") or key:match("^Register") or key == "EnableMouse" or key == "Raise" then return function() end end
    end })
    return object
end
function methods:SetScript(event, run) self.scripts[event] = run end
function methods:HookScript(event, run)
    self.hooks[event] = self.hooks[event] or {}
    table.insert(self.hooks[event], run)
end
function methods:Fire(event, ...)
    if self.scripts[event] then self.scripts[event](self, ...) end
    for _, run in ipairs(self.hooks[event] or {}) do run(self, ...) end
end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetWidth(width) self.width = width end
function methods:GetWidth() return self.width or (self.parent and self.parent:GetWidth()) or 675 end
function methods:SetHeight(height) self.height = height end
function methods:GetHeight() return self.height or 1 end
function methods:SetPoint(...) self.points[#self.points + 1] = { ... } end
function methods:ClearAllPoints() self.points = {} end
function methods:CreateFontString() return widget(self) end
function methods:CreateTexture() return widget(self) end
function methods:SetThumbTexture() self.thumb = widget(self) end
function methods:GetThumbTexture() return self.thumb end
function methods:SetFontString(font) self.font = font end
function methods:SetText(text)
    if self.font then self.font:SetText(text); return end
    if self.text ~= text then self.text = text or ""; self:Fire("OnTextChanged") end
end
function methods:GetText() return self.text or "" end
function methods:SetFormattedText(format, ...) self:SetText(string.format(format, ...)) end
function methods:GetStringHeight() return 14 end
function methods:SetValue(value)
    if self.value ~= value then self.value = value; self:Fire("OnValueChanged", value) end
end
function methods:SetEnabled(enabled) self.enabled = enabled; self:Fire(enabled and "OnEnable" or "OnDisable") end
function methods:IsEnabled() return self.enabled end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false; self:Fire("OnHide") end
function methods:SetShown(shown) if shown then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown end
function methods:GetFrameLevel() return 1 end
function methods:GetBottom() return 500 end
function methods:SetFocus() self.focus = true; self:Fire("OnEditFocusGained") end
function methods:ClearFocus() self.focus = false; self:Fire("OnEditFocusLost") end
function methods:HasFocus() return self.focus == true end
function methods:GetCursorPosition() return #(self.text or "") end
function CreateFrame(_, _, parent) return widget(parent) end
UIParent = widget()
C_Timer = { After = function(_, run) run() end }

local active, permitted, combat, guildKey = true, true, false, "guild a"
local calls, previews = {}, 0
local function connection(description)
    return { rules = { guildContacts = "Contact One", raceLock = false, classLock = false },
        guildHomepageDescription = { text = description }, guildHomepageIcon = { icon = 1 },
        guildHomepageTag = { tag = "NORMAL" }, guildHomepageClassBreakdown = { mode = "ALL", minLevel = 1, maxLevel = 60 },
        guildContactDetails = { ["Contact One"] = { note = "Original note" } } }
end
local saved = connection("Saved description")
local names = { ["contact one"] = "Contact One", ["contact two"] = "Contact Two" }
local addon = { GuildHomepageIcons = { "Icon One", "Icon Two", "Icon Three" }, GuildHomepageDescriptionMaxLength = 160,
    Colors = { Red = "", Reset = "" } }
function addon:Text(key) return key end
function addon:NormalizeName(name) return tostring(name or ""):lower():gsub("-", " ") end
function addon:GetGuildKey() return guildKey end
function addon:GetConnection() return saved end
function addon:GetConnectionRules() return saved.rules end
function addon:GetGuildHomepageClassBreakdown() return saved.guildHomepageClassBreakdown end
function addon:GetGuildHomepageTag() return saved.guildHomepageTag.tag end
function addon:GetGuildContactDetails(name) return saved.guildContactDetails[name] end
function addon:IsGuildConnectionActive() return active end
function addon:HasGuildPermission() return permitted end
function addon:IsLowTrafficMode() return combat end
function addon:IsMouseOverFrame() return false end
function addon:FormatInviteContactName(name) return name end
function addon:ResolveGuildMemberFullName(name) return names[self:NormalizeName(name)] end
function addon:ContainsProfanity(text) return text:find("blocked", 1, true) ~= nil end
function addon:Print() end
function addon:GetGuildRosterSnapshot() return { { name = "Contact One" }, { name = "Contact Two" } } end
local editor, refreshDuringSave = {}, false
local function changed(kind)
    calls[#calls + 1] = kind
    if refreshDuringSave then editor:Refresh(saved, permitted) end
end
function addon:SetGuildHomepageDescription(value) saved.guildHomepageDescription.text = value; changed("description"); return true end
function addon:SetGuildHomepageIcon(value) saved.guildHomepageIcon.icon = value; changed("icon"); return true end
function addon:SetGuildHomepageTag(value) saved.guildHomepageTag.tag = value; changed("tag"); return true end
function addon:SetGuildHomepageClassBreakdown(mode, minimum, maximum)
    saved.guildHomepageClassBreakdown = { mode = mode, minLevel = minimum, maxLevel = maximum }
    changed("classes"); return true
end
function addon:SetGuildContacts(value) saved.rules.guildContacts = value; changed("contacts"); return true end
function addon:SetGuildContactNote(name, note) saved.guildContactDetails[name] = { note = note }; changed("note"); return true end
addon.MainUI = { CreateGuildHomepagePreview = function(_, parent)
    local preview = widget(parent)
    preview:SetHeight(120)
    function preview:Refresh(draft) self.draft = draft; previews = previews + 1 end
    return preview
end }
local content, container = widget(), widget()
local locale = setmetatable({}, { __index = function(_, key) return key end })
local env = setmetatable({ iRC = addon, L = locale, ORANGE = { 1, 0.6, 0.1 },
    homepageDescriptionUI = editor, guildHomepageContent = content, guildHomepageContainer = container,
    SetSimpleTooltip = function() end,
    CreateManagementSettingsCard = function(parent)
        local card = widget(parent); card:SetHeight(120); return card, -70
    end,
}, { __index = _G })
local sourceFile = assert(io.open("iRC_Options.lua", "r"))
local source = sourceFile:read("*a"); sourceFile:close()
local first = assert(source:find("(function()\nlocal editor = homepageDescriptionUI", 1, true))
local last = assert(source:find("\nend)()", first, true)) + #"\nend)()" - 1
assert(load(source:sub(first, last), "@iRC_Options.lua:homepage", "t", env))()

editor:Refresh(saved, true)
assert(#calls == 0 and not editor:IsDirty(), "initial binding must not save or send")
for _, key in ipairs({ "presentation", "appearance", "contacts", "statistics" }) do
    editor.tabs[key]:Fire("OnClick")
    local visible = 0
    for _, panel in pairs(editor.panels) do if panel:IsShown() then visible = visible + 1 end end
    assert(editor.activeTab == key and visible == 1, "only the selected homepage tab is shown")
end
editor.description:SetText("Draft description")
editor.iconButtons[2]:Fire("OnClick")
editor.classMode:Fire("OnClick")
editor.classMode.menu.buttons[2]:Fire("OnClick")
editor.classMin:SetValue(20)
editor.classMax:SetValue(40)
editor.contactInput:SetText("Contact Two")
editor.addContact:Fire("OnClick")
editor.contactRows[2].note:SetText("Draft note")
assert(#calls == 0 and saved.guildHomepageDescription.text == "Saved description", "edits stay local until Save")
assert(editor.preview.draft == editor.draft and editor.preview.draft.icon == 2 and previews > 0, "preview receives the current draft")
editor:Refresh(saved, true)
assert(editor.draft.description == "Draft description" and editor.draft.contactNotes["contact two"] == "Draft note",
    "normal settings refresh cannot overwrite unsaved edits")
refreshDuringSave = true
assert(editor:Save(), "one Save applies a valid draft even when setters refresh Options synchronously")
assert(table.concat(calls, ",") == "description,icon,classes,contacts,note", "only changed fields publish")
assert(saved.guildHomepageDescription.text == "Draft description" and saved.guildHomepageIcon.icon == 2)
assert(saved.guildHomepageClassBreakdown.minLevel == 20 and saved.guildHomepageClassBreakdown.maxLevel == 40)
assert(saved.guildContactDetails["Contact Two"].note == "Draft note" and not editor:IsDirty())

calls = {}
editor.description:SetText("Discard me")
editor.contactRows[1].note:SetFocus()
editor.contactRows[1].note:SetText("Discard this note")
editor:Discard()
assert(editor.draft.description == "Draft description" and #calls == 0 and not editor:IsDirty(), "Discard restores saved values without publishing")
assert(editor.contactRows[1].note:GetText() == "Original note", "Discard restores focused note fields as well")
editor.description:SetText("blocked description")
editor.iconButtons[3]:Fire("OnClick")
assert(not editor:Save() and #calls == 0 and editor.draft.icon == 3, "invalid description rejects the whole draft before any setter")
editor.description:SetText("Valid pending description")
editor.contactInput:SetText("Not In Guild")
assert(not editor:Save() and #calls == 0, "invalid pending contacts cannot partially save other fields")
editor.contactInput:SetText("")
permitted = false
assert(not editor:Save() and #calls == 0, "permission is rechecked at Save")
editor:Refresh(saved, false)
assert(not editor.save:IsEnabled() and editor.draft.description == "Valid pending description", "permission loss keeps a read-only draft")
permitted = true
editor:Refresh(saved, true)
combat = true
assert(not editor:Save() and #calls == 0, "combat blocks Save")
combat = false
saved.rules.classLock = true
editor:Refresh(saved, true)
assert(not editor.canChooseIcon and not editor.iconButtons[3]:IsEnabled(), "rulesets keep control of their required icon")
assert(editor.draft.icon == saved.guildHomepageIcon.icon)
saved.rules.classLock = false
editor:Discard()

editor.description:SetText("My new description")
saved.guildHomepageTag.tag = "PVP"
editor:Refresh(saved, true)
assert(editor.remoteChanged and editor.draft.description == "My new description", "remote changes are noticed without discarding local edits")
calls = {}
assert(editor:Save())
assert(table.concat(calls, ",") == "description" and saved.guildHomepageTag.tag == "PVP", "Save preserves fields changed remotely but untouched in the draft")

calls = {}
editor.description:SetText("Description saved before later failure")
editor.iconButtons[3]:Fire("OnClick")
local setIcon, setDescription = addon.SetGuildHomepageIcon, addon.SetGuildHomepageDescription
addon.SetGuildHomepageIcon = function() return false end
assert(not editor:Save() and table.concat(calls, ",") == "description", "a setter failure stops later fields and retains the draft")
addon.SetGuildHomepageIcon = setIcon
addon.SetGuildHomepageDescription = function(self, text)
    assert(text ~= saved.guildHomepageDescription.text, "retry must not publish an already applied value")
    return setDescription(self, text)
end
assert(editor:Save() and table.concat(calls, ",") == "description,icon", "retry finishes only the unapplied fields")
assert(not editor:IsDirty())
addon.SetGuildHomepageDescription = setDescription

editor.description:SetText("Guild A private draft")
editor.description:SetFocus()
editor.contactRows[1].note:SetFocus()
guildKey, saved = "guild b", connection("Guild B description")
editor:Refresh(saved, true)
assert(editor.draft.description == "Guild B description" and not editor:IsDirty(), "switching guilds discards the previous guild's local draft")
assert(editor.description:GetText() == "Guild B description" and not editor.description:HasFocus(),
    "focused inputs cannot retain a previous guild's private draft")
assert(#calls == 2, "switching guilds does not publish")
print("PASS: homepage drafts, tabs, preview, changed-only Save, discard, validation, permissions, remote updates, and guild changes")
