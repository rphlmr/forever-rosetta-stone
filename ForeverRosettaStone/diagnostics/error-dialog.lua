local _, Addon = ...

local function Protect(callback)
    return function(...)
        local arguments, count = { ... }, select("#", ...)
        local ok, reason = xpcall(function() return callback(unpack(arguments, 1, count)) end,
            function(failure) return tostring(failure) .. "\n" .. debugstack(2, 20, 0) end)

        if not ok then
            pcall(Addon.RecordError, Addon, "debug tool", reason)
            pcall(print, "Forever Rosetta Stone: error window failed: " .. tostring(reason))
        else
            return reason
        end
    end
end

local function CreateErrorDialog()
    -- Diagnostics must remain usable after the main addon's callbacks and frames are suspended.
    local overlay = CreateFrame("Frame", "ForeverRosettaStoneErrorDialog", UIParent)
    Addon.errorDialog = { frame = overlay }
    overlay:Hide()
    table.insert(UISpecialFrames, overlay:GetName())
    overlay:SetAllPoints(UIParent)
    overlay:SetFrameStrata("TOOLTIP")
    -- The client clamps levels at 10000; children need headroom for drawing and mouse input.
    overlay:SetFrameLevel(9000)
    overlay:EnableMouse(true)
    local shade = overlay:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 0.12)

    local window = CreateFrame("Frame", nil, overlay, "PortraitFrameTemplateNoCloseButton")
    window:SetSize(660, 420)
    window:SetPoint("CENTER", UIParent, "CENTER")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    local dragHandle = CreateFrame("Frame", nil, window)
    dragHandle:SetPoint("TOPLEFT", window, "TOPLEFT", 65, 0)
    dragHandle:SetPoint("TOPRIGHT", window, "TOPRIGHT", -32, 0)
    dragHandle:SetHeight(30)
    dragHandle:EnableMouse(true)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", Protect(function() window:StartMoving() end))
    dragHandle:SetScript("OnDragStop", Protect(function() window:StopMovingOrSizing() end))
    dragHandle:SetScript("OnHide", Protect(function() window:StopMovingOrSizing() end))
    Addon.errorDialog.dragHandle = dragHandle
    window:SetPortraitToAsset([[Interface\AddOns\ForeverRosettaStone\media\icon]])
    window:SetPortraitTextureSizeAndOffset(54, -1, 5)
    local portraitMask = window.PortraitContainer.CircleMask
    portraitMask:ClearAllPoints()
    portraitMask:SetSize(58, 58)
    portraitMask:SetPoint("TOPLEFT", window, "TOPLEFT", -3, 7)
    local portraitBackground = window.PortraitContainer:CreateTexture(nil, "BACKGROUND")
    portraitBackground:SetAllPoints(portraitMask)
    portraitBackground:SetColorTexture(0.04, 0.03, 0.02, 1)
    portraitBackground:AddMaskTexture(portraitMask)
    window:GetPortrait():AddMaskTexture(portraitMask)
    window:SetTitle("Forever Rosetta Stone")
    local title = window.TitleContainer.TitleText
    local hint = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", window, "TOPLEFT", 80, -42)
    hint:SetWidth(610)
    hint:SetJustifyH("LEFT")
    hint:SetText("Select output, then Ctrl+C / Cmd+C to copy. Escape closes this window.")

    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", window, "TOPRIGHT", 1, 0)
    close:SetScript("OnClick", Protect(function() overlay:Hide() end))
    window.CloseButton = close
    window:SetFrameLevelsFromBaseLevel(window:GetFrameLevel())
    local background = window:CreateTexture(nil, "BACKGROUND", nil, -5)
    background:SetPoint("TOPLEFT", window, "TOPLEFT", 3, -21)
    background:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -3, 3)
    background:SetAtlas("Profession-Background-Template2")
    Addon.errorDialog.background = background

    local function ProfessionPanel()
        local panel = CreateFrame("Frame", nil, window)
        local art = panel:CreateTexture(nil, "BACKGROUND")
        art:SetAllPoints(panel)
        art:SetAtlas("Profession-overview-Card")
        art:SetTextureSliceMargins(16, 16, 16, 16)
        return panel
    end
    local sidebar = ProfessionPanel()
    sidebar:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -110)
    sidebar:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 12, 46)
    sidebar:SetWidth(300)
    local contentInset = ProfessionPanel()
    contentInset:SetPoint("TOPLEFT", window, "TOPLEFT", 320, -110)
    contentInset:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -30, 46)
    Addon.errorDialog.sidebar, Addon.errorDialog.contentInset, Addon.errorDialog.shade = sidebar, contentInset, shade

    local scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", window, "TOPLEFT", 18, -76)
    scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -40, 50)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetFontObject(GameFontHighlight)
    edit:SetTextColor(1, 1, 1, 1)
    edit:SetWidth(598)
    edit:SetHeight(300)
    edit:SetTextInsets(4, 4, 4, 4)
    scroll:SetScrollChild(edit)

    local measure = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    measure:SetWidth(590)
    measure:Hide()
    -- A focused edit box takes all input, so the controller never reaches SmartNavigation again.
    -- Listen to the controller only while focused: B closes like Escape, any other button gives
    -- navigation back.
    edit:SetScript("OnEditFocusGained", Protect(function()
        edit:HighlightText()
        edit:EnableGamePadButton(InputUtil.IsGamepadUIEnabled())
    end))
    edit:SetScript("OnEditFocusLost", Protect(function() edit:EnableGamePadButton(false) end))
    edit:SetScript("OnGamePadButtonDown", Protect(function(_, button)
        edit:ClearFocus()
        if button == "PAD2" then overlay:Hide() end
    end))
    edit:SetScript("OnEscapePressed", Protect(function() overlay:Hide() end))
    edit:SetScript("OnTextChanged", Protect(function()
        if edit:GetText() ~= Addon.errorDialog.report then
            edit:SetText(Addon.errorDialog.report)
            edit:HighlightText()
        end
    end))

    Addon.errorDialog.editBox = edit
    Addon.errorDialog.scroll = scroll
    Addon.errorDialog.measure = measure
    Addon.errorDialog.close = close
    Addon.errorDialog.title = title
    Addon.errorDialog.hint = hint
    Addon.errorDialog.window = window
    local selectOutput = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    selectOutput:SetSize(180, 26)
    selectOutput:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -18, 14)
    selectOutput:SetText(Addon:DebugText("copy"))
    selectOutput:SetScript("OnClick", Protect(function()
        edit:SetFocus()
        edit:HighlightText()
    end))
    Addon.errorDialog.selectOutput = selectOutput

    -- Report view: one capture action, the numbered capture list, and its own clear action.
    local pick = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    pick:SetSize(276, 30)
    pick:SetPoint("TOPLEFT", window, "TOPLEFT", 24, -70)
    pick:SetText(Addon:DebugText("inspect"))
    pick:SetScript("OnClick", Protect(function() Addon:MoveDebugPicker("start") end))
    local list = CreateFrame("EventScrollFrame", nil, window, "ScrollFrameTemplate")
    list:SetPoint("TOPLEFT", window, "TOPLEFT", 22, -142)
    list:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 22, 88)
    list:SetWidth(252)
    list.ScrollBar:ClearAllPoints()
    list.ScrollBar:SetPoint("TOPLEFT", list, "TOPRIGHT", 8, 0)
    list.ScrollBar:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 8, 0)
    local listChild = CreateFrame("Frame", nil, list)
    listChild:SetSize(252, 1)
    list:SetScrollChild(listChild)
    local clearCaptures = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    clearCaptures:SetSize(276, 26)
    clearCaptures:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 24, 54)
    clearCaptures:SetText(Addon:DebugText("clear"))
    clearCaptures:SetScript("OnClick", Protect(function() Addon:MoveDebugPicker("clear") end))

    -- Console view: free-form commands and addon-level reports.
    local command = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
    command:SetSize(520, 24)
    command:SetPoint("TOPLEFT", window, "TOPLEFT", 30, -78)
    command:SetAutoFocus(false)
    command:SetMaxLetters(0)
    command:SetTextColor(1, 1, 1, 1)
    local commandLabel = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    commandLabel:SetPoint("BOTTOMLEFT", command, "TOPLEFT", -6, 4)
    commandLabel:SetText(Addon:DebugText("command"))
    local run = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    run:SetSize(110, 26)
    run:SetPoint("LEFT", command, "RIGHT", 10, 0)
    run:SetText(Addon:DebugText("run"))
    local function Execute()
        command:ClearFocus()
        Addon:RunDebugCommand(command:GetText())
    end
    command:SetScript("OnEnterPressed", Protect(Execute))
    command:SetScript("OnEscapePressed", Protect(function() overlay:Hide() end))
    run:SetScript("OnClick", Protect(Execute))
    local help = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    help:SetSize(110, 26)
    help:SetPoint("LEFT", run, "RIGHT", 10, 0)
    help:SetText(Addon:DebugText("helpButton"))
    help:SetScript("OnClick", Protect(function()
        command:ClearFocus()
        command:SetText("help")
        Addon:RunDebugCommand("help")
    end))
    Addon.errorDialog.commandBox, Addon.errorDialog.run, Addon.errorDialog.pick = command, run, pick
    Addon.errorDialog.help, Addon.errorDialog.commandLabel = help, commandLabel
    local addonReport = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    addonReport:SetSize(180, 26)
    addonReport:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 18, 14)
    addonReport:SetText(Addon:DebugText("addon"))
    addonReport:SetScript("OnClick", Protect(function()
        command:ClearFocus()
        Addon:RunDebugCommand("status")
    end))
    Addon.errorDialog.addonReport, Addon.errorDialog.clearCaptures = addonReport, clearCaptures
    local saveReport = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    saveReport:SetSize(180, 26)
    saveReport:SetText(Addon:DebugText("save"))
    saveReport:SetScript("OnClick", Protect(function()
        Addon.preferences.debugReport = Addon.errorDialog.report
        hint:SetText(Addon:DebugText("saved"))
        hint:Show()
    end))
    Addon.errorDialog.saveReport = saveReport
    -- The reporting guide (steps and GitHub link) stays one button away, even with a capture open.
    local guide = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    guide:SetSize(180, 26)
    guide:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 18, 14)
    guide:SetText(Addon:DebugText("help"))
    guide:SetScript("OnClick", Protect(function()
        Addon.debugPendingSelection = Addon.errorDialog.selectedEntry
        Addon:ShowDebugConsole(Addon:GetDebugWelcome(), nil, "report")
    end))
    Addon.errorDialog.guide = guide
    local errorLog = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    errorLog:SetSize(180, 26)
    errorLog:SetPoint("LEFT", addonReport, "RIGHT", 10, 0)
    errorLog:SetText(Addon:DebugText("errorLog"))
    errorLog:SetScript("OnClick", Protect(function() Addon:ShowErrorDialog(true) end))
    Addon.errorDialog.errorLog = errorLog
    local clearErrorLog = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    clearErrorLog:SetSize(180, 26)
    clearErrorLog:SetPoint("LEFT", saveReport, "RIGHT", 10, 0)
    clearErrorLog:SetText(Addon:DebugText("clearErrorLog"))
    clearErrorLog:SetScript("OnClick", Protect(function()
        Addon:ClearErrorLog()
        Addon:ShowErrorDialog(true)
    end))
    clearErrorLog:Hide()
    Addon.errorDialog.clearErrorLog = clearErrorLog
    local function ControllerAction(button)
        button.OnSmartNavClick = Protect(function() button:GetScript("OnClick")(button) end)
    end
    for _, button in ipairs({ close, run, pick, guide, help, addonReport, clearCaptures, saveReport,
        errorLog, clearErrorLog, selectOutput }) do
        ControllerAction(button)
    end
    SmartNavigation_MarkFrameIgnored(command)
    SmartNavigation_MarkFrameIgnored(edit)
    -- The native cursor's HIGH stratum is behind this diagnostic overlay.
    local focusIndicator = CreateFrame("Frame", nil, overlay)
    focusIndicator:SetSize(32, 32)
    focusIndicator:SetFrameLevel(9600)
    focusIndicator:EnableMouse(false)
    local focusArrow = focusIndicator:CreateTexture(nil, "OVERLAY")
    focusArrow:SetAllPoints()
    focusArrow:SetAtlas("gamepad-largecursor-white")
    focusArrow:SetVertexColor(1, 0.82, 0)
    focusIndicator:Hide()
    Addon.errorDialog.focusIndicator = focusIndicator
    window.SmartNavigationOnSelect = Protect(function(_, button)
        focusIndicator:Hide()
        if not button or not button:IsVisible() or Addon:IsDebugPicking() then return end
        focusIndicator:ClearAllPoints()
        focusIndicator:SetPoint("RIGHT", button, "LEFT", 10, 0)
        focusIndicator:Show()
    end)
    window.FocusGamepad = Protect(function()
        SmartNavigation:SetScrollFrameForFrame(window, scroll)
        Addon:ClearGamepadTarget(window)
    end)
    window.UnfocusGamepad = Protect(function()
        focusIndicator:Hide()
        if not InCombatLockdown() then SmartNavigation:SetScrollFrameForFrame(window, nil) end
    end)
    window.SmartNavigationCloseHandler = Protect(function() overlay:Hide(); return true end)
    local footer = Addon:CreateGamepadLegend(window, "ForeverRosettaStoneDebugFooter")
    footer:AddStandardSelectPrompt()
    footer:AddStandardBackPrompt(FRAME_ACTION_CLOSE)
    footer:Finalize()
    Addon.errorDialog.gamepadFooter = footer
    InputUtil.RegisterForInterfaceTransitions(overlay, Protect(function() Addon:SyncDebugController() end))
    overlay:RegisterEvent("PLAYER_REGEN_ENABLED")
    overlay:SetScript("OnEvent", Protect(function()
        Addon:RefreshDebugPickedList()
        Addon:SyncDebugController()
    end))
    Addon.errorDialog.list, Addon.errorDialog.listChild = list, listChild
    Addon.errorDialog.pickedButtons = {}
    Addon.errorDialog.viewReports = {}

    local listTitle = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listTitle:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 14, -14)
    local empty = listChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    empty:SetPoint("TOPLEFT", listChild, "TOPLEFT", 4, -8)
    empty:SetWidth(240)
    empty:SetJustifyH("LEFT")
    empty:SetText(Addon:DebugText("empty"))
    Addon.errorDialog.listTitle, Addon.errorDialog.empty = listTitle, empty
    Addon:CreateDebugDisplay(Addon.errorDialog, Protect)

    local stopPanel = CreateFrame("Frame", "ForeverRosettaStoneDebugStop", UIParent)
    stopPanel:SetSize(260, 30)
    stopPanel:SetPoint("TOP", UIParent, "TOP", 0, -35)
    stopPanel:SetFrameStrata("TOOLTIP")
    stopPanel:SetFrameLevel(9100)
    stopPanel:Hide()
    local stop = CreateFrame("Button", nil, stopPanel, "UIPanelButtonTemplate")
    stop:SetSize(260, 30)
    stop:SetAllPoints(stopPanel)
    stop:SetFrameStrata("TOOLTIP")
    stop:SetFrameLevel(9100)
    stop:EnableMouse(true)
    stop:SetText(Addon:DebugText("stop"))
    stop:SetScript("OnClick", Protect(function() Addon:MoveDebugPicker("stop") end))
    ControllerAction(stop)
    local stopFooter = Addon:CreateGamepadLegend(stopPanel, "ForeverRosettaStoneDebugStopFooter")
    stopFooter:AddStandardBackPrompt((HOLD or (GetLocale() == "frFR" and "Maintenir" or "Hold")) .. " · " .. Addon:DebugText("stop"))
    stopFooter:Finalize()
    Addon.errorDialog.stopFooter = stopFooter
    -- A gamepad button listener intercepts native bindings, including opening bags and menus.
    stopPanel:SetScript("OnUpdate", Protect(function(_, elapsed)
        if not InputUtil.IsGamepadUIEnabled() or not Addon:IsDebugPicking() then return end
        local dialog = Addon.errorDialog
        if not IsKeyDown(GAMEPAD_FACE_RIGHT) then
            dialog.stopHold = 0
        elseif GamepadRadial and GamepadRadial:IsShown() then
            dialog.stopHold = nil
        elseif dialog.stopHold then
            dialog.stopHold = dialog.stopHold + elapsed
            if dialog.stopHold >= 0.8 then Addon:MoveDebugPicker("stop") end
        end
    end))
    stop:Hide()
    Addon.errorDialog.stopPicking = stop
    Addon.errorDialog.stopPanel = stopPanel
    overlay:SetScript("OnHide", Protect(function()
        if Addon.errorDialog.hidingForPick then return end
        local returnView = Addon.errorDialog.errorReturnView
        if Addon:IsDebugPicking() then returnView = { report = Addon:GetDebugPickedList(), view = "report" } end
        Addon.errorDialog.errorReturnView = nil
        if Addon.MoveDebugPicker then Addon:MoveDebugPicker("close") end
        stop:Hide()
        stopPanel:Hide()
        Addon:SyncDebugController()
        if returnView then
            -- Let native OnHide navigation cleanup finish before reusing this window.
            C_Timer.After(0, Protect(function()
                if overlay:IsShown() then return end
                if returnView.view == "display" then Addon:ShowDebugDisplay()
                else Addon:ShowDebugConsole(returnView.report, nil, returnView.view) end
            end))
        end
    end))
