local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

-- LibDataBroker / minimap launcher
--
-- This deliberately contains no main-window logic. It exposes the standard
-- broker object and forwards clicks to the UI module.

local Minimap = {}
iRC.Minimap = Minimap
local objectName = "iRC_MinimapButton"

-- Visibility follows the personal minimap setting maintained by Core.
function Minimap:UpdateVisibility()
    if not iRC.LDBIcon then return end
    if iRC:GetSettings().minimapButton.hide then
        iRC.LDBIcon:Hide(objectName)
    else
        iRC.LDBIcon:Show(objectName)
    end
end

-- LibDBIcon owns the actual movable button after the broker is created.
local function createDataObject()
    if not iRC.LDBroker or not iRC.LDBIcon then return end
    iRC.MinimapDataObject = iRC.LDBroker:NewDataObject(objectName, {
        type = "data source",
        text = iRC.DisplayName,
        icon = iRC.IconPath,
        iconCoords = { 0.14, 0.86, 0.10, 0.82 },
        OnClick = function(_, button)
            if button == "LeftButton" then
                if not iRC:CanOpenPanel() then return end
                if iRC.RaceGrid then iRC.RaceGrid:PublishFromClick() end
                iRC.MainUI:Toggle(true)
            end
            if button == "RightButton" then iRC:OpenOptions() end
        end,
        OnTooltipShow = function(tooltip)
            local colors = iRC.Colors
            tooltip:SetText(colors.iRC .. iRC.DisplayName .. colors.Green .. " v" .. iRC:GetDisplayVersion(), 1, 1, 1)
            tooltip:AddLine(" ")
            tooltip:AddLine(colors.Yellow .. "Left Click: " .. colors.Orange .. iRC:Text("IRC_MAIN_MINIMAP_TOGGLE"), 1, 1, 1)
            tooltip:AddLine(colors.Yellow .. "Right Click: " .. colors.Orange .. iRC:Text("IRC_MINIMAP_SETTINGS"), 1, 1, 1)
        end,
    })
end

local registered = false
-- Registration waits until saved variables and the broker libraries are ready.
local function register()
    if registered or not iRC.LDBIcon then return end
    createDataObject()
    if not iRC.MinimapDataObject then return end
    if iRC.LDBIcon:GetMinimapButton(objectName) then
        iRC.LDBIcon:Refresh(objectName, iRC:GetSettings().minimapButton)
    else
        iRC.LDBIcon:Register(objectName, iRC.MinimapDataObject, iRC:GetSettings().minimapButton)
    end
    registered = true
    Minimap:UpdateVisibility()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, _, addonName)
    if addonName == iRC.Name then register() end
end)
