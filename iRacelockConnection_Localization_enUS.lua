local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

-- English is the current source locale.  All player-facing text belongs here
-- so further locales can be added without changing addon logic.
local C = iRC.Colors
iRC.L = {
    ADDON_PREFIX = C.iRC .. "[iRC]: " .. C.Reset,
    LOADED = C.iRC .. "%s " .. C.Green .. "v%s" .. C.Reset .. " Loaded.",

    -- Mirrors iWR: severity uses its own colour, then the addon identity is
    -- always shown in iRC orange before the message.
    DEBUG_INFO = C.White .. "INFO: " .. C.iRC .. "[iRC]: ",
    DEBUG_WARNING = C.Yellow .. "WARNING: " .. C.iRC .. "[iRC]: ",
    DEBUG_ERROR = C.Red .. "ERROR: " .. C.iRC .. "[iRC]: ",
    DEBUG_RESET = C.Reset,
    DEBUG_MODE = "Debug Mode is activated." .. C.Red .. " This is not recommended for common use and will cause message spam.",
    ENABLE_DEBUG_MODE = "Enable Debug Mode",
    ENABLE_DEBUG_MODE_DESC = C.Gray .. "Enables verbose debug messages in chat. Not recommended for normal use." .. C.Reset,
    DEVELOPER_HEADER = "Developer",

    PRESENCE_POLL_SENT = "Presence poll sent to the guild.",
    PRESENCE_POLL_RECEIVED = "Presence poll received from %s; sending live profile.",
    PROFILE_SENT = "Live profile shared with the guild.",
    PROFILE_RECEIVED = "Live profile received from %s.",
    RULES_SENT = "Guild rules broadcast by Guild Master.",
    RULES_RECEIVED = "Guild rules received from %s.",
    PRESENCE_NOTIFICATION_LEADER = "This officer client is the active presence-notification leader.",
    PRESENCE_NOTIFICATION_NOT_LEADER = "Another eligible officer client handles presence notifications.",
    PRESENCE_MISMATCH = "%s has no verified live addon response (%s).",
    PRESENCE_RECOVERED = "%s is verified again; clearing the presence warning.",
    PRESENCE_NO_LIVE_RESPONSE = "No live response",
    PRESENCE_OFFICER_NOTICE = "[iRC] %s is online but iRacelockConnection is not currently verified (%s).",
    PRESENCE_OFFICER_ESCALATION = "[iRC] %s remains online without a verified iRacelockConnection response after five minutes (%s).",
    PRESENCE_PLAYER_NOTICE = "[iRacelockConnection] You are online, but iRC cannot detect a live addon response. Please enable or reload the addon.",
    PRESENCE_PLAYER_ESCALATION = "[iRacelockConnection] iRC still cannot detect a live addon response after five minutes. Please enable or reload the addon.",
    PRESENCE_GUILD_ESCALATION = "[iRC] %s has been online without a verified iRacelockConnection response for five minutes. Please enable or reload the addon.",
    NEW_MEMBER_CHECK = "Checking whether newly joined member %s has a live addon response.",
    NEW_MEMBER_WELCOME = "[iRC] Welcome to the guild, %s! iRacelockConnection is used here for shared race progress and guild verification. It is not currently detected on your character; please install, enable, or reload iRC.",

    RACEGRID_CHANNEL_JOIN = "Joining external race data channel %s.",
    RACEGRID_EXTERNAL_CHANNEL_READY = "External race data channel %s is ready and hidden from chat windows.",
    RACEGRID_OWN_CHANNEL_JOIN = "Joining the iRC global race data channel.",
    RACEGRID_OWN_CHANNEL_UNAVAILABLE = "The iRC global race data channel is not ready; no public iRC report was sent.",
    RACEGRID_INITIALIZED = "Race Overview initialized. Public iRC sharing is %s; RaceLocked and ForkEU channels are read-only inputs.",
    RACEGRID_SHARING_ENABLED = "enabled",
    RACEGRID_SHARING_DISABLED = "disabled",
    RACEGRID_NO_GUILD = "-",
    RACEGRID_REPORT_SENT = "Sent iRC race report: %s, %s, level %d, guild %s.",
    RACEGRID_REQUEST_SENT = "Requested current iRC race reports from the global channel.",
    RACEGRID_REQUEST_RECEIVED = "Received a global race-report request from %s; sending this client's report.",
    RACEGRID_IRC_REPORT_RECEIVED = "Received iRC race report from %s: %s, level %d, guild %s.",
    RACEGRID_REPORT_RECEIVED = "Received %s race overview report: %s, %d member(s), average level %s.",
    RACEGRID_SUMMARY = "Race Overview assembled: %d race group(s), %d external guild report(s), source: %s.",
    RACEGRID_UNSUPPORTED_RACE = "Skipped Race Overview data with an unsupported race value: %s.",

    COMMAND_CONNECTED = "Connected to %s.",
    COMMAND_NOT_CONNECTED = "No guild connection. Join a guild to use iRacelockConnection.",
    COMMAND_HELP = "/irc - achievements | /irc inspect <name> | /irc guild | /irc options | /irc status",
    ACHIEVEMENT_EARNED = "Achievement earned: |cffffff00%s|r",
    ACHIEVEMENT_WINDOW_RESET = "Achievement window position reset.",
    CONNECTION_STATUS_BROADCAST = "Guild connection status broadcast.",
    GUILD_FOUND_RESTRICTION = "Guild Found restriction: %s",
    SELF_FOUND_REQUIRED_WARNING = "SELF-FOUND REQUIRED: This character is not in Self-Found mode.",
    GUILD_FOUND_TRADE_CANCELLED = "Trade with %s was cancelled. %s",
    GUILD_FOUND_TRADE_REASON = "Only verified guild members may trade in Guild Found.",
    GUILD_FOUND_MAIL_BLOCKED = "Mail to %s is blocked. %s",
    GUILD_FOUND_MAIL_REASON = "Only verified guild members may receive Guild Found mail.",
    GUILD_FOUND_AUCTION_HOUSE_CLOSED = "Auction House was closed. Level 60 Guild Found permits item exchange with guild members only.",
    SAME_RACE_GROUP_LEAVE = "I am race-locked and must leave this group because Same-race groups only is active.",
    GUILD_FOUND_GROUP_LEAVE = "I am Guild Found at level 60 and can only group with guild members.",
    HCA_UNAVAILABLE = "HardcoreAchievements is not available.",
    HCA_NOT_READY = "HardcoreAchievements is loaded, but its achievement tab is not ready yet. Reload once and try again.",
}