end

function Addon:SyncDebugController()
    local dialog = self.errorDialog
    if not dialog or InCombatLockdown() then return end
    local manager = GamepadMode and GamepadMode.FrameControlsManager
    if not manager then return end
    local picking = self:IsDebugPicking()
    if picking and InputUtil.IsGamepadUIEnabled() then dialog.stopFooter:ShowPrompts()
    else dialog.stopFooter:HidePrompts() end
    local target
    if InputUtil.IsGamepadUIEnabled() then
        if dialog.previewReturnPanel:IsShown() then target = dialog.previewReturnPanel
        elseif dialog.frame:IsShown() and not picking then target = dialog.window end
    end
    if dialog.controllerRegistered == target then
        local selected = SmartNavigation:GetCurrentButton()
        if target == dialog.window and SmartNavigation:GetActiveFrame() == target
            and selected and not selected:IsVisible() then
            self:ClearGamepadTarget(target)
        end
        return
    end
    if dialog.controllerRegistered then
        local previous = dialog.controllerRegistered
        dialog.controllerRegistered = nil
        dialog.gamepadFooter:HidePrompts()
        dialog.previewFooter:HidePrompts()
        manager:HandlePopupHide(previous)
        SmartNavigation:RemovePanelInfo(previous)
    end
    if target then
        dialog.controllerRegistered = target
        -- A diagnostic popup returns navigation to the inspected window when Pick starts.
        manager:HandlePopupShown(target)
        if target == dialog.window then dialog.gamepadFooter:ShowPrompts() end
        if target == dialog.previewReturnPanel then dialog.previewFooter:ShowPrompts() end
    end
