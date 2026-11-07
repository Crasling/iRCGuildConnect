-- Build the real About-page section with lightweight controls. Native
-- invitation APIs are forbidden even when they return without a Lua error.
local file = assert(io.open("iRC_Options.lua", "r"))
local source = file:read("*a"); file:close()
local expectedURL = "https://www.worldofwarcraft.com/invite/3d423YnU7rA?region=EU&faction=Horde"
local addon = { Colors = setmetatable({}, { __index = function() return "" end }) }
assert(loadfile("Localization/enUS.lua"))("iRC", { iRC = addon })
local secret = {}
function addon:IsSecretValue(value) return rawequal(value, secret) end
local state = { protectedCalls = 0, buttons = {}, region = 3, faction = "Horde" }
local function protectedCall()
    state.protectedCalls = state.protectedCalls + 1
    -- Model a native ADDON_ACTION_FORBIDDEN event, not a catchable Lua error.
    return nil
end
local env = {
    C_Club = { RequestTicket = protectedCall, GetLastTicketResponse = protectedCall, RedeemTicket = protectedCall },
    C_AddOns = { LoadAddOn = protectedCall },
    CommunitiesHyperlink = { OnClickLink = protectedCall },
    ShowUIPanel = protectedCall,
    InCombatLockdown = function() return state.combat == true end,
    GetCurrentRegion = function() if state.regionError then error("not ready") end; return state.region end,
    UnitFactionGroup = function(unit) assert(unit == "player"); return state.faction end,
}
setmetatable(env, { __index = _G })
local function widget(_, _, parent)
    local frame = { scripts = {}, parent = parent, shown = true }
    function frame:SetText(text) self.text = text end
    function frame:GetText() return self.text end
    function frame:SetFocus() self.focused = true end
    function frame:ClearFocus() self.focused = false end
    function frame:HighlightText(first, last) self.highlighted = first == nil and last == nil end
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    function frame:CreateFontString() return widget("FontString", nil, self) end
    function frame:HookScript(event, callback) self.scripts[event] = callback end
    function frame:SetShown(shown) self.shown = shown end
    function frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function frame:SetHeight(height) self.height = height end
    function frame:RegisterEvent() end
    function frame:RegisterUnitEvent() end
    for _, method in ipairs({ "SetPoint", "SetWidth", "SetJustifyH", "SetJustifyV", "SetSize", "SetAutoFocus", "SetFontObject" }) do
        frame[method] = function() end
    end
    return frame
end
env.CreateFrame = widget
env.CreateSectionHeader = function(_, _, y) return widget(), y - 28 end
env.CreateInfoText = function(_, _, y) return widget(), y - 34 end
env.CreateSettingsCheckbox = function(_, _, _, y) return widget(), y - 34 end
env.CreateSettingsButton = function(_, text, _, y, callback)
    local button = { text = text, click = callback }
    state.buttons[#state.buttons + 1] = button
    return button, y - 34
end
local start = assert(source:find("    local communityTop = y", 1, true))
local finish = assert(source:find("\nend\n\nlocal companionAddons", start, true))
local prefix = source:sub(1, assert(source:find("-- Blizzard Settings panel", 1, true)) - 1)
local header = prefix .. "\nlocal aboutContent = select(3, ...)\nlocal y = -150\n"
local about = widget()
local controls = assert(load(header .. source:sub(start, finish - 1)
    .. "\nreturn { box = communityBox, hint = communityHint, section = communitySection, footer = aboutFooter }",
    "@iRC_Options.lua", "t", env))("iRC", { iRC = addon }, about)
assert(state.protectedCalls == 0 and not controls.box.focused, "building About must never request an invitation")
local button = assert(state.buttons[1])
assert(button.text == "Copy community invite")
button.click()
assert(controls.box:GetText() == expectedURL and controls.box.focused and controls.box.highlighted,
    "clicking selects the exact complete invite for Ctrl+C")
assert(controls.hint:GetText():find("Join Community", 1, true), "the hint explains where to paste the link in game")
controls.box:SetText("edited")
controls.box.scripts.OnEditFocusLost(controls.box)
assert(controls.box:GetText() == expectedURL, "editing cannot replace the configured community invite")
state.combat = true
button.click()
assert(controls.box:GetText() == expectedURL and controls.box.highlighted, "the copy button remains usable during combat")
controls.box.scripts.OnEscapePressed(controls.box)
assert(not controls.box.focused)
local fullHeight = about.height
assert(controls.section:IsVisible() and controls.box:IsVisible(), "EU Horde sees the complete community section")
for _, region in ipairs({ 1, 2, 3, 4, 5 }) do
    for _, faction in ipairs({ "Horde", "Alliance", "Neutral" }) do
        state.region, state.faction = region, faction
        about.scripts.OnShow(about)
        local eligible = region == 3 and faction == "Horde"
        assert(controls.section:IsVisible() == eligible and controls.box:IsVisible() == eligible,
            "the community link is visible only for EU Horde")
        assert(controls.footer:IsVisible(), "Discord and the other About sections remain available")
        if not eligible then
            assert(controls.section.height == 1 and about.height < fullHeight, "hidden community content leaves no empty section")
            button.click()
            assert(not controls.box.focused, "an ineligible character cannot focus the hidden invite")
        end
    end
end
state.region, state.faction = nil, "Horde"
about.scripts.OnShow(about)
assert(not controls.section:IsVisible(), "an unavailable region does not expose the invite")
state.region, state.faction = 3, nil
about.scripts.OnShow(about)
assert(not controls.section:IsVisible(), "an unavailable faction does not expose the invite")
state.region, state.faction = secret, "Horde"
about.scripts.OnShow(about)
assert(not controls.section:IsVisible(), "a secret region remains hidden")
state.region, state.faction = 3, secret
about.scripts.OnShow(about)
assert(not controls.section:IsVisible(), "a secret faction remains hidden")
state.region, state.faction = 3, "Horde"
controls.section.scripts.OnEvent(controls.section, "PLAYER_ENTERING_WORLD")
assert(controls.section:IsVisible() and about.height == fullHeight, "the section appears when player identity becomes available")
state.faction = "Alliance"
controls.section.scripts.OnEvent(controls.section, "UNIT_FACTION", "player")
assert(not controls.section:IsVisible(), "a faction update hides the section immediately")
assert(state.protectedCalls == 0, "no click may invoke the protected community flow or load Blizzard's invitation handlers")
assert(not source:find("CommunitiesHyperlink.OnClickLink", 1, true) and not source:find("C_Club.RequestTicket", 1, true),
    "the old asynchronous invitation entry point is removed")
print("PASS: EU Horde-only visibility, unavailable/secret identity, live faction updates, compact About layout and safe copying without invitation APIs")
