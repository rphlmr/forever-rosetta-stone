local addonName, Addon = ...

-- This module is loaded only by manifests built with --dev-debug.
Addon.devDebug = true
local session
local sequence = 0
local EVENT_LIMIT = 12000
local REVISION = "tooltip-trace-13"
local InstallStatHooks
local state = "waitingForAddon"
local transitions = {
    waitingForAddon = { ["addon.loaded"] = "capturing" },
    capturing = { ["capture.full"] = "full" },
    full = {},
}

local function Transition(event)
    local nextState = transitions[state][event]
    if not nextState then return false end
    state = nextState
    return true
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(frame, _, loadedAddon)
    if loadedAddon == addonName and Transition("addon.loaded") then
        -- WoW restores SavedVariables after executing addon files and before ADDON_LOADED.
        ForeverRosettaStoneDevTrace = ForeverRosettaStoneDevTrace or { sessions = {} }
        local sessions = ForeverRosettaStoneDevTrace.sessions
        session = { started = date("%Y-%m-%d %H:%M:%S"), revision = REVISION, events = {} }
        sessions[#sessions + 1] = session
        if #sessions > 3 then table.remove(sessions, 1) end
        print("Forever Rosetta Stone local debug enabled: " .. REVISION .. ". /reload saves the hover trace.")
    end
    if state ~= "waitingForAddon" and InstallStatHooks() then frame:UnregisterAllEvents() end
end)

local function Read(value)
    if not canaccessallvalues(value) then return "<restricted>" end
    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" then return value end
end

local function GetRect(frame)
    if not frame or frame:IsForbidden() then return end
    return { left = Read(frame:GetLeft()), top = Read(frame:GetTop()),
        width = Read(frame:GetWidth()), height = Read(frame:GetHeight()), scale = Read(frame:GetEffectiveScale()) }
end

local function ReadTable(value, depth)
    if not canaccessallvalues(value) then return "<restricted>" end
    if type(value) ~= "table" then return Read(value) end
    if depth == 0 then return "<depth-limit>" end
    local result = {}
    for key, field in pairs(value) do
        local readableKey = Read(key)
        if readableKey ~= nil then result[readableKey] = ReadTable(field, depth - 1) end
    end
    return result
end

local function BeginEvent()
    sequence = sequence + 1
    if state == "full" or #session.events >= EVENT_LIMIT then
        session.droppedEvents = (session.droppedEvents or 0) + 1
        if Transition("capture.full") then
            session.truncated = true
            print("Forever Rosetta Stone debug trace is full. /reload to save it and start a new capture.")
        end
        return false
    end
    return true
end