end

-- Each console view owns its controls; the view never depends on which text is displayed.
local function ApplyDebugLayout(self, dialog, view, title, guide)
    local width = view == "error" and 660 or math.min(1000, UIParent:GetWidth() - 40)
    local height = view == "error" and 420 or math.min(620, UIParent:GetHeight() - 40)
    dialog.window:SetSize(width, height)
    local report, console, display = view == "report", view == "console", view == "display"
    local visible = {
        [dialog.pick] = report, [dialog.sidebar] = report, [dialog.list] = report,
        [dialog.listTitle] = report, [dialog.clearCaptures] = report, [dialog.guide] = report,
        [dialog.commandBox] = console, [dialog.commandLabel] = console, [dialog.run] = console,
        [dialog.help] = console, [dialog.addonReport] = console, [dialog.errorLog] = console,
        [dialog.clearErrorLog] = view == "error" and title == "Error report",
        [dialog.saveReport] = not display, [dialog.selectOutput] = not display,
        [dialog.scroll] = not display, [dialog.contentInset] = not display, [dialog.display] = display,
        [dialog.hint] = report or view == "error",
        [dialog.capturesTab] = view ~= "error", [dialog.displayToggle] = view ~= "error",
        [dialog.consoleTab] = view ~= "error",
    }
    for frame, shown in pairs(visible) do frame:SetShown(shown) end
    dialog.capturesTab:SetChecked(report)
    dialog.displayToggle:SetChecked(display)
    dialog.consoleTab:SetChecked(console)

    local left, top = view == "report" and 320 or 12, view == "error" and -68 or -110
    dialog.contentInset:ClearAllPoints()
    dialog.contentInset:SetPoint("TOPLEFT", dialog.window, "TOPLEFT", left, top)
    dialog.contentInset:SetPoint("BOTTOMRIGHT", dialog.window, "BOTTOMRIGHT", -30, 46)
    dialog.scroll:ClearAllPoints()
    dialog.scroll:SetPoint("TOPLEFT", dialog.window, "TOPLEFT", left + 16, top - 16)
    dialog.scroll:SetPoint("BOTTOMRIGHT", dialog.window, "BOTTOMRIGHT", -40, 50)
    local textWidth = width - left - 80
    dialog.editBox:SetWidth(textWidth)
    dialog.measure:SetWidth(textWidth - 8)
    dialog.commandBox:SetWidth(width - 330)

    dialog.saveReport:ClearAllPoints()
    if view == "error" then dialog.saveReport:SetPoint("BOTTOMLEFT", dialog.window, "BOTTOMLEFT", 18, 14)
    else dialog.saveReport:SetPoint("RIGHT", dialog.selectOutput, "LEFT", -10, 0) end
    dialog.hint:ClearAllPoints()
    if report then
        dialog.hint:SetPoint("LEFT", dialog.pick, "RIGHT", 18, 0)
        dialog.hint:SetWidth(width - 350)
        dialog.hint:SetText(self:DebugText("pickHint"))
    else
        dialog.hint:SetPoint("TOPLEFT", dialog.window, "TOPLEFT", 80, -42)
        dialog.hint:SetWidth(width - 104)
        dialog.hint:SetText(self:DebugText("reportHint"))
    end
    -- The guide is instructions, not evidence: there is nothing to copy or save yet.
    if guide then
        dialog.selectOutput:Disable()
        dialog.saveReport:Disable()
    else
        dialog.selectOutput:Enable()
        dialog.saveReport:Enable()
    end
    dialog.title:SetText("Forever Rosetta Stone · " .. (view == "error" and title or self:DebugText("title")))
