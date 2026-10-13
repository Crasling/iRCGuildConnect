local _, private = ...
local iRC = private and private.iRC
if not iRC then return end
local L = iRC.L

-- Register the short command players use in chat. WoW calls the matching
-- SlashCmdList handler with everything written after "/irc".
SLASH_IRC1 = "/irc"
SlashCmdList.IRC = function(message)
    -- Commands are deliberately single words and case-insensitive. Only the
    -- first following word is needed today, as the inactive-members command
    -- accepts one optional day count.
    local command = (message or ""):match("^(%S*)")
    local argument = (message or ""):match("^%S+%s+(%S+)")
    command = string.lower(command or "")

    -- Opening the main panel also asks guild members for recent cached
    -- leaderboard reports. This is the same behavior as the minimap button.
    if command == "" or command == "main" then
        iRC.MainUI:Open(nil, true)

    -- Keep familiar aliases so players do not need to remember whether the
    -- Blizzard panel calls them options or settings.
    elseif command == "options" or command == "settings" then
        iRC:OpenOptions()

    -- These aliases all lead to the guild connection and verification view.
    elseif command == "guild" or command == "dashboard" or command == "overview" then
        iRC:OpenConnectionDashboard()

    -- Status is intentionally read-only: it reports whether this guild has a
    -- saved connection and whether that connection is currently active.
    elseif command == "status" then
        local connection = iRC:GetConnection()
        if connection and iRC:IsGuildConnectionActive() then
            iRC:Print(iRC:Text("COMMAND_CONNECTED", connection.guildName))
        elseif connection then
            iRC:Print(iRC:Text("COMMAND_GUILD_INACTIVE", connection.guildName))
        else
            iRC:Print(L.COMMAND_NOT_CONNECTED)
        end

    -- "/irc inactive 45" opens the inactive-member tool at 45 days. Missing
    -- or non-numeric input falls back to the usual 30-day threshold; the UI
    -- performs the final permission check and clamps the value safely.
    elseif command == "inactive" then
        iRC.MainUI:OpenInactiveMembers(tonumber(argument) or 30)

    -- Unknown commands return the localized command summary rather than
    -- failing silently.
    else
        iRC:Print(L.COMMAND_HELP)
    end
end
