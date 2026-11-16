local addonName = ...
local queue = RosettaQuestProbeQueue
local frame = CreateFrame("Frame")
local state = "loading"
local currentID, requestedAt, deadline, nextRequestAt, sessionDeadline
local retryAt, retryRecord
local data
local reportWindow
local RunCommand
local comparison
local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, entry in pairs(value) do result[key] = Copy(entry) end
    return result
end
local REQUEST_INTERVAL_SECONDS = 0.2
local REQUEST_TIMEOUT_SECONDS = 10
local SESSION_LIMIT_SECONDS = 7200
local transitions = {
    loading = { ["addon.loaded"] = "idle" },
    idle = { ["run.start"] = "cooldown" },
    paused = { ["run.start"] = "cooldown" },
    cooldown = { ["quest.request"] = "waiting", ["run.pause"] = "paused", ["run.complete"] = "complete" },
    waiting = { ["quest.finished"] = "cooldown", ["run.pause"] = "pausing" },
    pausing = { ["quest.finished"] = "paused" },
    complete = {},
}

local function Transition(event)
    local target = transitions[state][event]
    if not target then return false end
    state = target
    return true
end

local function Print(message)
    print("Forever Rosetta Stone quest probe: " .. message)
end

local function PrintStatus()
    if not data then Print("waiting for SavedVariables."); return end
    local counts = {}
    local finished = 0
    for _, id in ipairs(queue.ids) do
        local record = data.results[id]
        if record then
            counts[record.status] = (counts[record.status] or 0) + 1
            finished = finished + 1
        end
    end
    local parts = {}
    for _, key in ipairs({ "loadedWithObjectives", "loadedEmpty", "loadedWithoutObjectiveData",
        "loadFailed", "timeout", "requestError", "readError" }) do
        if counts[key] then parts[#parts + 1] = key .. "=" .. counts[key] end
    end
    Print(state .. ": " .. finished .. "/" .. #queue.ids .. "; " .. table.concat(parts, ", "))
end

local function BuildReport(questID)
    local lines = { "FRS local quest scan", "State: " .. state, "Queue: " .. queue.hash,
        "Selected IDs: " .. #queue.ids, "Catalog: " .. queue.catalogHash,
        "EG revision: " .. (queue.egRevision or ""),
        "Commands: status | start | pause | report | quest ID | compare ID", "" }
    if not data then return table.concat(lines, "\n") .. "\nWaiting for SavedVariables." end
    lines[#lines + 1] = "Client build: " .. tostring(data.build) .. " | Locale: " .. data.locale
    lines[#lines + 1] = "Next queue position: " .. data.nextIndex
    lines[#lines + 1] = "Saved comparisons: " .. #(data.comparisons or {})
    local counts = {}
    for _, record in pairs(data.results) do counts[record.status] = (counts[record.status] or 0) + 1 end
    local statuses = {}
    for status in pairs(counts) do statuses[#statuses + 1] = status end
    table.sort(statuses)
    for _, status in ipairs(statuses) do lines[#lines + 1] = status .. ": " .. counts[status] end
    if questID then
        local record = data.results[questID]
        lines[#lines + 1] = "\nQuest " .. questID
        if not record then lines[#lines + 1] = "No saved result for this quest." else
            lines[#lines + 1] = "Title: " .. tostring(record.title)
            lines[#lines + 1] = "Status: " .. record.status .. " | In log: " .. tostring(record.inLog)
            lines[#lines + 1] = "Error: " .. tostring(record.error)
            for index, row in ipairs(record.rows or {}) do
                lines[#lines + 1] = string.format("%d | %s | %s/%s | %s", index, tostring(row.type),
                    tostring(row.numFulfilled), tostring(row.numRequired), tostring(row.text))
            end
        end
    end
    return table.concat(lines, "\n")
end

local function ShowReport(questID)
    if not reportWindow then
        local window = CreateFrame("Frame", "FRSQuestProbeReport", UIParent, "BackdropTemplate")
        reportWindow = window
        window:SetSize(700, 500)
        window:SetPoint("CENTER", UIParent, "CENTER")
        window:SetFrameStrata("TOOLTIP")
        window:SetFrameLevel(9000)
        window:EnableMouse(true)
        window:SetClampedToScreen(true)
        window:SetBackdrop({ bgFile = [[Interface\DialogFrame\UI-DialogBox-Background-Dark]],
            edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]], tile = true, tileSize = 32, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        table.insert(UISpecialFrames, window:GetName())
        local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", window, "TOPLEFT", 18, -18)
        title:SetText("FRS · Local quest scan")
        local hint = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", window, "TOPLEFT", 18, -46)
        hint:SetText("Select output, then Ctrl+C / Cmd+C. Commands: status, start, pause, quest ID.")
        local command = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
        command:SetSize(530, 24)
        command:SetPoint("TOPLEFT", window, "TOPLEFT", 24, -78)
        command:SetAutoFocus(false)
        local function Execute() command:ClearFocus(); RunCommand(command:GetText()) end
        command:SetScript("OnEnterPressed", Execute)
        local run = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
        run:SetSize(90, 24)
        run:SetPoint("LEFT", command, "RIGHT", 10, 0)
        run:SetText("Run")
        run:SetScript("OnClick", Execute)
        local scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", window, "TOPLEFT", 18, -116)
        scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -40, 50)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetMaxLetters(0)
        edit:SetFontObject(ChatFontNormal)
        edit:SetTextColor(1, 1, 1, 1)
        edit:SetWidth(630)
        edit:SetHeight(300)
        scroll:SetScrollChild(edit)
        edit:SetScript("OnEditFocusGained", function() edit:HighlightText() end)
        edit:SetScript("OnEscapePressed", function() window:Hide() end)
        edit:SetScript("OnTextChanged", function()
            if edit:GetText() ~= window.report then edit:SetText(window.report) end
        end)
        local selectOutput = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
        selectOutput:SetSize(130, 24)
        selectOutput:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -18, 16)
        selectOutput:SetText("Select output")
        selectOutput:SetScript("OnClick", function() edit:SetFocus(); edit:HighlightText() end)
        local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -4, -4)
        close:SetScript("OnClick", function() window:Hide() end)
        window.editBox, window.commandBox, window.selectOutput = edit, command, selectOutput
    end
    reportWindow.report = BuildReport(questID)
    reportWindow.editBox:SetText(reportWindow.report)
    reportWindow.editBox:SetHeight(math.max(300, select(2, reportWindow.report:gsub("\n", "")) * 18 + 36))
    reportWindow.editBox:HighlightText()
    reportWindow:Show()
end

local function Pause()
    if comparison then
        comparison.cancelled = true
        Print("comparison will stop after the current item request.")
        return
    end
    if Transition("run.pause") then
        Print(state == "pausing" and "finishing the current request, then pausing."
            or "paused. /reload or logout saves progress; /frsscan start resumes.")
    end
end

local function CounterOnlyRows(rows)
    local count = 0
    if type(rows) ~= "table" then return count end
    for _, row in ipairs(rows) do
        if type(row) == "table" and type(row.text) == "string" then
            local text = row.text
            if text:match("^%s*$") or text:match("^%s*%d+%s*/%s*%d+%s*$")
                or (GetLocale() == "enUS" and row.type == "monster"
                    and text:match("^%s*%d+%s*/%s*%d+%s+slain%s*$")) then count = count + 1 end
        end
    end
    return count
end

local function CompatibleRows(first, second)
    if type(second) ~= "table" or #first ~= #second then return false end
    for index, row in ipairs(first) do
        local other = second[index]
        if type(row) ~= "table" or type(other) ~= "table" or type(other.text) ~= "string"
            or row.type ~= other.type or row.numFulfilled ~= other.numFulfilled
            or row.numRequired ~= other.numRequired then return false end
    end
    return true
end

local function Finish(status, success, reason, finalRetry)
    if state ~= "waiting" and state ~= "pausing" then return end
    local id = currentID
    local record = {
        status = status,
        loadSuccess = success,
        requestedAt = requestedAt,
        capturedAt = time(),
        error = reason,
        inLog = C_QuestLog.IsOnQuest(id),
    }
    if success then
        local ok, title, rows = pcall(function()
            return C_QuestLog.GetTitleForQuestID(id), C_QuestLog.GetQuestObjectives(id)
        end)
        if ok then
            record.title, record.rows = title, Copy(rows)
            if type(rows) ~= "table" then record.status = "loadedWithoutObjectiveData"
            elseif #rows == 0 then record.status = "loadedEmpty"
            else record.status = "loadedWithObjectives" end
        else
            record.status, record.error = "readError", tostring(title)
        end
        if retryRecord and (record.status ~= "loadedWithObjectives"
            or not CompatibleRows(retryRecord.rows, record.rows)
            or CounterOnlyRows(record.rows) > CounterOnlyRows(retryRecord.rows)) then
            record = retryRecord
        end
        if record.status == "loadedWithObjectives" and CounterOnlyRows(record.rows) > 0 then
            retryRecord = record
            if not finalRetry and GetTime() < deadline then
                retryAt = math.min(GetTime() + REQUEST_INTERVAL_SECONDS, deadline)
                return
            end
            record.labelRetry = "incomplete"
        elseif retryRecord then
            record.labelRetry = "resolved"
        end
    end
    data.results[id] = record
    data.nextIndex = data.nextIndex + 1
    currentID = nil
    retryAt, retryRecord = nil, nil
    nextRequestAt = math.max(nextRequestAt, GetTime())
    Transition("quest.finished")
    if (data.nextIndex - 1) % 50 == 0 or state == "paused" then PrintStatus() end
end

local function Start()
    if not data then Print("waiting for SavedVariables."); return end
    if comparison then Print("comparison in progress."); return end
    if data.queueHash ~= queue.hash or data.build ~= select(2, GetBuildInfo()) or data.locale ~= GetLocale() then
        Print("queue, build, or client language changed; preserve the saved scan before starting a separate one.")
        return
    end
    if not Transition("run.start") then PrintStatus(); return end
    sessionDeadline = GetTime() + SESSION_LIMIT_SECONDS
    nextRequestAt = math.max(nextRequestAt or 0, GetTime())
    Print("started; up to five requests per second, one at a time. /frsscan pause stops new requests.")
    PrintStatus()
end

local function ReadComparisonRows(id)
    local ok, rows = pcall(C_QuestLog.GetQuestObjectives, id)
    if ok then return { rows = Copy(rows), readSuccess = true } end
    return { readSuccess = false, error = tostring(rows) }
end

local function ItemCacheState(id)
    if not C_Item or type(C_Item.IsItemDataCachedByID) ~= "function" then return "unavailable" end
    local ok, cached = pcall(C_Item.IsItemDataCachedByID, id)
    if not ok or type(cached) ~= "boolean" then return "error" end
    return cached and "cached" or "notCached"
end

local function EndComparison(status)
    local record = comparison.record
    record.status = status
    record.finishedAt = time()
    record.after = ReadComparisonRows(comparison.id)
    for _, dependency in ipairs(record.dependencies) do
        dependency.cacheAfter = ItemCacheState(dependency.id)
    end
    data.comparisons = data.comparisons or {}
    table.insert(data.comparisons, record)
    comparison = nil
    Print("comparison " .. status .. "; paired observations saved separately.")
end

local function Compare(id)
    if not data or comparison or (state ~= "idle" and state ~= "paused" and state ~= "complete") then
        Print("comparison requires an idle, paused, or completed scan."); return
    end
    if data.queueHash ~= queue.hash or data.build ~= select(2, GetBuildInfo()) or data.locale ~= GetLocale() then
        Print("queue, build, or client language changed; comparison refused."); return
    end
    local ids = queue.itemDependencies and queue.itemDependencies[id]
    if not ids or #ids == 0 or not data.results[id] or not data.results[id].loadSuccess then
        Print("comparison requires candidate items and a successfully loaded saved quest."); return
    end
    if not C_Item or not C_Item.RequestLoadItemDataByID then Print("item request API unavailable."); return end
    comparison = {
        id = id, ids = ids, index = 1, nextAt = GetTime(), limit = GetTime() + SESSION_LIMIT_SECONDS,
        record = { questID = id, queueHash = queue.hash, build = data.build, locale = data.locale,
            startedAt = time(), before = ReadComparisonRows(id), dependencies = {} },
    }
    for _, itemID in ipairs(ids) do
        comparison.record.dependencies[#comparison.record.dependencies + 1] = {
            id = itemID, cacheBefore = ItemCacheState(itemID), status = "notRequested",
        }
    end
    Print("comparison started; candidate items do not establish objective indices.")
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("QUEST_DATA_LOAD_RESULT")
frame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
frame:SetScript("OnEvent", function(_, event, id, success)
    if event == "ADDON_LOADED" then
        if id ~= addonName or not Transition("addon.loaded") then return end
        if not RosettaQuestProbeData then
            RosettaQuestProbeData = {
                schemaVersion = 1,
                queueHash = queue.hash,
                egRevision = queue.egRevision,
                catalogHash = queue.catalogHash,
                locale = GetLocale(),
                build = select(2, GetBuildInfo()),
                startedAt = time(),
                nextIndex = 1,
                results = {},
            }
        end
        data = RosettaQuestProbeData
        Print("loaded; never starts automatically. /frsscan start; /frsscan status.")
    elseif event == "ITEM_DATA_LOAD_RESULT" then
        if comparison and comparison.pending == id then
            comparison.record.dependencies[comparison.index].status = success and "loaded" or "failed"
            comparison.pending = nil
            comparison.index = comparison.index + 1
        end
    elseif event == "QUEST_DATA_LOAD_RESULT" and id == currentID and not retryAt and (state == "waiting" or state == "pausing") then
        Finish(success and "loaded" or "loadFailed", success)
    end
end)

frame:SetScript("OnUpdate", function()
    if comparison then
        local now = GetTime()
        if comparison.pending and now >= comparison.deadline then
            comparison.record.dependencies[comparison.index].status = "timeout"
            comparison.pending = nil
            comparison.index = comparison.index + 1
        end
        if comparison.pending then return end
        if comparison.cancelled then EndComparison("paused"); return end
        if now >= comparison.limit then EndComparison("sessionLimit"); return end
        if comparison.index > #comparison.ids then EndComparison("complete"); return end
        if now < comparison.nextAt or InCombatLockdown() then return end
        local id = comparison.ids[comparison.index]
        if ItemCacheState(id) == "cached" then
            comparison.record.dependencies[comparison.index].status = "alreadyCached"
            comparison.index = comparison.index + 1
            return
        end
        comparison.pending, comparison.deadline = id, now + REQUEST_TIMEOUT_SECONDS
        comparison.nextAt = now + REQUEST_INTERVAL_SECONDS
        local ok, reason = pcall(C_Item.RequestLoadItemDataByID, id)
        if not ok and comparison and comparison.pending == id then
            comparison.record.dependencies[comparison.index].status = "requestError"
            comparison.record.dependencies[comparison.index].error = tostring(reason)
            comparison.pending = nil
            comparison.index = comparison.index + 1
        end
        return
    end
    if state == "waiting" or state == "pausing" then
        if retryAt and GetTime() >= retryAt then
            Finish("loaded", true, nil, GetTime() >= deadline)
        elseif GetTime() >= deadline then Finish("timeout") end
        return
    end
    if state ~= "cooldown" then return end
    if data.nextIndex > #queue.ids then
        Transition("run.complete")
        PrintStatus()
        Print("finished. Fully quit WoW to save both observations and the quest cache, then report back.")
        return
    end
    if GetTime() >= sessionDeadline then
        Pause()
        Print("two-hour session limit reached; /reload saves progress.")
        return
    end
    if GetTime() < nextRequestAt then return end
    if InCombatLockdown() then return end
    if not Transition("quest.request") then return end
    currentID = queue.ids[data.nextIndex]
    requestedAt = time()
    deadline = GetTime() + REQUEST_TIMEOUT_SECONDS
    nextRequestAt = GetTime() + REQUEST_INTERVAL_SECONDS
    local ok, reason = pcall(C_QuestLog.RequestLoadQuestByID, currentID)
    if not ok and currentID then Finish("requestError", nil, tostring(reason)) end
end)

SLASH_ROSETTAQUESTPROBE1 = "/frsscan"
RunCommand = function(command)
    command = command:lower():match("^%s*(.-)%s*$")
    if command == "start" then Start()
    elseif command == "pause" then Pause(); PrintStatus()
    elseif command:match("^compare%s+%d+$") then Compare(tonumber(command:match("%d+")))
    end
    if command == "" or command == "status" or command == "report" or command == "start" or command == "pause"
        or command:match("^quest%s+%d+$") or command:match("^compare%s+%d+$") then
        ShowReport(tonumber(command:match("^quest%s+(%d+)$")))
    else
        ShowReport()
    end
end
SlashCmdList.ROSETTAQUESTPROBE = function(command)
    C_Timer.After(0, function() RunCommand(command) end)
end
