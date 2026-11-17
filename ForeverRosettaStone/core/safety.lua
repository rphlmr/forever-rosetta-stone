local _, Addon = ...

Addon.lifecycle = "waiting"
Addon.generation = 0
Addon.frames = {}
Addon.errors = {}
Addon.blockedActions = {}
Addon.errorLog = {}

local ERROR_LOG_LIMIT = 10
local ERROR_ENTRY_LIMIT = 12000

function Addon:LoadErrorLog()
    local saved = self.preferences.errorLog
    if saved == self.errorLog then return end
    local history = {}
    if type(saved) == "table" then
        for index = math.max(1, #saved - ERROR_LOG_LIMIT + 1), #saved do
            if type(saved[index]) == "string" then
                history[#history + 1] = saved[index]:sub(1, ERROR_ENTRY_LIMIT)
            end
        end
    end
    for _, entry in ipairs(self.errorLog) do history[#history + 1] = entry end
    while #history > ERROR_LOG_LIMIT do table.remove(history, 1) end
    self.errorLog, self.preferences.errorLog = history, history
end

-- Entries are "<time> · <client>[ · ×N]\n<label>: <reason>". A repeat of the previous entry's body
-- updates its time and count instead of pushing older, different entries out of the log.
local ERROR_HEADER_ROOM = 80
local sessionStart = date("%Y-%m-%d %H:%M:%S")

local function SplitErrorEntry(entry)
    local header, body = entry:match("^(.-)\n(.*)$")
    return header or entry, body or ""
end

function Addon:RecordError(label, reason)
    local version, build = GetBuildInfo()
    local header = date("%Y-%m-%d %H:%M:%S") .. " · " .. tostring(version) .. " / " .. tostring(build)
    local body = (label .. ": " .. tostring(reason)):sub(1, ERROR_ENTRY_LIMIT - ERROR_HEADER_ROOM)
    local last = self.errorLog[#self.errorLog]
    if last then
        local lastHeader, lastBody = SplitErrorEntry(last)
        if lastBody == body then
            local count = tonumber(lastHeader:match(" · ×(%d+)$")) or 1
            self.errorLog[#self.errorLog] = header .. " · ×" .. (count + 1) .. "\n" .. body
            return
        end
    end
    self.errorLog[#self.errorLog + 1] = header .. "\n" .. body
    if #self.errorLog > ERROR_LOG_LIMIT then table.remove(self.errorLog, 1) end
end

function Addon:GetErrorLogNewestFirst()
    local entries = {}
    for index = #self.errorLog, 1, -1 do entries[#entries + 1] = self.errorLog[index] end
    return entries
end

-- Readable log: newest first, split into this session and earlier sessions (kept after /reload).
function Addon:FormatErrorLog()
    if #self.errorLog == 0 then return "Error log: empty." end
    local current, earlier = {}, {}
    for _, entry in ipairs(self:GetErrorLogNewestFirst()) do
        local group = entry:sub(1, #sessionStart) >= sessionStart and current or earlier
        group[#group + 1] = entry
    end
    local sections = {}
    local function Add(title, entries)
        if #entries == 0 then return end
        local lines = { title .. " (" .. #entries .. ", newest first)" }
        for index, entry in ipairs(entries) do lines[#lines + 1] = "[" .. index .. "] " .. entry end
        sections[#sections + 1] = table.concat(lines, "\n\n")
    end
    Add("This session", current)
    Add("Earlier sessions", earlier)
    return table.concat(sections, "\n\n=====\n\n")
end

function Addon:ClearErrorLog()
    for _, entries in ipairs({ self.errors, self.blockedActions, self.errorLog }) do
        for index = #entries, 1, -1 do entries[index] = nil end
    end
    if self.preferences then self.preferences.errorLog = self.errorLog end
end

-- Lists the insecure fields of the shared gamepad state, so a blocked-action report names the
-- variable that tainted Blizzard's code and the addon that wrote it.
local TAINT_LINE_LIMIT = 40

local function IsFrame(value)
    return type(value) == "table" and (type(rawget(value, 0)) == "userdata" or type(value.GetObjectType) == "function")
end

local function SlotName(value)
    if IsFrame(value) then
        local ok, name = pcall(value.GetName, value)
        return ok and name or tostring(value)
    end
    return tostring(value)
end

-- Visits every slot of the shared gamepad tables, one table level deep (shownFrames entries, panel
-- infos, binding sets), since a tainted entry there taints the native code that reads it.
local function VisitGamepadSlots(visit)
    local function Scan(label, owner, depth)
        if type(owner) ~= "table" or IsFrame(owner) then return end
        for key, value in pairs(owner) do
            -- issecurevariable only accepts string or number keys.
            local keyType = type(key)
            local secure, source = true, nil
            if keyType == "string" or keyType == "number" then secure, source = issecurevariable(owner, key) end
            local slot = label .. "." .. SlotName(key)
            visit(IsFrame(value) and (slot .. "=" .. SlotName(value)) or slot, secure, source)
            if depth > 0 and type(value) == "table" and not IsFrame(value) then Scan(slot, value, depth - 1) end
        end
    end
    -- One unreadable table must not hide the others.
    local function TryScan(label, owner, depth)
        local ok, reason = pcall(Scan, label, owner, depth)
        if not ok then visit(label .. " (scan failed: " .. tostring(reason) .. ")", false, "scan") end
    end
    local bindings = GamepadSharedUtility and GamepadSharedUtility.InputBindingManager
    TryScan("FrameControlsManager", GamepadMode and GamepadMode.FrameControlsManager, 1)
    TryScan("InputBindingManager", bindings, 0)
    TryScan("bindingSetStack", bindings and bindings.bindingSetStack, 1)
    TryScan("SmartNavigation", SmartNavigation, 0)
    TryScan("SmartNavigation.activeInfo", SmartNavigation and SmartNavigation.activeInfo, 0)
    TryScan("SmartNavigation.activePanels", SmartNavigation and SmartNavigation.activePanels, 1)
end

local function DescribeGamepadTaint()
    if not issecurevariable then return "" end
    local lines = {}
    VisitGamepadSlots(function(slot, secure, source)
        if not secure and #lines < TAINT_LINE_LIMIT then
            lines[#lines + 1] = slot .. ": source=" .. tostring(source)
        end
    end)
    if #lines == 0 then return "Insecure gamepad fields: none\n" end
    return "Insecure gamepad fields:\n" .. table.concat(lines, "\n") .. "\n"
end

local function SafeDescribeGamepadTaint()
    local ok, text = pcall(DescribeGamepadTaint)
    return ok and text or ("Insecure gamepad fields: scan failed: " .. tostring(text) .. "\n")
end

function Addon:InitializeSafetyMonitoring()
    if self.protectedActionEvents then return end
    local protectedActionEvents = CreateFrame("Frame")
    protectedActionEvents:RegisterEvent("ADDON_ACTION_BLOCKED")
    protectedActionEvents:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    protectedActionEvents:SetScript("OnEvent", function(_, event, source, action)
        if not canaccessallvalues(source, action) then return end

        local trace = SafeDescribeGamepadTaint() .. debugstack(2, 30, 0)
        Addon:RecordError(event, tostring(source) .. " / " .. tostring(action) .. "\n" .. trace)
        Addon.blockedActions[#Addon.blockedActions + 1] = event .. ": " .. source .. " / " .. tostring(action)
            .. "\n" .. trace
        if #Addon.blockedActions > 5 then table.remove(Addon.blockedActions, 1) end
    end)
    Addon.protectedActionEvents = protectedActionEvents

    if DisplayInterfaceActionBlockedMessage then
        hooksecurefunc(_G, "DisplayInterfaceActionBlockedMessage", function()
            local trace = SafeDescribeGamepadTaint() .. debugstack(2, 30, 0)
            Addon:RecordError("Interface action blocked", trace)
            Addon.blockedActions[#Addon.blockedActions + 1] = "Interface action blocked\n" .. trace
            if #Addon.blockedActions > 5 then table.remove(Addon.blockedActions, 1) end
        end)
    end
end

local lifecycleTransitions = {
    waiting = { ["initialize.start"] = "starting", failure = "suspended", reset = "starting" },
    starting = { ["initialize.ready"] = "ready", ["initialize.apiOnly"] = "apiOnly", failure = "suspended" },
    apiOnly = { failure = "suspended" },
    ready = { failure = "suspended", reset = "starting" },
    suspended = { reset = "starting" },
}

function Addon:MoveLifecycle(event)
    local nextState = lifecycleTransitions[self.lifecycle][event]

    if not nextState then return false end

    self.lifecycle = nextState
    if self.UpdateMinimapStatus then self:UpdateMinimapStatus() end

    return true
end

function Addon:HideFrames()
    if self.ReleaseControllerFocus then pcall(self.ReleaseControllerFocus, self) end
    if self.HideNameTooltips then pcall(self.HideNameTooltips, self) end

    for index = #self.frames, 1, -1 do
        local frame = self.frames[index]

        pcall(frame.Hide, frame)
    end

    pcall(function()
        if self.widgetTooltip then self.widgetTooltip:Hide() end
    end)
end

function Addon:GetPauseMessage()
    if GetLocale() == "frFR" then
        return "Forever Rosetta Stone : traductions en pause après une erreur. Cliquez sur l’icône de la mini-carte ou utilisez /frs error pour le rapport, /frs reset pour réessayer."
    end
    return "Forever Rosetta Stone: translations paused after an error. Click the minimap icon or use /frs error for the report, /frs reset to retry."
end

function Addon:Suspend(label, reason)
    if self.TraceFailure then self:TraceFailure(label, reason) end
    local alreadySuspended = self.lifecycle == "suspended"
    self:MoveLifecycle("failure")
    if self.StopBenchmark then pcall(self.StopBenchmark, self, "addon error") end
    self.current = { mode = "unavailable" }
    self:HideFrames()

    if alreadySuspended then return end

    self.errors[#self.errors + 1] = label .. ": " .. reason
    self:RecordError(label, reason)

    if #self.errors > 5 then table.remove(self.errors, 1) end

    pcall(print, self:GetPauseMessage())
end

-- Keep failures inside our callbacks; never replace WoW's or another addon's error handler.
function Addon:Run(label, callback, ...)
    if self.lifecycle == "suspended" then return false end

    local arguments, count = {...}, select("#", ...)
    local ok, result = xpcall(function()
        return callback(unpack(arguments, 1, count))
    end, function(reason)
        local trace = debugstack and debugstack(2, 8, 0) or ""
        return tostring(reason) .. "\n" .. trace
    end)

    if not ok then self:Suspend(label, result) end

    if self.lifecycle == "suspended" then
        self:HideFrames()
        return false
    end

    return ok, result
end

function Addon:Wrap(label, callback, fallback)
    local generation = self.generation

    return function(...)
        if generation ~= self.generation then return fallback end

        local ok, result = self:Run(label, callback, ...)

        if not ok then return fallback end

        return result
    end
end

function Addon:SetScript(frame, event, callback, fallback)
    frame:SetScript(event, callback and self:Wrap(event, callback, fallback) or nil)
end

function Addon:HookScript(frame, event, callback)
    frame:HookScript(event, self:Wrap(event, callback))
end

-- Native tooltip templates run Blizzard OnShow/OnHide handlers that write shared state
-- (EventRegistry counters, the item comparison manager). Fired by addon code they would leave
-- that state insecure for every later native tooltip, so addon tooltips keep only the cleanup
-- that touches their own frame.
local function OwnedTooltipShown(tip)
    if GameTooltip_CalculatePadding then GameTooltip_CalculatePadding(tip) end
end

local function OwnedTooltipHidden(tip)
    tip.waitingForData = false
    if SharedTooltip_SetBackdropStyle then SharedTooltip_SetBackdropStyle(tip, nil, tip.IsEmbedded) end
    if GameTooltip_ClearMoney then GameTooltip_ClearMoney(tip) end
    if GameTooltip_ClearStatusBars then GameTooltip_ClearStatusBars(tip) end
    if GameTooltip_ClearProgressBars then GameTooltip_ClearProgressBars(tip) end
    if GameTooltip_ClearWidgetSet then GameTooltip_ClearWidgetSet(tip) end
    if tip.ItemTooltip and EmbeddedItemTooltip_Hide then EmbeddedItemTooltip_Hide(tip.ItemTooltip) end
    tip:ClearPadding()
    if tip.ClearHandlerInfo then tip:ClearHandlerInfo() end
    if GameTooltip_ClearStatusBarWatch then GameTooltip_ClearStatusBarWatch(tip) end
    tip.suppressAutomaticCompareItem = false
end

local function IsolateTooltipScripts(tip)
    if GameTooltip_OnShow and tip:GetScript("OnShow") == GameTooltip_OnShow then
        tip:SetScript("OnShow", OwnedTooltipShown)
    end
    if GameTooltip_OnHide and tip:GetScript("OnHide") == GameTooltip_OnHide then
        tip:SetScript("OnHide", OwnedTooltipHidden)
    end
end

function Addon:NewFrame(kind, name, parent, template)
    local uniqueName = name and (name .. self.generation) or nil
    local frame = CreateFrame(kind, uniqueName, parent, template)
    self.frames[#self.frames + 1] = frame
    if kind == "GameTooltip" then IsolateTooltipScripts(frame) end

    return frame
end
