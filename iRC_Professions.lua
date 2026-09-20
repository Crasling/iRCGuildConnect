local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local Professions = {}
iRC.Professions = Professions
local ORDER = {
    { 171, "Alchemy" }, { 164, "Blacksmithing" }, { 333, "Enchanting" },
    { 202, "Engineering" }, { 182, "Herbalism" }, { 165, "Leatherworking" },
    { 186, "Mining" }, { 393, "Skinning" }, { 197, "Tailoring" },
    { 185, "Cooking" }, { 356, "Fishing" }, { 129, "First Aid" },
}
local byName, byID = {}, {}
for _, entry in ipairs(ORDER) do byName[entry[2]:lower()], byID[entry[1]] = entry[1], entry[2] end
local transfers = {}
local lastSummaryWire, lastSummaryGuild, pendingUpdate, sentCachedRecipes
local sharingReadyAt = 0
local CHUNK_SIZE, MAX_CHUNKS = 165, 64

local function localData()
    iRCCharDB = iRCCharDB or {}
    iRCCharDB.professionSnapshot = iRCCharDB.professionSnapshot or { skills = {}, recipes = {} }
    return iRCCharDB.professionSnapshot
end

local function digest(value)
    local a, b = 1, 0
    for index = 1, #value do
        a = (a + value:byte(index)) % 65521
        b = (b + a) % 65521
    end
    return string.format("%08x", b * 65536 + a)
end

local function escape(value)
    return tostring(value or ""):gsub("([^%w _%-])", function(char) return string.format("%%%02X", char:byte()) end)
end