local function RecordTooltip(event, source, data, reason)
    if not source or source:IsForbidden() then return end
    local spec = Addon.nameTooltips and Addon.nameTooltips[source]
    if not spec or not BeginEvent() then return end
    local info = source.GetProcessingTooltipInfo and source:GetProcessingTooltipInfo()
    data = data or (source.GetPrimaryTooltipData and source:GetPrimaryTooltipData())
    local owner = source.GetOwner and source:GetOwner()
    if owner and owner:IsForbidden() then owner = nil end
    local _, spellID
    if source.GetSpell then _, spellID = source:GetSpell() end
    local entry = {
        sequence = sequence, time = GetTime(), event = event, reason = reason, source = source:GetName(),
        lifecycle = Addon.lifecycle, mode = Addon.preferences and Addon.preferences.tooltipMode,
        tooltipState = spec.group and spec.group.lifecycle and spec.group.lifecycle.value,
        sourcePhase = spec.group and spec.group.lifecycle and spec.group.lifecycle.sources[source],
        coverage = Addon.preferences and Addon.preferences.tooltipCoverage,
        locale = Addon.preferences and Addon.preferences.locale,
        getter = info and Read(info.getterName), getterArgs = info and ReadTable(info.getterArgs, 2),
        dataType = data and Read(data.type), dataID = data and Read(data.id),
        owner = owner and owner:GetName(), ownerAction = owner and Read(owner.action),
        ownerRect = GetRect(owner), anchorType = source.GetAnchorType and Read(source:GetAnchorType()),
        defaultAnchor = Read(source.default),
        placementPolicy = Addon:GetTooltipPlacementPolicy(source) and Addon:GetTooltipPlacementPolicy(source).name,
        placementContext = Addon:GetTooltipPlacementPolicy(source) and Addon:GetTooltipPlacementPolicy(source).context,
        inputMode = Addon:GetTooltipInputMode(),
        ownerSpellID = owner and Read(owner.spellID),
        nativeSpellID = Read(spellID), kind = spec.kind, id = Read(spec.id), name = Read(spec.name),
        featureEnabled = spec.kind and Addon:IsFeatureEnabled(spec.kind .. "Tooltip"),
        blocked = not not Addon:IsTooltipBlocked(), rendering = Addon.tooltipRendering ~= nil,
        shown = source:IsShown(), rect = GetRect(source),
        companionShown = spec.tip and spec.tip:IsShown() or false, companionRect = GetRect(spec.tip),
        stacked = Addon.stackedTooltips and Addon.stackedTooltips[source] ~= nil or false,
    }
    if event == "data" then
        entry.data = ReadTable(data, 5)
        entry.lines = {}
        for index, line in ipairs(data and data.lines or {}) do
            entry.lines[index] = { type = Read(line.type), index = Read(line.lineIndex),
                left = Read(line.leftText), right = Read(line.rightText) }
        end
    end
    if spec.group and source ~= spec.group[1] and (event == "native.clear" or event == "show") then
        entry.stack = debugstack(2, 12, 0)
    end
    if event == "show" and source.NumLines then
        entry.nativeLines = {}
        for index = 1, source:NumLines() do
            local left, right = source:GetLeftLine(index), source:GetRightLine(index)
            entry.nativeLines[index] = { left = Read(left and left:GetText()), right = Read(right and right:GetText()),
                leftColor = left and ReadTable({ left:GetTextColor() }, 1),
                rightColor = right and ReadTable({ right:GetTextColor() }, 1) }
        end
    end
    if event == "layout" then
        entry.screen = GetRect(UIParent)
        entry.group = {}
        for _, native in ipairs(spec.group) do
            local member = Addon.nameTooltips[native]
            entry.group[#entry.group + 1] = { source = native:GetName(), id = Read(member.id),
                shown = native:IsShown(), rect = GetRect(native),
                companionShown = member.tip and member.tip:IsShown() or false, companionRect = GetRect(member.tip) }
        end
    end
    session.events[#session.events + 1] = entry
end

local function RecordStatTooltip(frame)
    if not Addon.devDebug or state == "waitingForAddon" or frame:IsForbidden()
        or GameTooltip:IsForbidden() or not GameTooltip:IsShown() or not GameTooltip:IsOwned(frame) then return end
    if not BeginEvent() then return end
    local entry = {
        sequence = sequence, time = GetTime(), event = "character.stat.hover", source = GameTooltip:GetName(),
        owner = frame:GetName(), locale = GetLocale(), label = frame.Label and Read(frame.Label:GetText()),
        value = frame.Value and Read(frame.Value:GetText()), numericValue = Read(frame.numericValue),
        unit = Read(frame.unit), tooltip = Read(frame.tooltip), tooltip2 = Read(frame.tooltip2),
        tooltip3 = Read(frame.tooltip3), nativeLines = {},
    }
    for index = 1, GameTooltip:NumLines() do
        local left, right = GameTooltip:GetLeftLine(index), GameTooltip:GetRightLine(index)
        entry.nativeLines[index] = {
            left = Read(left and left:GetText()), right = Read(right and right:GetText()),
            leftColor = left and ReadTable({ left:GetTextColor() }, 1),
            rightColor = right and ReadTable({ right:GetTextColor() }, 1),
        }
    end
    session.events[#session.events + 1] = entry
end

InstallStatHooks = function()
    if type(PaperDollFrame_SetLabelAndText) ~= "function" then return false end
    local hooked = setmetatable({}, { __mode = "k" })
    hooksecurefunc("PaperDollFrame_SetLabelAndText", function(frame)
        if frame:IsForbidden() or hooked[frame] then return end
        hooked[frame] = true
        frame:HookScript("OnEnter", function(owner)
            local ok, traceError = pcall(RecordStatTooltip, owner)
            if not ok then session.traceError = tostring(traceError) end
        end)
    end)
    return true
end

function Addon:TraceTooltip(event, source, data, reason)
    if not self.devDebug or state == "waitingForAddon" then return end
    local ok, traceError = pcall(RecordTooltip, event, source, data, reason)
    if not ok then session.traceError = tostring(traceError) end
end

function Addon:TraceFailure(label, reason)
    if not self.devDebug or state == "waitingForAddon" then return end
    session.failure = { label = label, reason = reason, time = GetTime() }
end

function Addon:GetDevTraceStatus()
    return { revision = REVISION, state = state, events = session and #session.events or 0,
        sequence = sequence, dropped = session and session.droppedEvents or 0,
        failure = session and session.failure, traceError = session and session.traceError }
end

function Addon:PrintDevTraceStatus()
    if state == "waitingForAddon" then
        print("Forever Rosetta Stone local debug: " .. REVISION .. "; waiting for SavedVariables to finish loading.")
        return
    end
    print("Forever Rosetta Stone local debug: " .. session.revision .. "; " .. #session.events .. "/" .. sequence
        .. " tooltip events saved in memory. /reload writes them to disk.")
    if session.truncated then print("Trace limit reached; " .. session.droppedEvents .. " later events were omitted.") end
end
