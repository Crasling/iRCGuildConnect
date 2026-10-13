local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

-- Guild milestones and chat identity icons
--
-- Rule-controlled announcements are sent to guild chat. The separate public
-- icon protocol lets nearby iRC users decorate names without exposing private
-- guild profile data.

local Announcements = {}
iRC.GuildAnnouncements = Announcements
local ICON_PREFIX = "iRCIconV1"
local ICON_WIRE_VERSION = "1"
local PUBLIC_ICON_TTL = 30
local PUBLIC_REQUEST_COOLDOWN = 300
local publicIcons, pendingRequests, queuedRequests, queuedNames = {}, {}, {}, {}
local lastReplyAt = {}
local lastPublicRequestAt, requestTimerPending = 0, false

Announcements.Icons = {
    death = "Interface\\AddOns\\iRC\\Images\\Icons\\Skull_Icon.blp",
    level60 = "Interface\\AddOns\\iRC\\Images\\Icons\\Sixty_Icon.blp",
    selfFound = "Interface\\AddOns\\iRC\\Images\\Icons\\SF_Icon.blp",
    guildFound = "Interface\\AddOns\\iRC\\Images\\Icons\\GF_Icon.blp",
    guildMaster = "Interface\\AddOns\\iRC\\Images\\Icons\\GM_Icon.blp",
    creator = "Interface\\AddOns\\iRC\\Images\\Icons\\The_Creator_Quill_256.blp",
    officer1 = "Interface\\AddOns\\iRC\\Images\\Icons\\Officer1_Icon.blp",
    violation = "Interface\\AddOns\\iRC\\Images\\Icons\\X_Icon.blp",
}

-- Only one earned badge is placed before a normal chat message. Safety states
-- take priority over cosmetic or rank badges.
local DEFAULT_ICON_PRIORITY = {
    "death", "violation", "creator", "guildMaster",
    "officer1", "selfFound", "guildFound",
}

local rosterReference, rosterGuildKey, rosterRanks, rosterMembers = nil, nil, {}, {}

-- Icon eligibility ----------------------------------------------------------

-- Death is a Hardcore identity state, not a general "currently unable to act"
-- state. Keeping this check in one place prevents ordinary realm deaths from
-- leaking into chat badges through local, guild, or public profile data.
local function isHardcoreDeathProfile(profile)
    return iRC:IsOfficialHardcoreRealm()
        and type(profile) == "table"
        and type(profile.guid) == "string"
        and profile.guid ~= ""
        and profile.deadGuid == profile.guid
end

local function sanitizePublicIconKind(kind, name)
    if kind == "death" and not iRC:IsOfficialHardcoreRealm() then return "none" end
    if kind == "creator" and not iRC:IsTestAdminName(name) then return "none" end
    return kind
end

local function publicNameKey(name)
    if type(name) ~= "string" or name == "" then return nil end
    if iRC:IsForeverClient() then
        local key = iRC:NormalizeName(name)
        return key ~= "" and key or nil
    end
    local character, realm = name:match("^([^-]+)%-(.+)$")
    if not character then character, realm = name, GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName and GetRealmName() end
    realm = tostring(realm or ""):gsub("%s+", "")
    if character == "" or realm == "" then return nil end
    return (character .. "-" .. realm):lower()
end

local function getRosterRank(name)
    local guildKey = iRC:GetGuildKey()
    if not guildKey or not iRC.GetGuildRosterSnapshot then return nil end
    local roster = iRC:GetGuildRosterSnapshot()
    if roster ~= rosterReference or guildKey ~= rosterGuildKey then
        rosterReference, rosterGuildKey, rosterRanks, rosterMembers = roster, guildKey, {}, {}
        for _, member in ipairs(roster) do
            local memberKey = publicNameKey(member.name)
            if memberKey then
                rosterRanks[memberKey] = member.rankIndex
                rosterMembers[memberKey] = member
            end
        end
    end
    return rosterRanks[publicNameKey(name)]
end

local function getRosterMember(name)
    getRosterRank(name)
    return rosterMembers[publicNameKey(name)]
end

