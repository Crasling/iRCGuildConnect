local iRL = _G.iRaceLocked
if not iRL then return end

local Minimap = {}
iRL.Minimap = Minimap
local objectName = "iRaceLocked_MinimapButton"

function Minimap:UpdateVisibility()
    if not iRL.LDBIcon then return end
    if iRL:GetSettings().minimapButton.hide then
        iRL.LDBIcon:Hide(objectName)
    else
        iRL.LDBIcon:Show(objectName)
    end
end

local function createDataObject()
    if not iRL.LDBroker or not iRL.LDBIcon then return end
    iRL.MinimapDataObject = iRL.LDBroker:NewDataObject(objectName, {
        type = "data source",
        text = iRL.DisplayName,
        icon = iRL.IconPath,
        OnClick = function(_, button)
            if button == "RightButton" then
                iRL:OpenOptions()
            elseif IsShiftKeyDown and IsShiftKeyDown() then
                iRL:OpenConnectionDashboard()
            else
                iRL.AchievementsUI:Open()
            end
        end,
        OnTooltipShow = function(tooltip)
            local colors = iRL.Colors
            tooltip:SetText(colors.iRC .. iRL.DisplayName .. colors.Green .. " v" .. iRL.Version, 1, 1, 1)
            tooltip:AddLine(" ")
            tooltip:AddLine(colors.Yellow .. "Left Click: " .. colors.Orange .. "Open achievements", 1, 1, 1)
            tooltip:AddLine(colors.Yellow .. "Shift-Left Click: " .. colors.Orange .. "Open connection dashboard", 1, 1, 1)
            tooltip:AddLine(colors.Yellow .. "Right Click: " .. colors.Orange .. "Open settings", 1, 1, 1)
        end,
    })
end

local registered = false
local function register()
    if registered or not iRL.LDBIcon then return end
    createDataObject()
    if not iRL.MinimapDataObject then return end
    if iRL.LDBIcon:GetMinimapButton(objectName) then
        iRL.LDBIcon:Refresh(objectName, iRL:GetSettings().minimapButton)
    else
        iRL.LDBIcon:Register(objectName, iRL.MinimapDataObject, iRL:GetSettings().minimapButton)
    end
    registered = true
    Minimap:UpdateVisibility()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, _, addonName)
    if addonName == iRL.Name then register() end
end)
