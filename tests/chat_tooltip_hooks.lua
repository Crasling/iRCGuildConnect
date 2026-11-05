-- Use the real tooltip setup without loading unrelated milestone handlers.
-- A blocked window must not be reported as a failure of every chat tooltip.
local env, addon, logs = {}, {}, {}
setmetatable(env, { __index = _G })
local secret = setmetatable({}, { __tostring = function() error("secret values must not be formatted") end })
function addon:IsSecretValue(value) return value == secret end
function addon:Text(key) return key end
function addon:DebugMsg(message, level) logs[#logs + 1] = { message = message, level = level } end
env.GameTooltip = { mouse = true }
function env.GameTooltip:IsMouseEnabled() return self.mouse end
function env.GameTooltip:EnableMouse(value) self.mouse = value end
function env.GameTooltip:SetOwner(owner) self.owner = owner end
function env.GameTooltip:SetText(text) self.title = text; self.lines = {} end
function env.GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end
function env.GameTooltip:Show() self.shown = true end
function env.GameTooltip:Hide() self.shown = false end

local file = assert(io.open("iRC_GuildAnnouncements.lua", "r"))
local source = file:read("*a")
file:close()
local first = assert(source:find("local ICON_HELP =", 1, true))
local last = assert(source:find("-- Guild announcements ", first, true))
local setup = "local iRC = ...\nlocal getRosterMember = function() return nil end\n"
    .. source:sub(first, last - 1) .. "\nreturn hookChatTooltip"
local hook = assert(load(setup, "@iRC_GuildAnnouncements.lua:tooltip", "t", env))(addon)
local function frame(name, blocked)
    local chat = { hooks = {}, attempts = 0 }
    function chat:GetName() return name end
    function chat:HookScript(event, callback)
        self.attempts = self.attempts + 1
        if blocked and blocked[event] then error(blocked[event], 0) end
        self.hooks[event] = callback
    end
    function chat:SetScript() error("existing chat scripts must not be replaced") end
    return chat
end

local working = frame("ChatFrame1")
hook(working)
assert(#logs == 0 and working.attempts == 2, "successful hooks produce no warning")
local function hover(chat, link, title)
    chat.hooks.OnHyperlinkEnter(chat, link)
    assert(env.GameTooltip.shown and env.GameTooltip.owner == chat and env.GameTooltip.title == title,
        "the original hyperlink hover still shows its tooltip")
    chat.hooks.OnHyperlinkLeave(chat)
    assert(not env.GameTooltip.shown and env.GameTooltip.mouse, "leaving restores tooltip mouse behavior")
end
hover(working, "addon:iRCIcon:creator", "CHAT_ICON_CREATOR_TITLE")
hover(working, "addon:iRCIdentity:Alt:Main Name", "Alt character")
hover(working, "addon:iRCIdentity:BankAlt:Main Name", "Personal Bank Alt")

local partitionError = "Cannot hook scripts across partitions"
local blocked = frame("ChatFrame2", { OnHyperlinkEnter = partitionError, OnHyperlinkLeave = partitionError })
hook(blocked)
assert(#logs == 1 and logs[1].level == 2 and logs[1].message:find("ChatFrame2", 1, true)
    and logs[1].message:find("OnHyperlinkEnter=failed", 1, true)
    and logs[1].message:find("OnHyperlinkLeave=failed", 1, true)
    and logs[1].message:find(partitionError, 1, true), "the warning identifies the blocked window, handlers and actual cause")
hover(working, "addon:iRCIcon:creator", "CHAT_ICON_CREATOR_TITLE")
assert(#logs == 1, "another window's warning does not mean the working tooltip is broken")
hook(blocked)
hook(working)
assert(#logs == 1 and blocked.attempts == 2 and working.attempts == 2, "repeat chat messages never rehook or repeat the warning")

local partial = frame("ChatFrame3", { OnHyperlinkLeave = partitionError })
hook(partial)
assert(#logs == 2 and logs[2].message:find("OnHyperlinkEnter=attached", 1, true)
    and logs[2].message:find("OnHyperlinkLeave=failed", 1, true), "one failed handler is distinguished from two failed handlers")
partial.hooks.OnHyperlinkEnter(partial, "addon:iRCIcon:creator")
assert(env.GameTooltip.shown, "a working hover-in handler can show the tooltip despite the warning")

local hidden = frame(secret, { OnHyperlinkEnter = secret, OnHyperlinkLeave = secret })
hook(hidden)
assert(logs[3].message:find("<unnamed>", 1, true) and logs[3].message:find("<secret>", 1, true),
    "secret error details and frame names are not formatted")
print("PASS: successful, blocked and partial chat hooks; exact per-window errors; icon, Alt and BankAlt tooltips unchanged")