function Announcements:GetUnlockedIcons(name)
    local unlocked = {}
    if type(name) ~= "string" or name == "" then return unlocked end
    if iRC:IsTestAdminName(name) then unlocked.creator = true end
    local key = iRC:NormalizeName(name)
    local isSelf = key == iRC:NormalizeName(iRC:GetPlayerName())
    local rank = getRosterRank(name)
    local connection = rank ~= nil and iRC:GetConnection() or nil
    local profile = isSelf and iRC:GetLocalProfile() or connection and connection.members and connection.members[key]
    if isHardcoreDeathProfile(profile) then unlocked.death = true end
    if rank == nil then
        if isSelf and iRCCharDB and iRCCharDB.hideChatIcon == true and not unlocked.death then return {} end
        return unlocked
    end
    local guildMasterRank = math.max(0, math.min(9,
        math.floor(tonumber(connection and connection.guildMasterRank) or 0)))
    if rank == 0 or guildMasterRank > 0 and rank <= guildMasterRank then
        unlocked.guildMaster = true
    else
        if connection and connection.active == true then
            for permission, defaultRank in pairs(iRC.DefaultRankPermissions) do
                local delegatedRank = tonumber(connection.rankPermissions and connection.rankPermissions[permission]) or defaultRank
                if rank <= delegatedRank then
                    unlocked.officer1 = true
                    break
                end
            end
        end
    end
    if isSelf and profile and profile.selfFound == true and profile.hideChatIcon ~= true then unlocked.selfFound = true end
    if not connection or connection.active ~= true then
        return profile and profile.hideChatIcon == true and not unlocked.death and {} or unlocked
    end
    local fresh = profile and (isSelf or time() - (tonumber(profile.lastSeen) or 0) <= 180)
    local status = iRC.RaceLockedSync and iRC.RaceLockedSync:GetStatus(name, connection)
    local rules = connection.rules or iRC.DefaultConnectionRules
    local mode = iRC:GetProgressionMode(rules)
    local guildFoundVerified = status and status.verified == true
    local guildFoundApplies = iRC:IsGuildFoundProgressionApplicable(profile and profile.level, profile and profile.selfFound, rules)
    if guildFoundApplies and status and status.clean == false then unlocked.violation = true end
    if fresh and profile.currentGroupRuleViolation then unlocked.violation = true end
    if fresh and profile.race and iRC:GetGuildMemberRaceCheck(profile.race, connection).mismatch then
        unlocked.violation = true
    end
    if fresh and profile.class and iRC:GetGuildMemberClassCheck(profile.class, connection).mismatch then
        unlocked.violation = true
    end
    local personalBank = iRC.Identity and iRC.Identity:IsPersonalBank(name)
    if fresh and not personalBank then
        local level = tonumber(profile.level) or 0
        if (mode == "SELF_FOUND" and level < 60 and profile.selfFound ~= true)
            or (mode == "SELF_FOUND" and level >= 60 and iRC:GetMaxLevelProgressionMode(rules) == "GUILD_FOUND" and not guildFoundVerified)
            or (mode == "GUILD_FOUND" and not guildFoundVerified)
            or (mode == "SELF_FOUND_OR_GUILD_FOUND" and profile.selfFound ~= true and not guildFoundVerified) then
            unlocked.violation = true
        end
    end
    -- A rule-violation badge is not an optional earned icon.
    if profile and profile.hideChatIcon == true then
        if unlocked.death then return { death = true } end
        return unlocked.violation and { violation = true } or {}
    end
    if profile and profile.selfFound == true and fresh then
        unlocked.selfFound = true
    end
    if guildFoundApplies and guildFoundVerified then unlocked.guildFound = true end
    return unlocked
end

function Announcements:SetHidden(hidden)
    iRCCharDB = iRCCharDB or {}
    iRCCharDB.hideChatIcon = hidden and true or false
    if iRC:IsGuildConnectionActive() then iRC:SendHello() end
end

function Announcements:GetDefaultChatIcon(name)
    local unlocked = self:GetUnlockedIcons(name)
    for _, kind in ipairs(DEFAULT_ICON_PRIORITY) do
        if unlocked[kind] then return self.Icons[kind], kind end
    end
end

-- Public icon request/reply protocol ---------------------------------------

local function sendIconWire(message, target)
    return iRC:SendAddonTraffic(ICON_PREFIX, message, "WHISPER", target)
end

