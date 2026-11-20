local _, Addon = ...
_G.ForeverRosettaStone = Addon
_G.BINDING_HEADER_FOREVERROSETTASTONE = "Forever Rosetta Stone"
_G.BINDING_NAME_FOREVERROSETTASTONE_READING = "Open / close quest translation"

-- Changing modes requires a reload: installed secure hooks cannot be removed safely.
function Addon:SetAPIOnly(enabled)
    assert(type(enabled) == "boolean", "API-only mode must be boolean")
    if type(ForeverRosettaStoneSettings) ~= "table" then ForeverRosettaStoneSettings = {} end
    ForeverRosettaStoneSettings.apiOnly = enabled
end

function Addon:IsAPIOnly()
    return self.apiOnly == true
end

-- A dependent addon can request a UI-free startup, without overwriting the player's choice.
function Addon:RequestAPIOnly()
    if self.lifecycle ~= "waiting" then return false, "startup already completed; reload required" end
    if type(ForeverRosettaStoneSettings) == "table" and ForeverRosettaStoneSettings.apiOnly == false then
        return false, "player selected normal mode"
    end
    self.apiOnlyRequested = true
    return true
end

local function RequestedAPIOnly()
    local setting
    if type(ForeverRosettaStoneSettings) == "table" then setting = ForeverRosettaStoneSettings.apiOnly end
    if type(setting) == "boolean" then return setting end
    return Addon.apiOnlyRequested == true
end

local function APICommand(argument)
    if argument == "on" or argument == "off" then
        Addon:SetAPIOnly(argument == "on")
        print("Forever Rosetta Stone: API-only mode " .. (argument == "on" and "enabled" or "disabled")
            .. " for the next session. Use /reload to apply.")
    elseif argument == "auto" then
        if type(ForeverRosettaStoneSettings) == "table" then ForeverRosettaStoneSettings.apiOnly = nil end
        print("Forever Rosetta Stone: automatic startup restored. Use /reload to apply.")
    elseif argument == "" or argument == "status" then
        local pending = RequestedAPIOnly()
        print("Forever Rosetta Stone: API-only mode " .. (Addon:IsAPIOnly() and "active" or "inactive")
            .. "; after reload: " .. (pending and "enabled" or "disabled") .. ".")
    else
        print("Forever Rosetta Stone: /frs api on | off | auto | status")
    end
end

function Addon:Send(event, questID)
    local nextState, effect = self:Transition(self.current, event, questID)

    if nextState == self.current and not effect then return end

    self.current = nextState

    if effect == "controller.reset" then self:ResetControllerFocus() end

    self:Render()

    if effect ~= "controller.reset" then self:SyncControllerFocus(effect == "panel.focus") end
end

function Addon:RefreshSelection()
    local details = QuestMapFrame and QuestMapFrame.DetailsFrame
    local available = self:IsFeatureEnabled("questPanel") and WorldMapFrame:IsShown() and details and details:IsVisible()
        and not (WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized())

    if not available then
        self:Send("map.close")
        return
    end

    self:Send("quest.select", details.questID or C_QuestLog.GetSelectedQuest())
end

function Addon:ToggleReading()
    self:Run("toggle reading", function()
        if self.lifecycle ~= "ready" or InCombatLockdown() then return end

        self:RefreshSelection()
        self:Send(self:IsPanelCollapsed() and "panel.open" or "panel.close")
    end)
end

local function ReleaseReaderControllers()
    for _, key in ipairs({ "questInteractionReader", "questInteractionBookmark", "bookReader", "bookBookmark" }) do
        local reader = Addon[key]
        if reader then pcall(reader.ReleaseController, reader) end
    end
end

