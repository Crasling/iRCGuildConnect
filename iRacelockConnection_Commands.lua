local _, private = ...
local iRC = private and private.iRC
if not iRC then return end
local L = iRC.L

SLASH_IRC1 = "/irc"
SlashCmdList.IRC = function(message)
    local command, argument = (message or ""):match("^(%S*)%s*(.-)$")
    command = string.lower(command or "")
    if command == "" or command == "achievements" or command == "achievement" then
        iRC.AchievementsUI:Open()
    elseif command == "inspect" and argument ~= "" then
        iRC.AchievementsUI:Open(argument)
        iRC:RequestInspection(argument)
    elseif command == "options" or command == "settings" then
        iRC:OpenOptions()
    elseif command == "guild" or command == "dashboard" or command == "overview" then
        iRC:OpenConnectionDashboard()
    elseif command == "status" then
        local connection = iRC:GetConnection()
        if connection and iRC:IsGuildConnectionActive() then
            iRC:Print(iRC:Text("COMMAND_CONNECTED", connection.guildName))
        elseif connection then
            iRC:Print(iRC:Text("COMMAND_GUILD_INACTIVE", connection.guildName))
        else
            iRC:Print(L.COMMAND_NOT_CONNECTED)
        end
    else
        iRC:Print(L.COMMAND_HELP)
    end
end