local function processPublicRequests()
    requestTimerPending = false
    local request = table.remove(queuedRequests, 1)
    if not request then return end
    queuedNames[request.key] = nil
    local now = GetTime and GetTime() or 0
    local delay = math.max(0, 2 - (now - lastPublicRequestAt))
    if delay > 0 and C_Timer and C_Timer.After then
        table.insert(queuedRequests, 1, request)
        queuedNames[request.key] = true
        requestTimerPending = true
        C_Timer.After(delay, processPublicRequests)
        return
    end
    lastPublicRequestAt = now
    if pendingRequests[request.key] and pendingRequests[request.key] > time() then
        sendIconWire("ICON_REQ\t" .. ICON_WIRE_VERSION, request.name)
    end
    if #queuedRequests > 0 and C_Timer and C_Timer.After then
        requestTimerPending = true
        C_Timer.After(2, processPublicRequests)
    end
end

local function requestPublicIcon(name)
    local key = publicNameKey(name)
    if not key or queuedNames[key] or #queuedRequests >= 40 then return end
    local now = time()
    if not Announcements.lastPublicCachePrune or now - Announcements.lastPublicCachePrune >= 60 then
        Announcements.lastPublicCachePrune = now
        for cachedKey, entry in pairs(publicIcons) do
            if entry.expiresAt <= now then publicIcons[cachedKey] = nil end
        end
        for pendingKey, expiresAt in pairs(pendingRequests) do
            if expiresAt <= now then pendingRequests[pendingKey] = nil end
        end
        for replyKey, repliedAt in pairs(lastReplyAt or {}) do
            if now - repliedAt > 600 then lastReplyAt[replyKey] = nil end
        end
    end
    if pendingRequests[key] and pendingRequests[key] > now then return end
    if publicIcons[key] and publicIcons[key].expiresAt > now then return end
    pendingRequests[key] = now + PUBLIC_REQUEST_COOLDOWN
    queuedNames[key] = true
    queuedRequests[#queuedRequests + 1] = { key = key, name = name }
    if not requestTimerPending then
        requestTimerPending = true
        if C_Timer and C_Timer.After then C_Timer.After(0.1, processPublicRequests) else processPublicRequests() end
    end
end

function Announcements:GetPublicChatIcon(name)
    local key = publicNameKey(name)
    local entry = key and publicIcons[key]
    if entry and entry.expiresAt > time() then
        local kind = sanitizePublicIconKind(entry.kind, name)
        if kind == "none" then
            publicIcons[key] = nil
            return nil
        end
        return self.Icons[kind], kind
    end
    requestPublicIcon(name)
end

function Announcements:ReceiveIconWire(message, distribution, sender)
    if distribution ~= "WHISPER" or type(message) ~= "string" or not sender then return end
    local kind, version, value = strsplit("\t", message)
    if version ~= ICON_WIRE_VERSION then return end
    local key = publicNameKey(sender)
    if not key or key == publicNameKey(iRC:GetPlayerName()) then return end
    if kind == "ICON_REQ" then
        local now = time()
        if now - (lastReplyAt[key] or 0) < 10 then return end
        lastReplyAt[key] = now
        local _, ownKind = self:GetDefaultChatIcon(iRC:GetPlayerName())
        sendIconWire("ICON_STATUS\t" .. ICON_WIRE_VERSION .. "\t" .. (ownKind or "none"), sender)
    elseif kind == "ICON_STATUS" and pendingRequests[key] and pendingRequests[key] > time() then
        if value ~= "none" and not self.Icons[value] then return end
        -- Remote clients may claim an icon, but this client decides whether
        -- that claim is valid for the sender and the current realm.
        value = sanitizePublicIconKind(value, sender)
        pendingRequests[key] = nil
        publicIcons[key] = { kind = value, expiresAt = time() + PUBLIC_ICON_TTL }
    end
end

local ICON_HELP = {
    creator = { "CHAT_ICON_CREATOR_TITLE", "CHAT_ICON_CREATOR_DESC" },
    death = { "CHAT_ICON_DEATH_TITLE", "CHAT_ICON_DEATH_DESC" },
    level60 = { "CHAT_ICON_LEVEL60_TITLE", "CHAT_ICON_LEVEL60_DESC" },
    selfFound = { "CHAT_ICON_SELF_FOUND_TITLE", "CHAT_ICON_SELF_FOUND_DESC" },
    guildFound = { "CHAT_ICON_GUILD_FOUND_TITLE", "CHAT_ICON_GUILD_FOUND_DESC" },
    guildMaster = { "CHAT_ICON_GUILD_MASTER_TITLE", "CHAT_ICON_GUILD_MASTER_DESC" },
    officer1 = { "CHAT_ICON_OFFICER_TITLE", "CHAT_ICON_OFFICER_DESC" },
    violation = { "CHAT_ICON_VIOLATION_TITLE", "CHAT_ICON_VIOLATION_DESC" },
}

-- Chat rendering ------------------------------------------------------------

local function iconLink(kind, icon)
    return string.format("|Haddon:iRCIcon:%s|h|T%s:0:0|t|h", kind, icon)
end

local function altIdentityLink(author)
    if iRCCharDB and iRCCharDB.showLinkedMainsInChat == false then return nil end
    if not (iRC.Identity and iRC.Identity.GetIdentityLabel
        and iRC.Identity.GetMainCharacterName) then return nil end
    local label = iRC.Identity:GetIdentityLabel(author)
    if type(label) ~= "string" or label == "Main" or label:find("^Pending")
        or not label:find("Alt of", 1, true) then return nil end
    local mainName = iRC.Identity:GetMainCharacterName(author)
    if type(mainName) ~= "string" or mainName == ""
        or iRC:NormalizeName(mainName) == iRC:NormalizeName(author) then return nil end
    mainName = iRC:FormatPlayerName(mainName):gsub("[%c|:]", ""):sub(1, 80)
    if mainName == "" then return nil end
    local bankAlt = label:find("Personal Bank Alt", 1, true) ~= nil
    local kind, color = bankAlt and "BankAlt" or "Alt", bankAlt and "66ccff" or "b38cff"
    return string.format("|Haddon:iRCIdentity:%s:%s|h|cff%s[%s]|r|h", kind, mainName, color, kind)
end

local hookedChatFrames = {}
local activeTooltipChatFrame
local tooltipMouseWasEnabled
local function hideChatIconTooltip(chatFrame)
    if activeTooltipChatFrame ~= chatFrame then return end
    activeTooltipChatFrame = nil
    if GameTooltip and GameTooltip.iRCChatIconOwner == chatFrame then
        GameTooltip.iRCChatIconOwner = nil
        GameTooltip:Hide()
        if tooltipMouseWasEnabled ~= nil then GameTooltip:EnableMouse(tooltipMouseWasEnabled) end
    end
    tooltipMouseWasEnabled = nil
end
local function hookChatTooltip(chatFrame)
    if not chatFrame or not chatFrame.HookScript or hookedChatFrames[chatFrame] then return end
    hookedChatFrames[chatFrame] = true
    chatFrame:HookScript("OnHyperlinkEnter", function(self, link)
        local identityKind, mainName
        if type(link) == "string" then
            identityKind, mainName = link:match("^addon:iRCIdentity:(%w+):(.+)$")
        end
        if mainName and mainName ~= "" and GameTooltip then
            activeTooltipChatFrame = self
            GameTooltip.iRCChatIconOwner = self
            if tooltipMouseWasEnabled == nil and GameTooltip.IsMouseEnabled then
                tooltipMouseWasEnabled = GameTooltip:IsMouseEnabled()
            end
            GameTooltip:EnableMouse(false)
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            local bankAlt = identityKind == "BankAlt"
            GameTooltip:SetText(bankAlt and "Personal Bank Alt" or "Alt character",
                bankAlt and 0.40 or 0.70, bankAlt and 0.80 or 0.55, 1.00)
            local member = getRosterMember(mainName)
            local classColor = member and member.classFile and RAID_CLASS_COLORS
                and RAID_CLASS_COLORS[member.classFile]
            GameTooltip:AddLine(mainName, classColor and classColor.r or 1,
                classColor and classColor.g or 1, classColor and classColor.b or 1, true)
            if member then
                GameTooltip:AddLine("Level " .. tostring(member.level or "?") .. " "
                    .. tostring(member.className or "Unknown") .. "  -  "
                    .. tostring(member.rankName or "Unknown rank"), 0.78, 0.78, 0.78, true)
            else
                GameTooltip:AddLine("Main character", 0.78, 0.78, 0.78, true)
            end
            GameTooltip:Show()
            return
        end
        local kind = type(link) == "string" and link:match("^addon:iRCIcon:(%w+)$")
        local help = kind and ICON_HELP[kind]
        if not help or not GameTooltip then
            hideChatIconTooltip(self)
            return
        end
        activeTooltipChatFrame = self
        GameTooltip.iRCChatIconOwner = self
        if tooltipMouseWasEnabled == nil and GameTooltip.IsMouseEnabled then
            tooltipMouseWasEnabled = GameTooltip:IsMouseEnabled()
        end
        GameTooltip:EnableMouse(false)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText(iRC:Text(help[1]), 1, 0.72, 0.22)
        GameTooltip:AddLine(iRC:Text(help[2]), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    chatFrame:HookScript("OnHyperlinkLeave", hideChatIconTooltip)
end

-- Guild announcements -------------------------------------------------------

local function canAnnounce(ruleKey)
    if not SendChatMessage or not iRC:IsGuildConnectionActive() or iRC:IsGuildConnectionBootstrap() then return false end
    local rules = iRC:GetConnectionRules()
    return rules and rules[ruleKey] == true
end

function Announcements:AnnounceDeath()
    if not iRC:IsOfficialHardcoreRealm() or not canAnnounce("enableGuildDeathMessage") then return false end
    iRCCharDB = iRCCharDB or {}
    local now = time()
    if now - (tonumber(iRCCharDB.lastGuildDeathAnnouncementAt) or 0) < 30 then return false end
    iRCCharDB.lastGuildDeathAnnouncementAt = now
    return pcall(SendChatMessage, iRC:Text("CHAT_ANNOUNCE_DEATH"), "GUILD")
end

function Announcements:AnnounceLevelMilestone(level)
    level = math.floor(tonumber(level) or 0)
    local rules = iRC:GetConnectionRules()
    local minimum = math.max(10, math.min(60,
        math.floor((tonumber(rules and rules.guildLevelAnnouncementMinimum) or 60) / 10) * 10))
    if level < minimum or level % 10 ~= 0 or not canAnnounce("enableGuildLevel60Message") then return false end
    iRCCharDB = iRCCharDB or {}
    iRCCharDB.guildLevelAnnouncementsSent = iRCCharDB.guildLevelAnnouncementsSent or {}
    if level == 60 and iRCCharDB.guildLevel60AnnouncementSent then
        iRCCharDB.guildLevelAnnouncementsSent[60] = true
    end
    if iRCCharDB.guildLevelAnnouncementsSent[level] then return false end
    local sent = pcall(SendChatMessage, iRC:Text("CHAT_ANNOUNCE_LEVEL", level), "GUILD")
    if sent then
        iRCCharDB.guildLevelAnnouncementsSent[level] = true
        if level == 60 then iRCCharDB.guildLevel60AnnouncementSent = true end
        iRC:DebugMsg("Guild level announcement sent for level " .. tostring(level) .. ".", 3)
    end
    return sent
end

function Announcements:CheckProfessionMilestones(skills, names)
    if type(skills) ~= "table" then return false end
    iRCCharDB = iRCCharDB or {}
    local observed = iRCCharDB.guildProfessionAnnouncementObservedSkills
    if type(observed) ~= "table" then
        observed = {}
        iRCCharDB.guildProfessionAnnouncementObservedSkills = observed
        for professionID, rank in pairs(skills) do observed[professionID] = tonumber(rank) or 0 end
        return false
    end
    local rules = iRC:GetConnectionRules()
    local firstMilestone = math.max(75, math.min(300,
        math.floor((tonumber(rules and rules.guildProfessionAnnouncementSkill) or 300) / 75) * 75))
    iRCCharDB.guildProfessionAnnouncementsSent = iRCCharDB.guildProfessionAnnouncementsSent or {}
    local sentAny = false
    for professionID, rank in pairs(skills) do
        professionID, rank = tonumber(professionID), math.floor(tonumber(rank) or 0)
        local previous = tonumber(observed[professionID])
        local primary = professionID and professionID ~= 185 and professionID ~= 356 and professionID ~= 129
        if primary and previous then
            for milestone = firstMilestone, 300, 75 do
                local announcementKey = tostring(professionID) .. ":" .. tostring(milestone)
                if previous < milestone and rank >= milestone
                    and not iRCCharDB.guildProfessionAnnouncementsSent[announcementKey]
                    and canAnnounce("enableGuildProfessionMessage") then
                    local name = type(names) == "table" and names[professionID] or tostring(professionID)
                    local sent = pcall(SendChatMessage,
                        iRC:Text("CHAT_ANNOUNCE_PROFESSION", milestone, tostring(name or professionID)), "GUILD")
                    if sent then
                        iRCCharDB.guildProfessionAnnouncementsSent[announcementKey] = true
                        sentAny = true
                        iRC:DebugMsg("Guild profession announcement sent for " .. tostring(name or professionID)
                            .. " at skill " .. tostring(milestone) .. ".", 3)
                    end
                end
            end
        end
        observed[professionID] = rank
    end
    return sentAny
end

function Announcements:SendTest(kind)
    if not iRC:IsTestAdmin() or not iRC:IsGuildConnectionActive() or not SendChatMessage then return false end
    if kind == "death" and not iRC:IsOfficialHardcoreRealm() then return false end
    local message = kind == "death" and iRC:Text("CHAT_ANNOUNCE_TEST_DEATH") or kind == "level60" and iRC:Text("CHAT_ANNOUNCE_TEST_LEVEL60")
    if not message then return false end
    return pcall(SendChatMessage, message, "GUILD")
end

local function addGuildAnnouncementIcon(chatFrame, _, message, author, ...)
    if iRC:IsSecretValue(message) or iRC:IsSecretValue(author) then return false end
    if type(message) ~= "string" or not author or author == "" then return false end
    local icon, iconKind
    if iRC:IsOfficialHardcoreRealm()
        and (message == iRC:Text("CHAT_ANNOUNCE_DEATH") or message == iRC:Text("CHAT_ANNOUNCE_TEST_DEATH")) then
        icon, iconKind = Announcements.Icons.death, "death"
    elseif message == iRC:Text("CHAT_ANNOUNCE_LEVEL", 60) or message == iRC:Text("CHAT_ANNOUNCE_LEVEL60")
        or message == iRC:Text("CHAT_ANNOUNCE_TEST_LEVEL60") then icon, iconKind = Announcements.Icons.level60, "level60" end
    local hideAll = iRCCharDB and iRCCharDB.hideAllChatIcons == true
    local identity = altIdentityLink(author)
    if hideAll and not icon and not identity then return false end
    local badge, badgeKind
    if not hideAll then
        badge, badgeKind = Announcements:GetDefaultChatIcon(author)
        if not badge and getRosterRank(author) == nil then
            badge, badgeKind = Announcements:GetPublicChatIcon(author)
        end
    end
    if icon and iconKind ~= badgeKind then message = message .. " " .. iconLink(iconKind, icon) end
    if badge then message = iconLink(badgeKind, badge) .. " " .. message end
    if identity then message = identity .. " " .. message end
    if not icon and not badge and not identity then return false end
    hookChatTooltip(chatFrame)
    return false, message, author, ...
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_DEAD")
frame:RegisterEvent("PLAYER_ALIVE")
frame:RegisterEvent("PLAYER_UNGHOST")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("CHAT_MSG_ADDON")
local deathStateSharePending = false
-- Lifecycle hooks -----------------------------------------------------------

local function shareCurrentDeathState()
    if not iRC:IsOfficialHardcoreRealm() then return end
    if deathStateSharePending then return end
    local function sendProfile()
        deathStateSharePending = false
        if iRC:IsGuildConnectionActive() then iRC:SendHello() end
    end
    if C_Timer and C_Timer.After then
        deathStateSharePending = true
        C_Timer.After(0.2, sendProfile)
    else
        sendProfile()
    end
end
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(ICON_PREFIX)
        end
        if ChatFrame_AddMessageEventFilter then
            for _, chatEvent in ipairs({
                "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
                "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
                "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
            }) do
                ChatFrame_AddMessageEventFilter(chatEvent, addGuildAnnouncementIcon)
            end
        end
    elseif event == "PLAYER_DEAD" then
        shareCurrentDeathState()
        Announcements:AnnounceDeath()
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        shareCurrentDeathState()
    elseif event == "PLAYER_LEVEL_UP" then
        Announcements:AnnounceLevelMilestone(...)
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, distribution, sender = ...
        if iRC:HasSecretValues(prefix, message, distribution, sender) then return end
        if prefix == ICON_PREFIX
            and iRC:AcceptIncomingAddonTraffic(prefix, message, distribution, sender, "chat-icons") then
            Announcements:ReceiveIconWire(message, distribution, sender)
        end
    end
end)
