local _, Addon = ...

function Addon:PositionMinimapButton(angle)
    local button = self.minimapButton
    button.angle = angle
    local radians = math.rad(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(radians) * (Minimap:GetWidth() / 2 + 4),
        math.sin(radians) * (Minimap:GetHeight() / 2 + 4))
end

local function UpdateDrag()
    local centerX, centerY = Minimap:GetCenter()
    if not centerX or not centerY then return end
    local x, y = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local angle = math.deg(math.atan2(y / scale - centerY, x / scale - centerX)) % 360
    Addon:PositionMinimapButton(angle)
end

function Addon:MinimapDragEvent(event)
    local button = self.minimapButton
    local state = button.dragState
    if event == "start" and state == "idle" then
        button.dragState = "dragging"
        if Addon:GetWidgetTooltip():IsOwned(button) then Addon:GetWidgetTooltip():Hide() end
        button:SetScript("OnUpdate", UpdateDrag)
        UpdateDrag()
    elseif (event == "stop" or event == "hide") and state == "dragging" then
        self.preferences.minimapAngle = button.angle
        button:SetScript("OnUpdate", nil)
        button.dragState = event == "hide" and "idle" or "released"
    elseif event == "press" and state == "released" then
        button.dragState = "idle"
    end
end

function Addon:CreateMinimapButton()
    if self.minimapButton then
        self:MinimapDragEvent("hide")
        self:PositionMinimapButton(self.preferences.minimapAngle)
        return
    end

    -- The launcher, like Settings, survives addon resets and can open Settings while suspended.
    local button = CreateFrame("Button", "ForeverRosettaStoneMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button.dragState = "idle"
    button:SetScript("OnMouseDown", function() self:MinimapDragEvent("press") end)
    button:SetScript("OnDragStart", function() self:MinimapDragEvent("start") end)
    button:SetScript("OnDragStop", function() self:MinimapDragEvent("stop") end)
    button:SetScript("OnHide", function()
        self:MinimapDragEvent("hide")
    end)
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture([[Interface\Minimap\UI-Minimap-Background]])
    background:SetAllPoints(button)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture([[Interface\AddOns\ForeverRosettaStone\media\icon]])
    icon:SetSize(22, 22)
    icon:SetPoint("CENTER", 0, 0)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture([[Interface\Minimap\MiniMap-TrackingBorder]])
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", 0, 0)
    button:SetHighlightTexture([[Interface\Minimap\UI-Minimap-ZoomButton-Highlight]])
    button:SetScript("OnClick", function(_, mouseButton)
        if button.dragState ~= "idle" then return end
        if Addon:GetWidgetTooltip():IsOwned(button) then Addon:GetWidgetTooltip():Hide() end
        if mouseButton == "RightButton" and IsShiftKeyDown() then self:MoveDebugPicker("start")
        else self:OpenSettings() end
    end)
    button:SetScript("OnEnter", function()
        if button.dragState == "dragging" then return end
        Addon:GetWidgetTooltip():SetOwner(button, "ANCHOR_LEFT")
        Addon:GetWidgetTooltip():SetText("Forever Rosetta Stone")
        Addon:GetWidgetTooltip():AddLine(self:SettingsText("minimapClick"), 1, 1, 1)
        Addon:GetWidgetTooltip():AddLine(self:SettingsText("minimapInspect"), 1, 1, 1)
        Addon:GetWidgetTooltip():AddLine(self:SettingsText("minimapDrag"), 1, 1, 1)
        Addon:GetWidgetTooltip():Show()
    end)
    button:SetScript("OnLeave", function()
        if Addon:GetWidgetTooltip():IsOwned(button) then Addon:GetWidgetTooltip():Hide() end
    end)
    self.minimapButton = button
    self:PositionMinimapButton(self.preferences.minimapAngle)
    Minimap:HookScript("OnSizeChanged", function() self:PositionMinimapButton(button.angle) end)
    button:Show()
end
