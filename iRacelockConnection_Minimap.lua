local _, private = ...
local iRC = private and private.iRC
if not iRC then return end

local Minimap = {}
iRC.Minimap = Minimap
local objectName = "iRacelockConnection_MinimapButton"

function Minimap:UpdateVisibility()
    if not iRC.LDBIcon then return end
    if iRC:GetSettings().minimapButton.hide then
        iRC.LDBIcon:Hide(objectName)
    else
        iRC.LDBIcon:Show(objectName)
    end
end

local function createDataObject()
    if not iRC.LDBroker or not iRC.LDBIcon then return end
    iRC.MinimapDataObject = iRC.LDBroker:NewDataObject(objectName, {
        type = "data source",
        text = iRC.DisplayName,
        icon = iRC.IconPath,
        OnClick = function(_, button)
            if button == "RightButton" then
                iRC:ToggleOptions()
            elseif IsShiftKeyDown and IsShiftKeyDown() then
                iRC.ConnectionDashboard:Toggle()
            else
                iRC.MainUI:Toggle(true)
            end
        end,
        OnTooltipShow = function(tooltip)
            local colors = iRC.Colors
            tooltip:SetText(colors.iRC .. iRC.DisplayName .. colors.Green .. " v" .. iRC:GetDisplayVersion(), 1, 1, 1)
            tooltip:AddLine(" ")
            tooltip:AddLine(colors.Yellow .. "Left Click: " .. colors.Orange .. iRC:Text("IRC_MAIN_MINIMAP_TOGGLE"), 1, 1, 1)
            tooltip:AddLine(colors.Yellow .. "Shift-Left Click: " .. colors.Orange .. "Toggle connection dashboard", 1, 1, 1)
            tooltip:AddLine(colors.Yellow .. "Right Click: " .. colors.Orange .. "Toggle settings", 1, 1, 1)
        end,
    })
end

local registered = false
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
