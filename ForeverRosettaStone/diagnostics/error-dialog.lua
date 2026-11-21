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
    sidebar:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -145)
    sidebar:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 12, 46)
    sidebar:SetWidth(232)
    local contentInset = ProfessionPanel()
    contentInset:SetPoint("TOPLEFT", window, "TOPLEFT", 252, -145)
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
    selectOutput:SetSize(160, 24)
    selectOutput:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -18, 16)
    selectOutput:SetText(Addon:DebugText("copy"))
    selectOutput:SetScript("OnClick", Protect(function()
        edit:SetFocus()
        edit:HighlightText()
    end))
    Addon.errorDialog.selectOutput = selectOutput

    local command = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
    command:SetSize(520, 24)
    command:SetPoint("TOPLEFT", window, "TOPLEFT", 24, -78)
    command:SetAutoFocus(false)
    command:SetMaxLetters(0)
    command:SetTextColor(1, 1, 1, 1)
    local commandLabel = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    commandLabel:SetPoint("BOTTOMLEFT", command, "TOPLEFT", 0, 4)
    commandLabel:SetText(Addon:DebugText("command"))
    local run = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    run:SetSize(70, 24)
    run:SetPoint("LEFT", command, "RIGHT", 10, 0)
    run:SetText(Addon:DebugText("run"))
    local function Execute()
        command:ClearFocus()
        Addon:RunDebugCommand(command:GetText())
    end
    command:SetScript("OnEnterPressed", Protect(Execute))
    command:SetScript("OnEscapePressed", Protect(function() overlay:Hide() end))
    run:SetScript("OnClick", Protect(Execute))
    local pick = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    pick:SetSize(150, 24)
    pick:SetPoint("LEFT", run, "RIGHT", 10, 0)
    pick:SetText(Addon:DebugText("inspect"))
    pick:SetScript("OnClick", Protect(function() Addon:MoveDebugPicker("start") end))
    local help = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    help:SetSize(90, 24)
    help:SetPoint("LEFT", pick, "RIGHT", 10, 0)
    help:SetText(Addon:DebugText("helpButton"))
    help:SetScript("OnClick", Protect(function()
        command:ClearFocus()
        command:SetText("help")
        Addon:RunDebugCommand("help")
    end))

    local list = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    list:SetPoint("TOPLEFT", window, "TOPLEFT", 18, -118)
    list:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 18, 50)
    list:SetWidth(210)
    local listChild = CreateFrame("Frame", nil, list)
    listChild:SetSize(190, 1)
    list:SetScrollChild(listChild)
    Addon.errorDialog.commandBox, Addon.errorDialog.run, Addon.errorDialog.pick = command, run, pick
    Addon.errorDialog.help = help
    local homeButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    homeButton:SetSize(90, 24)
    homeButton:SetPoint("LEFT", help, "RIGHT", 10, 0)
    homeButton:SetText(Addon:DebugText("home"))
    homeButton:SetScript("OnClick", Protect(function() Addon:RunDebugCommand("") end))
    Addon.errorDialog.homeButton, Addon.errorDialog.commandLabel = homeButton, commandLabel
    local addonReport = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    addonReport:SetSize(150, 24)
    addonReport:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 18, 16)
    addonReport:SetText(Addon:DebugText("addon"))
    addonReport:SetScript("OnClick", Protect(function()
        command:ClearFocus()
        Addon:RunDebugCommand("status")
    end))
    local clearCaptures = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    clearCaptures:SetSize(150, 24)
    clearCaptures:SetPoint("TOPRIGHT", window, "TOPRIGHT", -22, -40)
    clearCaptures:SetText(Addon:DebugText("clear"))
    clearCaptures:SetScript("OnClick", Protect(function()
        command:ClearFocus()
        Addon:RunDebugCommand("clear")
    end))
    Addon.errorDialog.addonReport, Addon.errorDialog.clearCaptures = addonReport, clearCaptures
    local saveReport = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    saveReport:SetSize(150, 24)
    saveReport:SetPoint("LEFT", addonReport, "RIGHT", 10, 0)
    saveReport:SetText(Addon:DebugText("save"))
    saveReport:SetScript("OnClick", Protect(function()
        Addon.preferences.debugReport = Addon.errorDialog.report
        hint:SetText(Addon:DebugText("saved"))
    end))
    Addon.errorDialog.saveReport = saveReport
    local errorLog = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    errorLog:SetSize(150, 24)
    errorLog:SetPoint("LEFT", saveReport, "RIGHT", 10, 0)
    errorLog:SetText(Addon:DebugText("errorLog"))
    errorLog:SetScript("OnClick", Protect(function() Addon:ShowErrorDialog(true) end))
    Addon.errorDialog.errorLog = errorLog
    local clearErrorLog = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    clearErrorLog:SetSize(180, 24)
    clearErrorLog:SetPoint("LEFT", saveReport, "RIGHT", 10, 0)
    clearErrorLog:SetText(Addon:DebugText("clearErrorLog"))
    clearErrorLog:SetScript("OnClick", Protect(function()
        Addon:ClearErrorLog()
        Addon:ShowErrorDialog(true)
    end))
    clearErrorLog:Hide()
    Addon.errorDialog.clearErrorLog = clearErrorLog
    local captureBar = CreateFrame("StatusBar", nil, window)
    captureBar:SetPoint("TOPLEFT", window, "TOPLEFT", 82, -42)
    captureBar:SetPoint("RIGHT", clearCaptures, "LEFT", -12, 0)
    captureBar:SetHeight(18)
    captureBar:SetMinMaxValues(0, 30)
    captureBar:SetStatusBarTexture([[Interface\TargetingFrame\UI-StatusBar]])
    captureBar:SetStatusBarColor(0.15, 0.7, 0.85)
    local barBackground = captureBar:CreateTexture(nil, "BACKGROUND")
    barBackground:SetPoint("TOPLEFT", captureBar, "TOPLEFT", -2, 3)
    barBackground:SetPoint("BOTTOMRIGHT", captureBar, "BOTTOMRIGHT", 2, -3)
    barBackground:SetAtlas("Profession-ProgressBar-BG")
    local barBorder = captureBar:CreateTexture(nil, "OVERLAY")
    barBorder:SetPoint("TOPLEFT", captureBar, "TOPLEFT", -2, 3)
    barBorder:SetAtlas("Profession-ProgressBar-frame", true)
    barBorder:SetTextureSliceMargins(8, 6, 8, 6)
    barBorder:SetPoint("RIGHT", captureBar, "RIGHT", 2, 0)
    local captureCount = captureBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    captureCount:SetPoint("CENTER")
    Addon.errorDialog.captureBar, Addon.errorDialog.captureCount = captureBar, captureCount
    local function ControllerAction(button)
        button.OnSmartNavClick = Protect(function() button:GetScript("OnClick")(button) end)
    end
    for _, button in ipairs({ close, run, pick, help, homeButton, addonReport, clearCaptures, saveReport,
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

    local listTitle = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listTitle:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 12, -14)
    local empty = listChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    empty:SetPoint("TOPLEFT", listChild, "TOPLEFT", 4, -8)
    empty:SetWidth(180)
    empty:SetJustifyH("LEFT")
    empty:SetText(Addon:DebugText("empty"))
    local home = CreateFrame("Frame", nil, window)
    home:SetPoint("TOPLEFT", window, "TOPLEFT", 18, -108)
    home:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -18, 56)
    local introduction = home:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    introduction:SetPoint("TOPLEFT", home, "TOPLEFT", 20, -24)
    introduction:SetText(Addon:DebugText("title"))
    local introductionText = home:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    introductionText:SetPoint("TOPLEFT", introduction, "BOTTOMLEFT", 0, -12)
    introductionText:SetPoint("RIGHT", home, "RIGHT", -24, 0)
    introductionText:SetJustifyH("LEFT")
    introductionText:SetText(Addon:DebugText("pickHint"))
    Addon.errorDialog.homeCards = {}
    local function Action(key, description, index, callback)
        local card = CreateFrame("Frame", nil, home, "BackdropTemplate")
        card:SetPoint("TOPLEFT", home, "TOPLEFT", 4, -96 - (index - 1) * 116)
        card:SetSize(940, 108)
        card:SetBackdrop({
            bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
            edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        card:SetBackdropColor(0.06, 0.045, 0.025, 0.85)
        card:SetBackdropBorderColor(0.48, 0.34, 0.16, 1)
        local heading = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        heading:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -22)
        heading:SetPoint("RIGHT", card, "RIGHT", -290, 0)
        heading:SetJustifyH("LEFT")
        heading:SetText(Addon:DebugText(key))
        local button = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
        button:SetPoint("RIGHT", card, "RIGHT", -24, 0)
        button:SetSize(240, 30)
        button:SetText(Addon:DebugText(key))
        button:SetScript("OnClick", Protect(callback))
        ControllerAction(button)
        local text = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -12)
        text:SetPoint("RIGHT", card, "RIGHT", -290, 0)
        text:SetJustifyH("LEFT")
        text:SetText(Addon:DebugText(description))
        Addon.errorDialog.homeCards[index] = card
        return button
    end
    Addon.errorDialog.inspectAction = Action("inspect", "inspectHint", 1, function() Addon:MoveDebugPicker("start") end)
    Addon.errorDialog.reportAction = Action("addon", "addonHint", 2, function() Addon:RunDebugCommand("status") end)
    Addon.errorDialog.shareAction = Action("help", "shareHint", 3, function() Addon:RunDebugCommand("report") end)
    Addon.errorDialog.home, Addon.errorDialog.listTitle, Addon.errorDialog.empty = home, listTitle, empty
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
        if Addon:IsDebugPicking() then returnView = { report = Addon:GetDebugPickedList() } end
        Addon.errorDialog.errorReturnView = nil
        if Addon.MoveDebugPicker then Addon:MoveDebugPicker("close") end
        stop:Hide()
        stopPanel:Hide()
        Addon:SyncDebugController()
        if returnView then
            -- Let native OnHide navigation cleanup finish before reusing this window.
            C_Timer.After(0, Protect(function()
                if overlay:IsShown() then return end
                if returnView.display then Addon:ShowDebugDisplay()
                else Addon:ShowDebugConsole(returnView.report) end
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

function Addon:ShowDiagnosticReport(title, report, console, preparingPick)
    local ok, reason = pcall(function()
        if not self.errorDialog then CreateErrorDialog() end

        local dialog = self.errorDialog
        dialog.errorReturnView = nil
        self:MoveDebugPreview("dismiss")
        if self:IsDebugPicking() then self:MoveDebugPicker("close") end
        dialog.display:Hide()
        local home = console and report == self:GetDebugWelcome()
        if home then
            dialog.consoleTab:SetChecked(true)
            dialog.capturesTab:SetChecked(false)
        else
            dialog.consoleTab:SetChecked(false)
            dialog.capturesTab:SetChecked(true)
        end
        dialog.displayToggle:SetChecked(false)
        dialog.console = console
        local width = console and math.min(1000, UIParent:GetWidth() - 40) or 660
        dialog.window:SetSize(width, console and math.min(620, UIParent:GetHeight() - 40) or 420)
        dialog.commandBox:SetWidth(width - 510)
        dialog.commandBox:ClearAllPoints()
        dialog.commandBox:SetPoint("TOPLEFT", dialog.window, "TOPLEFT", 24, -118)
        dialog.list:ClearAllPoints()
        dialog.list:SetPoint("TOPLEFT", dialog.window, "TOPLEFT", 24, -180)
        dialog.list:SetPoint("BOTTOMLEFT", dialog.window, "BOTTOMLEFT", 18, 50)
        for _, frame in ipairs({ dialog.commandBox, dialog.run, dialog.pick, dialog.help, dialog.list,
            dialog.homeButton, dialog.commandLabel, dialog.listTitle, dialog.addonReport,
            dialog.errorLog }) do
            frame:SetShown(console and not home)
        end
        dialog.saveReport:SetShown(not home)
        dialog.clearErrorLog:SetShown(not console and title == "Error report")
        dialog.saveReport:ClearAllPoints()
        if console then dialog.saveReport:SetPoint("LEFT", dialog.addonReport, "RIGHT", 10, 0)
        else dialog.saveReport:SetPoint("BOTTOMLEFT", dialog.window, "BOTTOMLEFT", 18, 16) end
        for _, frame in ipairs({ dialog.displayToggle, dialog.consoleTab, dialog.capturesTab,
            dialog.clearCaptures, dialog.captureBar }) do frame:SetShown(console) end
        dialog.sidebar:SetShown(console and not home)
        dialog.contentInset:SetShown(not home)
        dialog.contentInset:ClearAllPoints()
        dialog.contentInset:SetPoint("TOPLEFT", dialog.window, "TOPLEFT", console and 252 or 12, console and -145 or -68)
        dialog.contentInset:SetPoint("BOTTOMRIGHT", dialog.window, "BOTTOMRIGHT", -30, 46)
        dialog.home:SetShown(home)
        dialog.hint:SetShown(not console)
        dialog.selectOutput:SetShown(not home)
        for index, card in ipairs(dialog.homeCards) do
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", dialog.home, "TOPLEFT", 4, -96 - (index - 1) * 116)
            card:SetSize(width - 44, 108)
        end
        dialog.scroll:SetShown(not home)
        if home then
            dialog.selectOutput:Disable()
            dialog.saveReport:Disable()
        else
            dialog.selectOutput:Enable()
            dialog.saveReport:Enable()
        end
        dialog.scroll:ClearAllPoints()
        dialog.scroll:SetPoint("TOPLEFT", dialog.window, "TOPLEFT", console and 270 or 18, console and -165 or -76)
        dialog.scroll:SetPoint("BOTTOMRIGHT", dialog.window, "BOTTOMRIGHT", -40, 50)
        dialog.editBox:SetWidth(console and width - 310 or 598)
        dialog.measure:SetWidth(console and width - 318 or 590)
        dialog.title:SetText("Forever Rosetta Stone · " .. (console and self:DebugText("title") or title))
        dialog.hint:SetWidth(width - 104)
        dialog.hint:SetText(console and self:DebugText("inspectHint") or self:DebugText("reportHint"))
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

function Addon:ShowDebugConsole(report, preparingPick)
    if self.InitializeSafetyMonitoring then self:InitializeSafetyMonitoring() end
    self:ShowDiagnosticReport("Debug console", report, true, preparingPick)
end

function Addon:RefreshDebugPickedList()
    local dialog = self.errorDialog
    if not dialog then return end
    local entries = self.debugPicker.entries
    for index, entry in ipairs(entries) do
        local button = dialog.pickedButtons[index]
        if not button then
            button = CreateFrame("Button", nil, dialog.listChild, "UIPanelButtonTemplate")
            button:SetSize(190, 26)
            button:SetPoint("TOPLEFT", dialog.listChild, "TOPLEFT", 0, -(index - 1) * 28)
            local label = button:GetFontString()
            label:SetWidth(174)
            label:SetHeight(18)
            label:SetWordWrap(false)
            dialog.pickedButtons[index] = button
        end
        button:SetText(self:GetDebugKindLabel(entry.kind) .. " · " .. entry.name)
        button:SetScript("OnClick", Protect(function()
            self:ShowDebugConsole(self:GetEntityDebugReport(entry.kind, entry.id))
        end))
        button.OnSmartNavClick = button:GetScript("OnClick")
        button.OnSmartNavSelect = Protect(function()
            if InCombatLockdown() then return end
            dialog.list:SetVerticalScroll(math.max(0, (index - 1) * 28 - dialog.list:GetHeight() + 28))
        end)
        button:Show()
    end
    for index = #entries + 1, #dialog.pickedButtons do dialog.pickedButtons[index]:Hide() end
    dialog.listChild:SetHeight(math.max(1, #entries * 28))
    dialog.empty:SetShown(#entries == 0)
    dialog.listTitle:SetText(self:DebugText("captures") .. " · " .. #entries .. "/30")
    dialog.captureBar:SetValue(#entries)
    dialog.captureCount:SetText(self:DebugText("count", #entries, 30))
    if not InCombatLockdown() then
        local navigation = dialog.home:IsShown()
            and { dialog.inspectAction, dialog.reportAction, dialog.shareAction, dialog.pick, dialog.help,
                dialog.homeButton, dialog.clearCaptures, dialog.close }
            or { dialog.addonReport, dialog.pick, dialog.help, dialog.homeButton, dialog.clearCaptures, dialog.saveReport,
                dialog.selectOutput, dialog.close, dialog.errorLog, dialog.clearErrorLog }
        if dialog.display:IsShown() then
            navigation = {}
            for _, button in ipairs(dialog.displayNavigation) do navigation[#navigation + 1] = button end
            for _, button in ipairs({ dialog.consoleTab, dialog.close }) do
                navigation[#navigation + 1] = button
            end
        end
        if not dialog.display:IsShown() and not dialog.home:IsShown() then
            for index = 1, #entries do navigation[#navigation + 1] = dialog.pickedButtons[index] end
        end
        local visibleNavigation, seen = {}, {}
        for _, button in ipairs(navigation) do
            if button:IsShown() and button ~= dialog.consoleTab and button ~= dialog.capturesTab
                and button ~= dialog.displayToggle and not seen[button] then
                visibleNavigation[#visibleNavigation + 1] = button
                seen[button] = true
            end
        end
        for index, button in ipairs(visibleNavigation) do
            local previous = visibleNavigation[index - 1] or visibleNavigation[#visibleNavigation]
            local following = visibleNavigation[index + 1] or visibleNavigation[1]
            for _, direction in ipairs({ "LEFT", "UP" }) do
                SmartNavigation_AddJumpNavigationOverride(button, SMART_NAV_INPUT_DIRECTION[direction], previous)
            end
            for _, direction in ipairs({ "RIGHT", "DOWN" }) do
                SmartNavigation_AddJumpNavigationOverride(button, SMART_NAV_INPUT_DIRECTION[direction], following)
            end
        end
        local tabs = { dialog.consoleTab, dialog.capturesTab, dialog.displayToggle }
        local selectedTab = dialog.home:IsShown() and dialog.consoleTab
            or dialog.display:IsShown() and dialog.displayToggle or dialog.capturesTab
        for _, button in ipairs(visibleNavigation) do
            if selectedTab:IsShown() then
                SmartNavigation_AddJumpNavigationOverride(button, SMART_NAV_INPUT_DIRECTION.RIGHT, selectedTab)
            end
        end
        local function LinkRow(buttons, leftEdge)
            local row = {}
            for _, button in ipairs(buttons) do
                if button:IsShown() then row[#row + 1] = button end
            end
            for index, button in ipairs(row) do
                SmartNavigation_AddJumpNavigationOverride(button, SMART_NAV_INPUT_DIRECTION.LEFT,
                    row[index - 1] or leftEdge or button)
                SmartNavigation_AddJumpNavigationOverride(button, SMART_NAV_INPUT_DIRECTION.RIGHT,
                    row[index + 1] or selectedTab:IsShown() and selectedTab or button)
            end
        end
        LinkRow({ dialog.run, dialog.pick, dialog.help, dialog.homeButton })
        LinkRow({ dialog.addonReport, dialog.saveReport, dialog.errorLog, dialog.clearErrorLog, dialog.selectOutput })
        if dialog.display:IsShown() then
            local kindButton = dialog.displayKinds[dialog.displayKind]
            for _, button in pairs(dialog.displayKinds) do
                SmartNavigation_AddJumpNavigationOverride(button, SMART_NAV_INPUT_DIRECTION.RIGHT, dialog.displayShow)
            end
            LinkRow({ dialog.displayShow, dialog.displayPin }, kindButton)
            LinkRow({ dialog.displayTarget, dialog.displayHide }, kindButton)
            LinkRow({ dialog.displaySeparate, dialog.displayStacked }, kindButton)
        end
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
        returnView = { report = dialog.report, display = dialog.display:IsShown() }
    end
    -- Addon failures and blocked actions are all in the saved log; it is the single source shown here.
    self:ShowDiagnosticReport("Error report", "Forever Rosetta Stone · State: " .. self.lifecycle
        .. " · last 10 entries kept after /reload\n\n" .. self:FormatErrorLog())
    if self.errorDialog and self.errorDialog.frame:IsShown() then
        self.errorDialog.errorReturnView = returnView
    end
end