local function Initialize()
    Addon.apiOnly = RequestedAPIOnly()
    if Addon:IsAPIOnly() then
        -- Catalog getters load their own locale packs on demand. Do not load UI preferences,
        -- install hooks, create panels, or load the UI's selected language in this mode.
        if ForeverRosettaStoneDB.InitializeLookups then ForeverRosettaStoneDB:InitializeLookups() end
        Addon:MoveLifecycle("initialize.apiOnly")
        return
    end
    Addon.tooltipRendering = nil
    Addon:LoadPreferences()
    if ForeverRosettaStoneDB.InitializeLookups then ForeverRosettaStoneDB:InitializeLookups() end
    if Addon.InitializeTooltipLabels then Addon:InitializeTooltipLabels() end
    Addon.current = Addon:CreateQuestState()
    Addon.questInteractionState, Addon.questInteractionReader = { mode = "hidden" }, nil
    Addon.questInteractionBookmark, Addon.bookBookmark, Addon.bookReader = nil, nil, nil
    Addon.bookReaderState, Addon.bookItemCandidate, Addon.openBookCache = nil, nil, nil
    Addon.contentKey, Addon.tooltipKey = nil, nil
    Addon:CreateUI()
    Addon:CreateRewardTooltips()
    Addon:CreateNameTooltips()
    Addon.questTrackerTooltip, Addon.questOfferTooltip = nil, nil
    Addon.questTrackerTooltipKey = nil
    Addon:RegisterMapMenuTranslations()
    Addon:CreateControllerFocus()
    Addon:CreateSettingsUI()
    Addon:CreateMinimapButton()
    local input = Addon:NewFrame("Frame", "ForeverRosettaStoneInput", UIParent)
    Addon.input = input

    hooksecurefunc("QuestMapFrame_ShowQuestDetails", Addon:Wrap("quest details", function()
        Addon:RefreshSelection()
    end))
    Addon:HookScript(WorldMapFrame, "OnShow", function() Addon:RefreshSelection() end)
    Addon:HookScript(WorldMapFrame, "OnHide", function()
        Addon:Send("map.close")
        Addon.tooltip:Hide()
        Addon.locationTooltip:Hide()
        Addon.mapLocationLabel:Hide()
        Addon.mapContextLabel:Hide()
        Addon.playerLocationLabel:Hide()
        Addon.mapMenuTooltip:Hide()
        Addon.mapMenuTooltip:SetWindow(nil)
    end)
    Addon:HookScript(QuestMapFrame.DetailsFrame, "OnHide", function() Addon:Send("map.close") end)
    Addon:HookScript(WorldMapFrame, "OnSizeChanged", function() Addon:RefreshSelection() end)
    Addon:HookScript(GameTooltip, "OnHide", function() Addon.tooltip:Hide() end)

    if GameMenuFrame then
        Addon:HookScript(GameMenuFrame, "OnShow", function()
            Addon:SyncControllerFocus()
            Addon:HideNameTooltips()
        end)
        Addon:HookScript(GameMenuFrame, "OnHide", function()
            Addon:SyncControllerFocus()
            Addon:RefreshNameTooltips()
        end)
    end

    Addon:HookScript(SettingsPanel, "OnShow", function()
        Addon:SyncControllerFocus()
        Addon.mapContextLabel:Hide()
        Addon:RefreshNameTooltips()
    end)
    Addon:HookScript(SettingsPanel, "OnHide", function()
        Addon:SyncControllerFocus()
        Addon:RefreshNameTooltips()
    end)

    local update = Addon:Wrap("OnUpdate", function()
        Addon:RefreshSelection()
        Addon:ShowMapLocationLabel()
        Addon:ShowMapContext()
        Addon:ShowTranslationTooltip()
        Addon:UpdateRewardTooltips()
        Addon:UpdateTooltipComponents()
    end)
    local elapsedSeconds, inputGeneration = 0, Addon.generation
    -- Throttle before the safety wrapper allocates its arguments and protected-call closures.
    input:SetScript("OnUpdate", function(_, deltaSeconds)
        if inputGeneration ~= Addon.generation or Addon.lifecycle == "suspended" then return end

        elapsedSeconds = elapsedSeconds + deltaSeconds

        if elapsedSeconds < 0.1 then return end

        elapsedSeconds = 0
        update()
    end)

    local events = Addon:NewFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("QUEST_LOG_UPDATE")
    events:RegisterEvent("PLAYER_LOGOUT")
    local handleEvent = Addon:Wrap("quest events", function(_, event)
        if event == "PLAYER_LOGOUT" then
            Addon:StopBenchmark("logout")
        elseif event == "PLAYER_REGEN_ENABLED" then
            Addon:RefreshSelection()
            Addon:RefreshNameTooltips()
        elseif event == "QUEST_LOG_UPDATE" then
            Addon:RefreshSelection()
        end
    end)
    local generation = Addon.generation
    events:SetScript("OnEvent", function(_, event)
        if generation ~= Addon.generation then return end

        if event == "PLAYER_REGEN_ENABLED" then pcall(Addon.RestoreTooltipSources, Addon) end

        -- A failure in combat must still release native focus after combat ends.
        if event == "PLAYER_REGEN_ENABLED" and Addon.lifecycle == "suspended" then
            pcall(Addon.ReleaseControllerFocus, Addon)
            ReleaseReaderControllers()
            return
        end

        handleEvent(nil, event)
    end)
    if not Addon:MoveLifecycle("initialize.ready") then return end
    Addon:RefreshSelection()
end

function Addon:Restart()
    if self:IsAPIOnly() then
        print("Forever Rosetta Stone: API-only mode is active. Use /frs api off, then /reload to restore the UI.")
        return
    end
    if InCombatLockdown() then
        pcall(print, "Forever Rosetta Stone: leave combat before resetting.")
        return
    end

    self:StopBenchmark("addon reset")
    self:HideNameTooltips()

    if not self:MoveLifecycle("reset") then return end

    ReleaseReaderControllers()
    self.generation = self.generation + 1
    if self.questReport then
        self.questReport.frame:Hide()
        self:SyncQuestReportController()
        self.questReport = nil
    end
    self:ReleaseControllerFocus()

    if self.errorDialog then self.errorDialog.frame:Hide() end

    for index = #self.frames, 1, -1 do
        local frame = self.frames[index]
        pcall(frame.Hide, frame)
        pcall(frame.UnregisterAllEvents, frame)
    end

    self.frames = {}
    self:Run("initialize", Initialize)
end

Addon:Run("startup", function()
    local login = Addon:NewFrame("Frame")
    login:RegisterEvent("PLAYER_LOGIN")
    Addon:SetScript(login, "OnEvent", function()
        login:UnregisterAllEvents()

        if Addon:MoveLifecycle("initialize.start") then Initialize() end
    end)
end)

SLASH_FOREVERROSETTASTONE1 = "/frs"
SlashCmdList.FOREVERROSETTASTONE = function(command)
    local ok, reason = pcall(function()
        local mode, argument = (command or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
        if mode == "api" then APICommand(argument); return end
        if Addon:IsAPIOnly() then
            print("Forever Rosetta Stone: API-only mode is active. Use /frs api off, then /reload to restore the UI.")
            return
        end
        local action = (command or ""):lower():match("^%s*(%S+)")

        if action == "reset" or action == "settings" or action == "bench"
            or action == "language" or action == "quest" then
            Addon:RunDebugCommand(command)
        else
            -- Let native chat finish clearing its edit box before opening report UI.
            C_Timer.After(0, function() Addon:RunDebugCommand(command) end)
        end
    end)

    if not ok then Addon:Suspend("command", tostring(reason)) end
end