end

function Addon:ShowDiagnosticReport(title, report, console, preparingPick, view)
    local ok, reason = pcall(function()
        if not self.errorDialog then CreateErrorDialog() end

        local dialog = self.errorDialog
        dialog.errorReturnView = nil
        self:MoveDebugPreview("dismiss")
        if self:IsDebugPicking() then self:MoveDebugPicker("close") end
        if console then
            -- Free-form output never lands on the tooltip tester, which has no text field.
            view = view or (dialog.view ~= "display" and dialog.view) or (dialog.view and "console") or "report"
            dialog.view = view
            if view ~= "display" then dialog.viewReports[view] = report end
        else
            view = "error"
        end
        if view == "report" then dialog.selectedEntry = self.debugPendingSelection end
        self.debugPendingSelection = nil
        dialog.console = console
        ApplyDebugLayout(self, dialog, view, title, view == "report" and report == self:GetDebugWelcome())
        dialog.report = report
        dialog.measure:SetText(dialog.report)
        dialog.editBox:SetHeight(math.max(300, dialog.measure:GetStringHeight() + 16))
        dialog.editBox:SetText(dialog.report)
        dialog.editBox:HighlightText(0, 0)
        dialog.editBox:ClearFocus()
        dialog.scroll:SetVerticalScroll(0)
        dialog.frame:Show()
        self:HideNameTooltips()
        self:ReleaseControllerFocus()
        self:RefreshDebugPickedList()
        -- Direct inspection must not briefly take focus away from the native window being inspected.
        if not preparingPick then self:SyncDebugController() end
    end)

    if not ok then
        pcall(self.RecordError, self, "open debug report", reason)
        if self.errorDialog then pcall(self.errorDialog.frame.Hide, self.errorDialog.frame) end
        pcall(print, "Forever Rosetta Stone: could not open error window: " .. tostring(reason))
    end