local function unescape(value)
    return (value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

function Professions:GetOptions() return ORDER end
function Professions:GetName(id) return byID[tonumber(id)] or "Unknown profession" end

local function isFishingRod(itemID)
    itemID = tonumber(itemID)
    if not itemID then return false end
    if C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
        local fishingSubclass = Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole or 20
        if classID == 2 and subclassID == fishingSubclass then return true end
    end
    return false
end

local function carriedFishingRod()
    local equipped = GetInventoryItemID and GetInventoryItemID("player", INVSLOT_MAINHAND or 16)
    if not equipped and GetInventoryItemLink then
        local link = GetInventoryItemLink("player", INVSLOT_MAINHAND or 16)
        equipped = link and tonumber(link:match("item:(%d+)"))
    end
    if isFishingRod(equipped) then return equipped end
    if not (C_Container and C_Container.GetContainerNumSlots) then return nil end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local itemID = C_Container.GetContainerItemID and C_Container.GetContainerItemID(bag, slot)
            if not itemID and C_Container.GetContainerItemInfo then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                itemID = info and info.itemID
            end
            if isFishingRod(itemID) then return itemID end
        end
    end
end

function Professions:CollectSkills()
    local data = localData()
    local found = {}
    if GetProfessions and GetProfessionInfo then
        local indices = { GetProfessions() }
        for slot = 1, select("#", GetProfessions()) do
            local index = indices[slot]
            if index then
                local name, _, rank, _, _, _, skillLine = GetProfessionInfo(index)
                local id = tonumber(skillLine) or byName[tostring(name or ""):lower()]
                if id and byID[id] then found[id] = math.max(0, tonumber(rank) or 0) end
            end
        end
    end
    data.skills = found
    data.fishingRodID = found[356] and carriedFishingRod() or nil
    for id in pairs(data.recipes or {}) do
        if not found[id] or id == 129 or id == 356 then
            data.recipes[id] = nil
            if data.recipeUpdatedAt then data.recipeUpdatedAt[id] = nil end
        end
    end
    data.guid = UnitGUID("player") or ""
    data.updatedAt = time()
    return data
end

function Professions:SendSummary(force)
    local data = self:CollectSkills()
    if GetTime and GetTime() < sharingReadyAt then return false end
    if not iRC:IsGuildConnectionActive() then return false end
    local fields = {}
    for _, entry in ipairs(ORDER) do
        local rank = data.skills[entry[1]]
        if rank then fields[#fields + 1] = entry[1] .. ":" .. math.floor(rank) end
    end
    local wire = table.concat(fields, ",")
    local rodID = tonumber(data.fishingRodID) or 0
    local guildKey = iRC:GetGuildKey()
    if guildKey ~= lastSummaryGuild then sentCachedRecipes = nil end
    if not force and wire .. ":" .. rodID == lastSummaryWire and guildKey == lastSummaryGuild then return false end
    local message = table.concat({ "PROF_SUM", "2", data.guid, data.updatedAt, wire, rodID }, "\t")
    if iRC:SendAddonTraffic(iRC.Prefix, message, "GUILD") then
        lastSummaryWire = wire .. ":" .. rodID
        lastSummaryGuild = guildKey
        local connection = iRC:GetConnection()
        if connection then
            connection.professionMembers = connection.professionMembers or {}
            connection.professionMembers[iRC:NormalizeName(iRC:GetPlayerName())] = data
            if iRC.InvalidateGuildMemberRow then iRC:InvalidateGuildMemberRow(iRC:GetPlayerName()) end
        end
        if not sentCachedRecipes then
            sentCachedRecipes = true
            self:SendKnownRecipes()
        end
        return true
    end
    return false
end

local function sendRecipeChunks(id, data)
    if id == 129 or id == 356 then return end
    if not iRC:IsGuildConnectionActive() then return end
    local recipes = data.recipes and data.recipes[id]
    if not recipes then return end
    local encoded = {}
    for _, recipe in ipairs(recipes) do encoded[#encoded + 1] = escape(recipe) end
    local payload = table.concat(encoded, ";")
    if #payload > CHUNK_SIZE * MAX_CHUNKS then return end
    local stamp = tonumber(data.recipeUpdatedAt and data.recipeUpdatedAt[id]) or time()
    local hash = digest(data.guid .. ":" .. id .. ":" .. stamp .. ":" .. payload)
    local total = math.max(1, math.ceil(#payload / CHUNK_SIZE))
    for index = 1, total do
        local chunk = payload:sub((index - 1) * CHUNK_SIZE + 1, index * CHUNK_SIZE)
        local message = table.concat({ "PROF_REC", "1", data.guid, id, stamp, index, total, hash, chunk }, "\t")
        if index == 1 or not C_Timer or not C_Timer.After then
            iRC:SendAddonTraffic(iRC.Prefix, message, "GUILD")
        else
            C_Timer.After((index - 1) * 0.08, function()
                if iRC:IsGuildConnectionActive() then iRC:SendAddonTraffic(iRC.Prefix, message, "GUILD") end
            end)
        end
    end
end

function Professions:SendKnownRecipes()
    local data = localData()
    for id in pairs(data.recipes or {}) do sendRecipeChunks(id, data) end
end

local function knownProfessionID(value)
    if type(value) == "table" then
        local id = tonumber(value.professionID or value.parentProfessionID or value.skillLineID)
        if byID[id] then return id end
        return byName[tostring(value.professionName or value.name or ""):lower()]
    end
    local id = tonumber(value)
    return byID[id] and id or nil
end

local function professionForRecipe(recipeID, recipeInfo)
    local id = knownProfessionID(recipeInfo)
    if id then return id end
    if C_TradeSkillUI.GetProfessionInfoByRecipeID then
        local first, second = C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)
        id = knownProfessionID(first) or knownProfessionID(second)
        if id then return id end
        id = byName[tostring(second or ""):lower()]
        if id then return id end
    end
    if C_TradeSkillUI.GetTradeSkillLineForRecipe then
        local first, second = C_TradeSkillUI.GetTradeSkillLineForRecipe(recipeID)
        id = knownProfessionID(first) or knownProfessionID(second)
        if id then return id end
    end
end

function Professions:CollectOpenRecipes()
    if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo) then return end
    local grouped, seen = {}, {}
    for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if recipeInfo and recipeInfo.learned and not recipeInfo.isHeader then
            local id = professionForRecipe(recipeID, recipeInfo)
            if id and id ~= 129 and id ~= 356 then
                grouped[id], seen[id] = grouped[id] or {}, seen[id] or {}
                local key = "S" .. tostring(recipeID)
                if not seen[id][key] then
                    seen[id][key] = true
                    grouped[id][#grouped[id] + 1] = key
                end
            end
        end
    end
    local data = localData()
    if not next(grouped) then return end
    if data.recipeScanVersion ~= 2 then
        data.recipes = {}
        data.recipeUpdatedAt = {}
        data.recipeScanVersion = 2
    end
    data.recipeUpdatedAt = data.recipeUpdatedAt or {}
    local changed, now = {}, time()
    for id, recipes in pairs(grouped) do
        table.sort(recipes)
        local old = data.recipes[id] or {}
        if table.concat(old, "\t") ~= table.concat(recipes, "\t") then
            data.recipes[id] = recipes
            data.recipeUpdatedAt[id] = now
            changed[#changed + 1] = id
        end
    end
    if #changed == 0 then return end
    data.guid = UnitGUID("player") or ""
    for _, id in ipairs(changed) do sendRecipeChunks(id, data) end
end

local function validSender(sender, guid)
    if not iRC:IsGuildConnectionActive() or not iRC:IsGuildMemberName(sender) then return nil end
    local connection = iRC:GetConnection()
    if not connection then return nil end
    local key = iRC:NormalizeName(sender)
    local profile = connection.members and connection.members[key]
    if profile and profile.guid and profile.guid ~= "" and guid ~= "" and profile.guid ~= guid then return nil end
    return connection, key
end

function Professions:Receive(message, sender)
    local kind = message:match("^([^\t]+)")
    if kind == "PROF_SUM" then
        local version = message:match("^PROF_SUM\t([^\t]*)")
        local guid, stamp, wire, rodText
        if version == "2" then
            _, guid, stamp, wire, rodText = message:match("^PROF_SUM\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
        elseif version == "1" then
            _, guid, stamp, wire = message:match("^PROF_SUM\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
        end
        stamp = tonumber(stamp)
        local rodID = tonumber(rodText) or 0
        if not wire or (version ~= "1" and version ~= "2") or not guid or #guid > 80
            or not stamp or stamp > time() + 300 or #wire > 160 or rodID < 0 or rodID > 2000000 then return end
        local connection, key = validSender(sender, guid)
        if not connection then return end
        local skills = {}
        for idText, rankText in wire:gmatch("(%d+):(%d+)") do
            local id, rank = tonumber(idText), tonumber(rankText)
            if byID[id] and rank <= 1000 then skills[id] = rank end
        end
        connection.professionMembers = connection.professionMembers or {}
        local previous = connection.professionMembers[key]
        if previous and previous.guid == guid and (tonumber(previous.updatedAt) or 0) > stamp then return end
        local member = previous and previous.guid == guid and previous or { recipes = {}, recipeUpdatedAt = {} }
        member.guid, member.skills, member.updatedAt = guid, skills, stamp
        member.recipes, member.recipeUpdatedAt = member.recipes or {}, member.recipeUpdatedAt or {}
        member.fishingRodID = skills[356] and rodID > 0 and rodID or nil
        connection.professionMembers[key] = member
        if iRC.InvalidateGuildMemberRow then iRC:InvalidateGuildMemberRow(sender) end
        if iRC.MainUI and iRC.MainUI.frame and iRC.MainUI.frame.category == "Guild Members" then iRC.MainUI:RefreshIfShown() end
    elseif kind == "PROF_REC" then
        local version, guid, id, stamp, index, total, hash, chunk = message:match("^PROF_REC\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
        id, stamp, index, total = tonumber(id), tonumber(stamp), tonumber(index), tonumber(total)
        if version ~= "1" or not chunk or not byID[id] or id == 129 or id == 356
            or not guid or #guid > 80 or not stamp or stamp > time() + 300
            or not index or not total or index < 1 or index > total or total > MAX_CHUNKS or #chunk > CHUNK_SIZE
            or not hash or #hash ~= 8 or not hash:match("^[0-9a-f]+$") then return end
        local key = iRC:NormalizeName(sender)
        local transferKey = key .. ":" .. id
        local transfer = transfers[transferKey]
        if not transfer or transfer.stamp ~= stamp or transfer.hash ~= hash or transfer.total ~= total or time() - transfer.startedAt > 90 then
            transfer = { stamp = stamp, hash = hash, total = total, guid = guid, chunks = {}, startedAt = time() }
            transfers[transferKey] = transfer
        end
        if transfer.guid ~= guid then return end
        transfer.chunks[index] = chunk
        for part = 1, total do if transfer.chunks[part] == nil then return end end
        transfers[transferKey] = nil
        local payload = table.concat(transfer.chunks)
        if digest(guid .. ":" .. id .. ":" .. stamp .. ":" .. payload) ~= hash then return end
        local connection = validSender(sender, guid)
        if not connection then return end
        connection.professionMembers = connection.professionMembers or {}
        local member = connection.professionMembers[key] or { guid = guid, skills = {}, recipes = {}, recipeUpdatedAt = {} }
        if member.guid ~= guid or (tonumber(member.recipeUpdatedAt and member.recipeUpdatedAt[id]) or 0) > stamp then return end
        local recipes = {}
        if payload ~= "" then
            for token in (payload .. ";"):gmatch("(.-);") do
                local recipe = unescape(token)
                if #recipe > 100 or not recipe:match("^[SN]") then return end
                recipes[#recipes + 1] = recipe
                if #recipes > 500 then return end
            end
        end
        member.recipes[id] = recipes
        member.recipeUpdatedAt[id] = stamp
        connection.professionMembers[key] = member
        if iRC.InvalidateGuildMemberRow then iRC:InvalidateGuildMemberRow(sender) end
        if iRC.MainUI and iRC.MainUI.frame and iRC.MainUI.frame.category == "Guild Members" then iRC.MainUI:RefreshIfShown() end
    end
end

function Professions:DescribeRecipes(data)
    local lines = {}
    for _, entry in ipairs(ORDER) do
        local id = entry[1]
        if data.skills and data.skills[id] then
            if id == 129 or id == 393 then
                lines[#lines + 1] = entry[2] .. " (" .. data.skills[id] .. ")"
            elseif id == 356 then
                local rodName
                if data.fishingRodID and C_Item and C_Item.GetItemInfo then
                    local name, link = C_Item.GetItemInfo(data.fishingRodID)
                    rodName = link or name
                end
                lines[#lines + 1] = entry[2] .. " (" .. data.skills[id] .. ") - Fishing rod: "
                    .. (rodName or (data.fishingRodID and ("Item #" .. data.fishingRodID) or "not detected"))
            else
                local recipes = data.recipes and data.recipes[id]
                lines[#lines + 1] = entry[2] .. " (" .. data.skills[id] .. ") - " .. (recipes and (#recipes .. " known recipes") or "recipes not scanned")
                for _, recipe in ipairs(recipes or {}) do
                    local name = recipe:sub(1, 1) == "S" and iRC:GetSpellName(tonumber(recipe:sub(2))) or recipe:sub(2)
                    lines[#lines + 1] = "  " .. tostring(name or recipe:sub(2))
                end
            end
        end
    end
    return lines
end

local eventFrame = CreateFrame("Frame")
local function registerSupportedEvent(event)
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then return false end
    return pcall(eventFrame.RegisterEvent, eventFrame, event)
end

for _, event in ipairs({
    "PLAYER_LOGIN", "SKILL_LINES_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED",
    "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
}) do
    registerSupportedEvent(event)
end
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        Professions:CollectSkills()
        if C_Timer and C_Timer.After then
            -- Presence replies are time-sensitive. Start optional profession
            -- and recipe sharing after the initial HELLO/activation exchange.
            local delay = iRC:GetStartupTrafficDelay() + 15
            sharingReadyAt = (GetTime and GetTime() or 0) + delay
            local attempts = 0
            local function sendInitialSummary()
                if Professions:SendSummary(true) then return end
                attempts = attempts + 1
                if attempts < 5 then C_Timer.After(15, sendInitialSummary) end
            end
            C_Timer.After(delay, sendInitialSummary)
        end
    elseif event == "SKILL_LINES_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" or event == "BAG_UPDATE_DELAYED" then
        if pendingUpdate then return end
        pendingUpdate = true
        C_Timer.After(2, function() pendingUpdate = false; Professions:SendSummary(false) end)
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
        if C_Timer and C_Timer.After then C_Timer.After(0.2, function() Professions:CollectOpenRecipes() end) end
    end
end)
