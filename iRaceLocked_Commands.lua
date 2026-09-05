local iRL = _G.iRaceLocked
if not iRL then return end

SLASH_IRACELOCKED1 = "/irc"
SLASH_IRACELOCKED2 = "/irl"
SlashCmdList.IRACELOCKED = function(message)
    local command, argument = (message or ""):match("^(%S*)%s*(.-)$")
    command = string.lower(command or "")
    if command == "" or command == "achievements" or command == "achievement" then
        iRL.AchievementsUI:Open()
    elseif command == "inspect" and argument ~= "" then
        iRL.AchievementsUI:Open(argument)
        iRL:RequestInspection(argument)
    elseif command == "options" or command == "settings" then
        iRL:OpenOptions()
    elseif command == "guild" or command == "dashboard" or command == "overview" then
        iRL:OpenConnectionDashboard()
    elseif command == "status" then
        local connection = iRL:GetConnection()
        if connection then iRL:Print("Connected to " .. connection.guildName .. ".") else iRL:Print("No guild connection. Join a guild to use iRacelockConnection.") end
    else
        iRL:Print("/irc - achievements | /irc inspect <name> | /irc guild | /irc options | /irc status")
    end
end