end

function Addon:ShowDebugConsole(report, preparingPick, view)
    if self.InitializeSafetyMonitoring then self:InitializeSafetyMonitoring() end
    self:ShowDiagnosticReport("Debug console", report, true, preparingPick, view)
end

function Addon:SelectDebugCapture(entry)
    if self.InitializeSafetyMonitoring then self:InitializeSafetyMonitoring() end
    local ok, report = pcall(self.GetDebugCaptureReport, self, entry)
    if not ok then
        pcall(self.RecordError, self, "debug capture report", report)
        report = self:GetDebugPickedList()
    end
    self.debugPendingSelection = entry
    self:ShowDebugConsole(report, nil, "report")
end

-- Reopens a tab with the content it had, so actions never send the player elsewhere.
function Addon:ShowDebugView(view)
    local dialog = self.errorDialog
    view = view or dialog and dialog.view or "report"
    if view == "display" then return self:ShowDebugDisplay() end
    if view == "console" then
        return self:ShowDebugConsole(dialog and dialog.viewReports.console or self:GetCommandHelp(), nil, "console")
    end
    local entry = dialog and dialog.selectedEntry
    local byID = self.debugPicker.byID
    if entry and byID[entry.kind .. ":" .. entry.id] == entry then return self:SelectDebugCapture(entry) end
    self:ShowDebugConsole(self:GetDebugWelcome(), nil, "report")
