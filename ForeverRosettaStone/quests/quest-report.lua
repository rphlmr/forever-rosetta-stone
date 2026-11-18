local _, Addon = ...

local transitions = {
    closed = { open = "waiting" },
    waiting = { result = "ready", close = "closed" },
    ready = { close = "closed" },
}

function Addon:CanReportQuest(questID)
    return self.lifecycle == "ready" and not InCombatLockdown() and self:IsReadableEntityID(questID)
        and not (self.questReport and self.questReport.frame:IsShown())
end

function Addon:CanOpenQuestOptions()
    return self.panel:IsVisible() and self.current.mode ~= "unavailable" and self:CanReportQuest(self.current.questID)
end

-- Without an explicit quest ID the menu belongs to the journal panel's displayed quest.
function Addon:ShowQuestOptions(owner, questID)
    if questID == nil then
        if not self:CanOpenQuestOptions() then return end
        questID = self.current.questID
    elseif not self:CanReportQuest(questID) then
        return
    end
    -- A context menu opened by addon code taints the controller manager: its MenuProxy close
    -- callback unsuspends focus from our call stack and blocks every later native action. The
    -- controller therefore goes straight to the menu's only action, through the secure report popup.
    if InputUtil.IsGamepadUIEnabled() then
        self:ShowQuestReport(questID)
        return
    end
    MenuUtil.CreateContextMenu(owner or self.panel, function(_, root)
        root:CreateTitle("Forever Rosetta Stone")
        root:CreateButton(self:SettingsText("questBugged"), function() self:ShowQuestReport(questID) end)
    end)
end

