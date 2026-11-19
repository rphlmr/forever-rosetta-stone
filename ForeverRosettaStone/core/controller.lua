local _, Addon = ...

local function GetFocusManager()
    return GamepadMode and GamepadMode.FrameControlsManager
end

-- Keep the window active for scrolling and Back, without preselecting an action.
-- Both calls use the client's SecureHelper wrappers; directional input resumes normal navigation.
function Addon:ClearGamepadTarget(frame)
    if InCombatLockdown() or SmartNavigation:GetActiveFrame() ~= frame then return end
    SmartNavigation:SetTargetButtonForFrame(frame, nil)
    SmartNavigation:HideCursor()
    if frame.SmartNavigationOnSelect then frame:SmartNavigationOnSelect(nil) end
end

-- Blizzard's prompt footer builds a binding group and pushes it on the shared gamepad binding stack.
-- Built from addon code, that group taints the stack, and later native actions (leaving a vendor,
-- opening chat) are blocked. This legend only draws the prompts: SmartNavigation owns Select and Back.
function Addon:CreateGamepadLegend(parent, name)
    local frame = self:NewFrame("Frame", name, parent)
    frame:SetSize(1, 22)
    frame:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", -6, -2)
    frame:Hide()
    local legend = { frame = frame, prompts = {} }

    local function Add(key, label)
        local icon = CreateFrame("Frame", nil, frame, "InputIconTextureFrameTemplate")
        icon:SetSize(20, 20)
        icon:SetInputKey(key)
        local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetText(label)
        legend.prompts[#legend.prompts + 1] = { icon = icon, text = text }
    end

    function legend:AddStandardSelectPrompt()
        Add(GAMEPAD_FACE_BOTTOM, ACTION_LABEL_SELECT)
    end

    function legend:AddStandardBackPrompt(label)
        Add(GAMEPAD_FACE_RIGHT, label or FRAME_ACTION_BACK)
    end

    function legend:Finalize()
        local anchor
        for index = #self.prompts, 1, -1 do
            local prompt = self.prompts[index]
            if anchor then prompt.text:SetPoint("RIGHT", anchor, "LEFT", -14, 0)
            else prompt.text:SetPoint("RIGHT", frame, "RIGHT") end
            prompt.icon:SetPoint("RIGHT", prompt.text, "LEFT", -4, 0)
            anchor = prompt.icon
        end
    end

    function legend:ShowPrompts()
        frame:Show()
    end

    function legend:HidePrompts()
        frame:Hide()
    end

    return legend
end

function Addon:SetupSideReaderController(reader, footerName, dismiss)
    local frame, body, options = reader.frame, reader.body, reader.options
    local footer = self:CreateGamepadLegend(frame, footerName)
    if options then footer:AddStandardSelectPrompt() end
    footer:AddStandardBackPrompt(FRAME_ACTION_CLOSE)
    footer:Finalize()
    footer:HidePrompts()
    local selectPrompt = options and footer.prompts[1]
    reader.footer = footer

    -- Keep actions reachable without preselecting Options; the X gives way to Back.
    function reader:SyncTarget()
        local gamepad = InputUtil.IsGamepadUIEnabled()
        frame.CloseButton:SetShown(not gamepad)
        local focused = gamepad and self.registered and not InCombatLockdown() and SmartNavigation:GetActiveFrame() == frame
        local selected = focused and SmartNavigation:GetCurrentButton()
        if selectPrompt then
            local canSelect = selected == options and options:IsVisible()
            selectPrompt.icon:SetShown(canSelect)
            selectPrompt.text:SetShown(canSelect)
        end
        if selected and not selected:IsVisible() then
            Addon:ClearGamepadTarget(frame)
        end
    end

    function reader:ReleaseController()
        footer:HidePrompts()

        if not self.registered or InCombatLockdown() then return end

        self.registered = nil
        GamepadMode.FrameControlsManager:FrameHidden(frame)
        SmartNavigation:RemovePanelInfo(frame)
    end

    function reader:SyncController(focus)
        if not InputUtil.IsGamepadUIEnabled() or not frame:IsShown()
            or (options and Addon.questReport and Addon.questReport.frame:IsShown()) then
            self:ReleaseController()
            return
        end

        if not self.registered and not InCombatLockdown() then
            self.registered = true
            GamepadMode.FrameControlsManager:FrameShown(frame, false, focus == true)
        end
    end

    frame.FocusGamepad = self:Wrap("focus " .. frame:GetName(), function()
        if not reader.registered or InCombatLockdown() then return end

        SmartNavigation:SetScrollFrameForFrame(frame, body.frame)
        SmartNavigation_MarkScrollFrameMaintainPreviousButtonOnScroll(body.frame)
        Addon:ClearGamepadTarget(frame)
        reader:SyncTarget()
        footer:ShowPrompts()
    end)
    frame.UnfocusGamepad = self:Wrap("leave " .. frame:GetName(), function()
        footer:HidePrompts()

        if not InCombatLockdown() then SmartNavigation:SetScrollFrameForFrame(frame, nil) end
    end)
    frame.SmartNavigationCloseHandler = self:Wrap("close " .. frame:GetName(), function()
        dismiss()
        return true
    end, true)
    self:HookScript(frame, "OnHide", function() reader:ReleaseController() end)
end

function Addon:SyncPanelInputMode()
    local gamepad = InputUtil.IsGamepadUIEnabled()
    self.panel.CloseButton:SetShown(not gamepad)
    if not gamepad then self.panel.gamepadFooter:HidePrompts() end
end

function Addon:CreateControllerFocus()
    local panel = self.panel
    local footer = Addon:CreateGamepadLegend(panel, "ForeverRosettaStoneQuestFooter")
    footer:AddStandardSelectPrompt()
    footer:AddStandardBackPrompt(FRAME_ACTION_CLOSE)
    footer:Finalize()
    panel.gamepadFooter = footer
    self.frenchScrollPosition = nil
    local hint = self:NewFrame("Frame", nil, panel, "GamepadScrollBarHintTemplate")
    hint:SetOwner(self.page.body.frame.ScrollBar.Track.Thumb, "CENTER")
    hint:Hide()
    self.scrollHint = hint
    InputUtil.RegisterForInterfaceTransitions(panel, self:Wrap("input mode changed", function()
        self:Send("input.reset")
    end))

    panel.FocusGamepad = self:Wrap("focus English", function()
        if InCombatLockdown() or self.registeredPanel ~= panel then return end

        local details = QuestMapFrame.DetailsFrame
        self.frenchScrollPosition = { questID = details.questID, offset = details.ScrollFrame:GetVerticalScroll() }
        self:Send("focus.enter")
        SmartNavigation:SetScrollFrameForFrame(panel, self.page.body.frame)
        SmartNavigation_MarkScrollFrameMaintainPreviousButtonOnScroll(self.page.body.frame)
        self:ClearGamepadTarget(panel)
        footer:ShowPrompts()
        hint:Show()
    end)
    panel.UnfocusGamepad = self:Wrap("leave English", function()
        footer:HidePrompts()
        hint:Hide()

        if not InCombatLockdown() then SmartNavigation:SetScrollFrameForFrame(panel, nil) end

        if self.current.mode == "reading" then self:Send("focus.leave") end
    end)
    panel.SmartNavigationCloseHandler = self:Wrap("close English", function()
        self:Send("panel.close")
        return true
    end, true)
    self:HookScript(panel, "OnHide", function() self:ReleaseControllerFocus() end)

    self.toggle.OnSmartNavSelect = self:Wrap("select bookmark", function()
        if not self.toggle:IsVisible() then return end
        self:Send("bookmark.focus")
        self.toggle:SetGamepadFocus(true)
    end)
    self.toggle.OnSmartNavDeselect = self:Wrap("deselect bookmark", function()
        self.toggle:SetGamepadFocus(false)
        self:Send("bookmark.blur")
    end)

    hooksecurefunc(WorldMapFrame, "FocusDetails", self:Wrap("restore French scroll", function()
        if GetFocusManager():GetActiveFrame() ~= WorldMapFrame then return end

        local position = self.frenchScrollPosition
        self.frenchScrollPosition = nil
        local details = QuestMapFrame.DetailsFrame

        if not position or not details:IsVisible() or details.questID ~= position.questID then return end

        details.ScrollFrame:SetVerticalScroll(math.min(position.offset, details.ScrollFrame:GetVerticalScrollRange()))
    end))
end

function Addon:OpenPanel()
    if InCombatLockdown() then return end

    self:Send("panel.open")
end

function Addon:ReleaseControllerFocus()
    self:SyncQuestReportController()
    if self.scrollHint then self.scrollHint:Hide() end
    if self.panel and self.panel.gamepadFooter then self.panel.gamepadFooter:HidePrompts() end

    if not self.registeredPanel or InCombatLockdown() then return end

    local panel = self.registeredPanel
    self.registeredPanel = nil
    GetFocusManager():FrameHidden(panel)
    SmartNavigation:RemovePanelInfo(panel)
end

function Addon:ResetControllerFocus()
    self.registeredPanel, self.frenchScrollPosition = nil, nil
    self.scrollHint:Hide()
    self.panel.gamepadFooter:HidePrompts()
    self:SyncPanelInputMode()
    self.panel:EndFocus()
end

function Addon:SyncControllerFocus(focusPanel)
    self:SyncPanelInputMode()
    if self.current.mode == "unavailable" then self.frenchScrollPosition = nil end

    if InCombatLockdown() then return end

    local manager = GetFocusManager()

    if not manager then return end

    -- Do not preserve a hidden bookmark in the map's focus history.
    if SmartNavigation:GetCurrentButton() == self.toggle and not self.toggle:IsVisible() then
        SmartNavigation:HideCursor()
    end

    local selected = SmartNavigation:GetCurrentButton()

    if self.panel:IsShown() and self.current.mode ~= "unavailable"
        and SmartNavigation:GetActiveFrame() == self.panel
        and (selected == self.page.reportButton or selected == self.panel.ReportButton)
        and not selected:IsVisible() then
        self:ClearGamepadTarget(self.panel)
    end

    if SmartNavigation:GetActiveFrame() == self.panel and selected and not selected:IsForbidden() and selected.rewardSource
        and not self:IsFeatureEnabled("rewardComparison") then
        SmartNavigation:HideCursor()
    end

    local available = self.lifecycle == "ready" and self.panel:IsShown()
        and self.current.mode ~= "unavailable"
        and InputUtil.IsGamepadUIEnabled()
        and not (GameMenuFrame and GameMenuFrame:IsShown())
        and not SettingsPanel:IsShown()
        and not (self.errorDialog and self.errorDialog.frame:IsShown() and not self:IsDebugPicking())
        and not (self.questReport and self.questReport.frame:IsShown())

    if not available then
        self:ReleaseControllerFocus()
    elseif self.registeredPanel ~= self.panel then
        self:ReleaseControllerFocus()
        self.registeredPanel = self.panel
        manager:FrameShown(self.panel, false, focusPanel == true)
    end
end