end

local function DebugNavigation(dialog, entries)
    local view = dialog.console and dialog.view or "error"
    local column, rows, edge = {}, {}, nil
    if view == "report" then
        column = { dialog.pick }
        for index = 1, #entries do column[#column + 1] = dialog.pickedButtons[index] end
        for _, button in ipairs({ dialog.clearCaptures, dialog.guide, dialog.saveReport, dialog.selectOutput }) do
            column[#column + 1] = button
        end
        rows = { { dialog.pick }, { dialog.guide, dialog.saveReport, dialog.selectOutput } }
    elseif view == "console" then
        column = { dialog.run, dialog.help, dialog.addonReport, dialog.errorLog, dialog.saveReport, dialog.selectOutput }
        rows = { { dialog.run, dialog.help }, { dialog.addonReport, dialog.errorLog, dialog.saveReport, dialog.selectOutput } }
    elseif view == "display" then
        column = { dialog.displayKinds.item, dialog.displayKinds.spell, dialog.displayKinds.quest,
            dialog.displayKinds.recipe, dialog.displayKinds.comparison, dialog.displayShow, dialog.displayPin,
            dialog.displayTarget, dialog.displayHide, dialog.displaySeparate, dialog.displayStacked }
        edge = dialog.displayKinds[dialog.displayKind]
        rows = { { dialog.displayShow }, { dialog.displayPin, dialog.displayTarget, dialog.displayHide },
            { dialog.displaySeparate, dialog.displayStacked } }
    else
        column = { dialog.saveReport, dialog.clearErrorLog, dialog.selectOutput }
        rows = { { dialog.saveReport, dialog.clearErrorLog, dialog.selectOutput } }
    end
    column[#column + 1] = dialog.close
    local tab = view == "report" and dialog.capturesTab or view == "console" and dialog.consoleTab
        or view == "display" and dialog.displayToggle or nil
    return column, rows, edge, tab
end

function Addon:RefreshDebugPickedList()
    local dialog = self.errorDialog
    if not dialog then return end
    local entries = self.debugPicker.entries
    for index, entry in ipairs(entries) do
        local button = dialog.pickedButtons[index]
        if not button then
            button = CreateFrame("Button", nil, dialog.listChild, "UIPanelButtonTemplate")
            button:SetSize(244, 26)
            button:SetPoint("TOPLEFT", dialog.listChild, "TOPLEFT", 0, -(index - 1) * 28)
            local label = button:GetFontString()
            label:SetWidth(228)
            label:SetHeight(18)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)
            button:SetScript("OnClick", Protect(function()
                if button.entry then self:SelectDebugCapture(button.entry) end
            end))
            button.OnSmartNavClick = button:GetScript("OnClick")
            button.OnSmartNavSelect = Protect(function()
                if InCombatLockdown() then return end
                local top, bottom = (index - 1) * 28, index * 28
                local offset, height = dialog.list:GetVerticalScroll(), dialog.list:GetHeight()
                if top < offset then
                    dialog.list:SetVerticalScroll(top)
                elseif bottom > offset + height then
                    dialog.list:SetVerticalScroll(math.min(bottom - height, dialog.list:GetVerticalScrollRange()))
                end
            end)
            dialog.pickedButtons[index] = button
        end
        -- Capture order is the order shown, so the player can tell the first and latest apart.
        button.entry = entry
        button:SetText(index .. ". " .. self:GetDebugKindLabel(entry.kind) .. " · " .. entry.name)
        if entry == dialog.selectedEntry then button:LockHighlight() else button:UnlockHighlight() end
        button:Show()
    end
    for index = #entries + 1, #dialog.pickedButtons do
        local button = dialog.pickedButtons[index]
        button.entry = nil
        button:Hide()
    end
    local contentHeight = math.max(1, #entries * 28)
    if dialog.listChild:GetHeight() ~= contentHeight then
        dialog.listChild:SetHeight(contentHeight)
        dialog.list:UpdateScrollChildRect()
    end
    local offset, range = dialog.list:GetVerticalScroll(), dialog.list:GetVerticalScrollRange()
    if offset > range then dialog.list:SetVerticalScroll(range) end
    dialog.empty:SetShown(#entries == 0)
    dialog.listTitle:SetText(self:DebugText("captures") .. " · " .. #entries .. "/30")
    -- Clear stays in place when the list is empty so controller focus never jumps away.
    if #entries == 0 then dialog.clearCaptures:Disable() else dialog.clearCaptures:Enable() end
    if not InCombatLockdown() then
        local column, rows, edge, selectedTab = DebugNavigation(dialog, entries)
        local visibleNavigation, seen = {}, {}
        for _, button in ipairs(column) do
            if button and button:IsShown() and not seen[button] then
                visibleNavigation[#visibleNavigation + 1] = button
                seen[button] = true
            end
        end
        -- Every direction is rewritten on each refresh so no override survives from another view.
        for index, button in ipairs(visibleNavigation) do
            local previous = visibleNavigation[index - 1] or visibleNavigation[#visibleNavigation]
            local following = visibleNavigation[index + 1] or visibleNavigation[1]
            SmartNavigation_AddJumpNavigationOverride(button, SMART_NAV_INPUT_DIRECTION.UP, previous)
            SmartNavigation_AddJumpNavigationOverride(button, SMART_NAV_INPUT_DIRECTION.DOWN, following)
            SmartNavigation_AddJumpNavigationOverride(button, SMART_NAV_INPUT_DIRECTION.LEFT, edge or previous)
            SmartNavigation_AddJumpNavigationOverride(button, SMART_NAV_INPUT_DIRECTION.RIGHT, selectedTab or following)
        end
        if edge then
            for _, button in pairs(dialog.displayKinds) do
                SmartNavigation_AddJumpNavigationOverride(button, SMART_NAV_INPUT_DIRECTION.LEFT, button)
                SmartNavigation_AddJumpNavigationOverride(button, SMART_NAV_INPUT_DIRECTION.RIGHT, dialog.displayShow)
            end
        end
        for _, buttons in ipairs(rows) do
            local row = {}
            for _, button in ipairs(buttons) do
                if seen[button] then row[#row + 1] = button end
            end
            for index, button in ipairs(row) do
                SmartNavigation_AddJumpNavigationOverride(button, SMART_NAV_INPUT_DIRECTION.LEFT,
                    row[index - 1] or edge or button)
                SmartNavigation_AddJumpNavigationOverride(button, SMART_NAV_INPUT_DIRECTION.RIGHT,
                    row[index + 1] or selectedTab or button)
            end
        end
        local tabs = { dialog.capturesTab, dialog.displayToggle, dialog.consoleTab }
        local pageButton = visibleNavigation[1]
        for index, tab in ipairs(tabs) do
            SmartNavigation_AddJumpNavigationOverride(tab, SMART_NAV_INPUT_DIRECTION.UP, tabs[index - 1] or tabs[#tabs])
            SmartNavigation_AddJumpNavigationOverride(tab, SMART_NAV_INPUT_DIRECTION.DOWN, tabs[index + 1] or tabs[1])
            SmartNavigation_AddJumpNavigationOverride(tab, SMART_NAV_INPUT_DIRECTION.LEFT, pageButton)
            SmartNavigation_AddJumpNavigationOverride(tab, SMART_NAV_INPUT_DIRECTION.RIGHT, tab)
        end
    end
    if self:IsDebugPicking() then
        dialog.report = self:GetDebugPickedList()
        dialog.editBox:SetText(dialog.report)
        dialog.stopPicking:SetText(self:DebugText("stop") .. " · " .. #entries .. "/30")
        -- New row buttons must remain click-through until picking ends.
        for _, button in ipairs(dialog.pickedButtons) do button:EnableMouse(false) end
    end
end

function Addon:SetDebugPickerView(picking)
    local dialog = self.errorDialog
    if not dialog then return end
    if picking then
        dialog.commandBox:ClearFocus()
        dialog.editBox:ClearFocus()
        dialog.mouseState = {}
        local function Disable(frame)
            dialog.mouseState[frame] = { mouse = frame:IsMouseEnabled(), wheel = frame:IsMouseWheelEnabled() }
            frame:EnableMouse(false)
            frame:EnableMouseWheel(false)
            for _, child in ipairs({ frame:GetChildren() }) do Disable(child) end
        end
        Disable(dialog.frame)
        dialog.frame:SetAlpha(0.15)
        dialog.stopHold = nil
        if InputUtil.IsGamepadUIEnabled() then
            dialog.hidingForPick = true
            dialog.frame:Hide()
            dialog.hidingForPick = nil
        end
        dialog.stopPicking:Show()
        dialog.stopPanel:Show()
        self:RefreshDebugPickedList()
    else
        for frame, previous in pairs(dialog.mouseState or {}) do
            frame:EnableMouse(previous.mouse)
            frame:EnableMouseWheel(previous.wheel)
        end
        for _, button in ipairs(dialog.pickedButtons) do button:EnableMouse(true) end
        dialog.mouseState = nil
        dialog.frame:SetAlpha(1)
        dialog.stopPicking:Hide()
        dialog.stopPanel:Hide()
    end
    self:SyncDebugController()
end

function Addon:ShowErrorDialog(returnToDebug)
    if self.InitializeSafetyMonitoring then self:InitializeSafetyMonitoring() end
    returnToDebug = returnToDebug and self.lifecycle ~= "suspended"
    local dialog = self.errorDialog
    local returnView = returnToDebug and dialog and dialog.errorReturnView
    if returnToDebug and dialog and dialog.frame:IsShown() and dialog.console then
        returnView = { report = dialog.report, view = dialog.view }
    end
    -- Addon failures and blocked actions are all in the saved log; it is the single source shown here.
    self:ShowDiagnosticReport("Error report", "Forever Rosetta Stone · State: " .. self.lifecycle
        .. " · last 10 entries kept after /reload\n\n" .. self:FormatErrorLog())
    if self.errorDialog and self.errorDialog.frame:IsShown() then
        self.errorDialog.errorReturnView = returnView
    end
end