local function Read(record, name, callback, ...)
    if type(callback) ~= "function" then return nil end

    local ok, first, second = pcall(callback, ...)
    if ok then return first, second end

    record.apiErrors[#record.apiErrors + 1] = { api = name, message = tostring(first) }
end

local function Serialize(value)
    if type(value) == "string" then return string.format("%q", value) end
    if type(value) ~= "table" then return tostring(value) end

    local keys, lines = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(first, second) return tostring(first) < tostring(second) end)

    for _, key in ipairs(keys) do
        lines[#lines + 1] = "[" .. Serialize(key) .. "] = " .. Serialize(value[key])
    end

    return "{\n" .. table.concat(lines, ",\n") .. "\n}"
end

function Addon:MoveQuestReport(event)
    local dialog = self.questReport
    local nextState = transitions[dialog.state][event]
    if not nextState then return false end

    dialog.state = nextState
    return true
end

function Addon:CaptureQuestReport(record, tooltip)
    local questID, api = record.questID, C_QuestLog
    record.title = Read(record, "GetTitleForQuestID", api.GetTitleForQuestID, questID)
    record.objectives = Read(record, "GetQuestObjectives", api.GetQuestObjectives, questID)
    local index = Read(record, "GetLogIndexForQuestID", api.GetLogIndexForQuestID, questID)

    -- Full prose is only available through a verified quest-log index.
    if type(index) == "number" and index > 0
        and Read(record, "GetQuestIDForLogIndex", api.GetQuestIDForLogIndex, index) == questID then
        record.description, record.summary = Read(record, "GetQuestLogQuestText", GetQuestLogQuestText, index)
        record.questLogInfo = Read(record, "GetInfo", api.GetInfo, index)
    end
    record.isComplete = Read(record, "IsComplete", api.IsComplete, questID)
    record.isFailed = Read(record, "IsFailed", api.IsFailed, questID)

    if not tooltip then
        record.questTagInfo = Read(record, "GetQuestTagInfo", api.GetQuestTagInfo, questID)
        record.questLink = Read(record, "GetQuestLink", api.GetQuestLink, questID)
        record.tooltipData = Read(record, "C_TooltipInfo.GetHyperlink",
            C_TooltipInfo and C_TooltipInfo.GetHyperlink, "quest:" .. questID)
        return
    end
    tooltip:ClearLines()
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    Read(record, "GameTooltip.SetHyperlink", tooltip.SetHyperlink, tooltip, "quest:" .. questID)
    record.tooltipLines = {}

    for line = 1, tooltip:NumLines() do
        local left = _G[tooltip:GetName() .. "TextLeft" .. line]
        local right = _G[tooltip:GetName() .. "TextRight" .. line]
        local leftText, rightText = left and left:GetText(), right and right:GetText()

        if leftText or rightText then
            record.tooltipLines[#record.tooltipLines + 1] = { left = leftText, right = rightText }
        end
    end

    tooltip:Hide()
end

function Addon:FinishQuestReport(outcome, message)
    if not self:MoveQuestReport("result") then return end

    local dialog = self.questReport
    local record = dialog.record
    record.requestOutcome, record.requestError = outcome, message
    self:CaptureQuestReport(record, dialog.tooltip)
    dialog.text = "## Quest report: " .. record.questID
        .. "\n\nWhat is wrong?\n[Describe the problem and what you expected.]"
        .. "\n\nClient text is included exactly as returned; its language has not been verified."
        .. "\nFull summary and description are only available when the quest is in your quest log."
        .. "\n\n```lua\n" .. Serialize(record) .. "\n```"
    dialog.measure:SetText(dialog.text)
    dialog.edit:SetHeight(math.max(280, dialog.measure:GetStringHeight() + 16))
    dialog.edit:SetText(dialog.text)
    dialog.scroll:SetVerticalScroll(0)
    dialog.copy:Enable()
end

function Addon:SyncQuestReportController()
    local dialog = self.questReport
    if not dialog or InCombatLockdown() then return end

    local manager = GamepadMode and GamepadMode.FrameControlsManager
    if not manager then return end

    local available = self.lifecycle == "ready" and dialog.frame:IsShown() and InputUtil.IsGamepadUIEnabled()
        and not (GameMenuFrame and GameMenuFrame:IsShown())
        and not (SettingsPanel and SettingsPanel:IsShown())
        and not (self.errorDialog and self.errorDialog.frame:IsShown() and not self:IsDebugPicking())

    if available and not dialog.registered then
        dialog.registered = true
        manager:FrameShown(dialog.frame, false, true)
    elseif not available and dialog.registered then
        dialog.registered = nil
        manager:FrameHidden(dialog.frame)
        SmartNavigation:RemovePanelInfo(dialog.frame)
    end
end

function Addon:CreateQuestReport()
    local frame = self:NewFrame("Frame", "ForeverRosettaStoneQuestReport", UIParent, "BackdropTemplate")
    frame:Hide()
    frame:SetSize(660, 440)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetBackdrop({
        bgFile = [[Interface\DialogFrame\UI-DialogBox-Background-Dark]],
        edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    table.insert(UISpecialFrames, frame:GetName())

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 18, -18)
    title:SetText("Forever Rosetta Stone: Quest bug report")
    local instructions = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    instructions:SetPoint("TOPLEFT", 18, -46)
    instructions:SetWidth(610)
    instructions:SetJustifyH("LEFT")
    instructions:SetText("Select Copy report, then press Ctrl+C / Cmd+C. Open a GitHub issue and paste the report.\n"
        .. "GitHub: [issue URL coming soon]")

    local close = self:NewFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    self:SetScript(close, "OnClick", function() frame:Hide() end)
    frame.CloseButton = close

    local copy = self:NewFrame("Button", nil, frame, "UIPanelButtonTemplate")
    copy:SetSize(140, 24)
    copy:SetPoint("BOTTOMLEFT", 18, 16)
    copy:SetText("Copy report")
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("LEFT", copy, "RIGHT", 12, 0)
    hint:SetText("Selects all text. Use your keyboard to copy.")

    local scroll = self:NewFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -92)
    scroll:SetPoint("BOTTOMRIGHT", -40, 52)
    local edit = self:NewFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetFontObject(ChatFontNormal)
    edit:SetSize(598, 280)
    scroll:SetScrollChild(edit)
    local measure = frame:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    measure:SetWidth(598)
    measure:Hide()
    local tooltip = self:NewFrame("GameTooltip", "ForeverRosettaStoneQuestReportTooltip", UIParent,
        "GameTooltipTemplate")
    tooltip:Hide()
    self.questReport = { frame = frame, edit = edit, scroll = scroll, measure = measure,
        copy = copy, tooltip = tooltip, state = "closed" }

    self:SetScript(copy, "OnClick", function()
        if self.questReport.state ~= "ready" then return end
        edit:SetFocus()
        edit:HighlightText()
    end)
    self:SetScript(edit, "OnEditFocusGained", function() edit:HighlightText() end)
    self:SetScript(edit, "OnEscapePressed", function() frame:Hide() end)
    self:SetScript(frame, "OnHide", function()
        self:MoveQuestReport("close")
        edit:ClearFocus()
        self:SyncQuestReportController()
        self:SyncControllerFocus(true)
        local reader = self.questInteractionReader
        if reader then
            reader:SyncController(reader.reportOwner)
            reader:SyncTarget()
            reader.reportOwner = nil
        end
    end)
    frame.FocusGamepad = self:Wrap("focus quest report", function()
        SmartNavigation:SetScrollFrameForFrame(frame, scroll)
        SmartNavigation_MarkScrollFrameMaintainPreviousButtonOnScroll(scroll)
        self:ClearGamepadTarget(frame)
    end)
    frame.UnfocusGamepad = self:Wrap("leave quest report", function()
        if not InCombatLockdown() then SmartNavigation:SetScrollFrameForFrame(frame, nil) end
    end)
    frame.SmartNavigationCloseHandler = self:Wrap("close quest report", function()
        frame:Hide()
        return true
    end, true)
    SmartNavigation_AddBidirectionalJumpNavigationOverride(close, SMART_NAV_INPUT_DIRECTION.DOWN, copy)
    SmartNavigation_MarkFrameIgnored(edit)
    InputUtil.RegisterForInterfaceTransitions(frame, self:Wrap("quest report input", function()
        self:SyncQuestReportController()
    end))
    frame:RegisterEvent("QUEST_DATA_LOAD_RESULT")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:SetScript(frame, "OnEvent", function(_, event, questID, success)
        if event == "PLAYER_REGEN_ENABLED" then
            self:SyncQuestReportController()
        elseif self.questReport.state == "waiting" and self.questReport.record.questID == questID then
            self:FinishQuestReport(success and "success" or "failed")
        end
    end)
    self:SetScript(frame, "OnUpdate", function()
        if self.questReport.state == "waiting" and GetTime() >= self.questReport.deadline then
            self:FinishQuestReport("timeout")
        end
        self:SyncQuestReportController()
    end)
end

function Addon:ShowQuestReport(questID)
    if InCombatLockdown() then return end
    if type(questID) ~= "number" or questID < 1 or questID % 1 ~= 0 or questID > 2147483647 then return end
    if not self.questReport then self:CreateQuestReport() end
    if not self:MoveQuestReport("open") then return end

    local dialog = self.questReport
    local version, build, buildDate, interface = GetBuildInfo()
    dialog.record = { schemaVersion = 1, questID = questID, locale = GetLocale(),
        version = version, build = build, buildDate = buildDate, interface = interface,
        translationLocale = self:GetTargetLocale(), catalogVersion = ForeverRosettaStoneDB.catalogVersion,
        apiErrors = {} }
    dialog.record.addonVersion = Read(dialog.record, "GetAddOnMetadata", C_AddOns.GetAddOnMetadata,
        "ForeverRosettaStone", "Version")
    dialog.deadline = GetTime() + 5
    dialog.edit:SetText("Loading quest " .. questID .. "...")
    dialog.copy:Disable()
    dialog.frame:Show()
    self:SyncControllerFocus()
    if self.questInteractionReader then self.questInteractionReader:SyncController() end
    self:SyncQuestReportController()
    local ok, reason = pcall(C_QuestLog.RequestLoadQuestByID, questID)
    if not ok then self:FinishQuestReport("request_error", tostring(reason)) end
end
