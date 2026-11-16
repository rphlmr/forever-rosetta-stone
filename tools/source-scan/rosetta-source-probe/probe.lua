local addonName = ...
local queue = RosettaSourceProbeQueue
local frame = CreateFrame("Frame")
local state = "loading"
local session, jobs, current, requestedAt, deadline, nextRequestAt, sessionDeadline, spellSettleDeadline
local REQUEST_INTERVAL = 0.2
local REQUEST_TIMEOUT = 10
local SESSION_LIMIT = 7200
local SPELL_SETTLE_SECONDS = 1
local transitions = {
    loading = { ["addon.loaded"] = "idle" },
    idle = { ["run.start"] = "cooldown" },
    paused = { ["run.start"] = "cooldown" },
    cooldown = { ["request.start"] = "waiting", ["run.pause"] = "paused", ["run.complete"] = "complete" },
    waiting = { ["request.finish"] = "cooldown", ["run.pause"] = "pausing" },
    pausing = { ["request.finish"] = "paused" },
    complete = {},
    invalid = {},
}

local function Transition(event)
    local target = transitions[state][event]
    if not target then return false end
    state = target
    return true
end

local function Print(message)
    print("Forever Rosetta Stone source probe: " .. message)
end

local function Status()
    if not session then Print("No session. Use /frssource start."); return end
    Print(state .. ": attempted " .. (session.nextIndex - 1) .. "/" .. #jobs
        .. "; locale=" .. session.locale .. "; build=" .. session.build .. "; queue=" .. session.queueHash)
end

local function ValidSavedData(data)
    if type(data) ~= "table" or data.schemaVersion ~= 1 or type(data.sessions) ~= "table" then return false end
    local count = 0
    for key, saved in pairs(data.sessions) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or type(saved) ~= "table"
            or type(saved.locale) ~= "string" or type(saved.build) ~= "string"
            or type(saved.queueHash) ~= "string" or type(saved.nextIndex) ~= "number"
            or saved.nextIndex < 1 or saved.nextIndex % 1 ~= 0 or type(saved.results) ~= "table" then
            return false
        end
        local results = 0
        for resultKey, result in pairs(saved.results) do
            if type(resultKey) ~= "number" or resultKey < 1 or resultKey % 1 ~= 0
                or type(result) ~= "table" or type(result.status) ~= "string" then return false end
            results = results + 1
        end
        if results ~= #saved.results or saved.nextIndex ~= results + 1 then return false end
        count = count + 1
    end
    return count == #data.sessions
end

local function SafeValue(value, seen, depth)
    if issecretvalue and issecretvalue(value) then return nil end
    local kind = type(value)
    if kind == "string" or kind == "boolean" then return value end
    if kind == "number" then
        if value == value and value ~= math.huge and value ~= -math.huge then return value end
        return nil
    end
    if kind ~= "table" or depth >= 12 or seen[value] then return nil end
    seen[value] = true
    local copy = {}
    for key, item in pairs(value) do
        local safeKey = SafeValue(key, seen, depth + 1)
        if type(safeKey) == "string" or type(safeKey) == "number" then
            copy[safeKey] = SafeValue(item, seen, depth + 1)
        end
    end
    seen[value] = nil
    return copy
end

local function Report()
    Status()
    if not session then return end
    local counts = {}
    for _, result in ipairs(session.results) do
        counts[result.status] = (counts[result.status] or 0) + 1
    end
    local statuses = {}
    for status in pairs(counts) do statuses[#statuses + 1] = status end
    table.sort(statuses)
    for _, status in ipairs(statuses) do Print(status .. ": " .. counts[status]) end
    Print("Full observations are in RosettaSourceProbeData after logout or reload.")
end

local function CharacterContext()
    local _, class = UnitClass("player")
    local _, race = UnitRace("player")
    return { level = UnitLevel("player"), class = class, race = race, sex = UnitSex("player") }
end

-- Capture each API return separately so nil, restricted, and failed reads remain visible.
local function SnapshotCall(fn, count, ...)
    local result = {}
    if type(fn) ~= "function" then
        for i = 1, count do result[i] = { status = "unavailable" } end
        return result
    end
    local ok, values = pcall(function(...) return { n = count, fn(...) } end, ...)
    if not ok then
        for i = 1, count do result[i] = { status = "error" } end
        return result
    end
    for i = 1, count do
        local safe, entry = pcall(function()
            local value = values[i]
            if issecretvalue and issecretvalue(value) then return { status = "restricted" } end
            if value == nil then return { status = "unavailable" } end
            if type(value) == "boolean" or (type(value) == "number" and value == value
                and value ~= math.huge and value ~= -math.huge) then
                return { status = "available", value = value }
            end
            return { status = "unavailable" }
        end)
        result[i] = safe and entry or { status = "restricted" }
    end
    return result
end

local function SpellContext(job)
    local context = { build = session.build, locale = session.locale, unit = "player",
        level = SnapshotCall(UnitLevel, 1, "player"),
        spirit = SnapshotCall(UnitStat, 4, "player", 5),
        attackPower = SnapshotCall(UnitAttackPower, 3, "player"),
        rangedAttackPower = SnapshotCall(UnitRangedAttackPower, 3, "player"),
        spellHealing = SnapshotCall(GetSpellBonusHealing, 1), damageBySchool = {}, knownSpells = {} }
    for school = 1, 7 do context.damageBySchool[school] = SnapshotCall(GetSpellBonusDamage, 1, school) end
    for _, id in ipairs(job.knownSpellIds or {}) do
        context.knownSpells[id] = SnapshotCall(C_SpellBook and C_SpellBook.IsSpellKnown, 1, id)
    end
    return context
end

local function ObserveValue(value, seen, depth)
    if issecretvalue and issecretvalue(value) then return { status = "restricted" } end
    if value == nil then return { status = "unavailable" } end
    local kind = type(value)
    if kind == "string" or kind == "boolean" then return { status = "available", value = value } end
    if kind == "number" then
        if value == value and value ~= math.huge and value ~= -math.huge then
            return { status = "available", value = value }
        end
        return { status = "unavailable" }
    end
    if kind ~= "table" or depth >= 12 or seen[value] then return { status = "unavailable" } end
    seen[value] = true
    local fields, omitted = {}, 0
    for key, item in pairs(value) do
        local okKey, safeKey = pcall(function()
            if issecretvalue and issecretvalue(key) then return nil end
            if type(key) == "string" or type(key) == "number" then return key end
        end)
        if okKey and safeKey ~= nil then
            local okValue, observation = pcall(ObserveValue, item, seen, depth + 1)
            fields[safeKey] = okValue and observation or { status = "restricted" }
        else omitted = omitted + 1 end
    end
    seen[value] = nil
    return { status = "available", fields = fields, omittedKeys = omitted }
end

local function ObserveCall(fn, ...)
    if type(fn) ~= "function" then return { status = "unavailable", returns = {} } end
    local function Pack(...) return { n = select("#", ...), ... } end
    local ok, values = pcall(function(...) return Pack(fn(...)) end, ...)
    if not ok then return { status = "error", returns = {} } end
    local returns = {}
    for i = 1, values.n do
        local safe, value = pcall(ObserveValue, values[i], {}, 0)
        returns[i] = safe and value or { status = "restricted" }
    end
    return { status = "available", returnCount = values.n, returns = returns }
end

local function Finish(status, values, reason)
    if state ~= "waiting" and state ~= "pausing" then return end
    if values then
        local ok, safe = pcall(SafeValue, values, {}, 0)
        if ok then values = safe else status, values, reason = "readError", nil, "Values could not be serialized safely" end
    end
    session.results[#session.results + 1] = {
        job = current,
        status = status,
        values = values,
        error = reason,
        requestedAt = requestedAt,
        capturedAt = time(),
        character = CharacterContext(),
        contextSnapshot = current.kind == "spells" and current.captureContext == 1 and SpellContext(current) or nil,
    }
    session.nextIndex = session.nextIndex + 1
    current = nil
    spellSettleDeadline = nil
    Transition("request.finish")
    if state == "paused" or (session.nextIndex - 1) % 50 == 0 then Status() end
end

local function ReadQuest(id)
    return {
        title = C_QuestLog.GetTitleForQuestID(id),
        objectives = C_QuestLog.GetQuestObjectives(id),
        inLog = C_QuestLog.IsOnQuest(id),
    }
end

local function ReadSpell(id)
    local info = C_Spell.GetSpellInfo(id)
    return {
        name = info and info.name,
        info = info,
        description = C_Spell.GetSpellDescription(id),
        descriptionKind = "rendered",
        subtext = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id),
        subtextKind = "rendered",
        known = IsPlayerSpell and IsPlayerSpell(id),
    }
end

local function ReadItem(id)
    local name, link, _, _, _, _, _, _, _, _, _, classID, subclassID, _, _, _, _, description = C_Item.GetItemInfo(id)
    return { name = name, link = link, classID = classID, subclassID = subclassID,
        description = description, descriptionKind = "apiObservation" }
end

local function CaptureTooltip(kind, id, values)
    if not C_TooltipInfo then return end
    if not C_TooltipInfo.GetHyperlink then return end
    local link = kind == "items" and values.link or "spell:" .. id
    if not link then return end
    local ok, tooltip = pcall(C_TooltipInfo.GetHyperlink, link)
    if ok then
        local safe, result = pcall(SafeValue, tooltip, {}, 0)
        if safe then values.tooltip = result else values.tooltipError = "Tooltip could not be serialized safely" end
    else
        values.tooltipError = "Tooltip request failed"
    end
    values.tooltipKind = "rendered"
end

local function ReadResult(kind, id)
    local values
    if kind == "quests" then values = ReadQuest(id)
    elseif kind == "spells" then values = ReadSpell(id)
    elseif kind == "items" then values = ReadItem(id)
    end
    if values and (kind == "spells" or kind == "items") then CaptureTooltip(kind, id, values) end
    return values
end

local function CompleteLoaded(success, settleExpired)
    if not success then Finish("loadFailed"); return end
    local ok, values = pcall(ReadResult, current.kind, current.id)
    if not ok then Finish("readError", nil, tostring(values)); return end
    if current.kind == "spells" then
        local missingText = not values.description or values.description == ""
            or not values.subtext or values.subtext == ""
        if missingText and not settleExpired then
            spellSettleDeadline = spellSettleDeadline or (GetTime() + SPELL_SETTLE_SECONDS)
            return
        end
        values.textStatus = missingText and "unavailableAfterSettle" or "available"
    end
    values.unavailableFields = {}
    for _, field in ipairs(current.fields or {}) do
        local key = field == "objectiveLines" and "objectives" or field
        if values[key] == nil or values[key] == "" then
            values.unavailableFields[#values.unavailableFields + 1] = field
        end
    end
    Finish("captured", values)
end

local function Request(job)
    local kind, id = job.kind, job.id
    if kind == "quests" and C_QuestLog and C_QuestLog.RequestLoadQuestByID then
        C_QuestLog.RequestLoadQuestByID(id)
    elseif kind == "items" and C_Item and C_Item.RequestLoadItemDataByID and C_Item.GetItemInfo then
        C_Item.RequestLoadItemDataByID(id)
    elseif kind == "spells" and C_Spell and C_Spell.RequestLoadSpellData
        and C_Spell.GetSpellInfo and C_Spell.GetSpellDescription then
        C_Spell.RequestLoadSpellData(id)
    elseif kind == "areas" and C_Map and C_Map.GetAreaInfo then
        local value = C_Map.GetAreaInfo(id)
        Finish(value and "captured" or "unavailable", { name = value })
    elseif kind == "maps" and C_Map and C_Map.GetMapInfo then
        local value = C_Map.GetMapInfo(id)
        Finish(value and "captured" or "unavailable", { name = value and value.name, info = value })
    elseif kind == "factions" then
        Finish("captured", { modern = ObserveCall(C_Reputation and C_Reputation.GetFactionDataByID, id),
            legacy = ObserveCall(GetFactionInfoByID, id),
            playerLevel = ObserveCall(UnitLevel, "player"), build = session.build, locale = session.locale })
    elseif kind == "globals" then
        local observation = ObserveCall(function() return _G[job.key] end)
        local entry = observation.returns[1]
        local value = entry and entry.status == "available" and entry.value or nil
        Finish(type(value) == "string" and "captured" or "unavailable", { value = value, observation = observation })
    else
        Finish("unavailable", nil, "No supported native API for this job")
    end
end

local function Start()
    if state == "invalid" then Print("Saved data is invalid or unsupported; collection is disabled."); return end
    if not queue or type(queue.hash) ~= "string" or not queue.profiles then
        Print("Queue is missing or invalid."); return
    end
    local locale, build = GetLocale(), tostring(select(2, GetBuildInfo()))
    local profile = queue.profiles[locale]
    if not profile or type(profile.jobs) ~= "table" then Print("No queue for locale " .. locale); return end
    if state ~= "idle" and state ~= "paused" then Status(); return end
    jobs = profile.jobs
    if not session then
        for index = #RosettaSourceProbeData.sessions, 1, -1 do
            local previous = RosettaSourceProbeData.sessions[index]
            if previous.locale == locale and previous.build == build and previous.queueHash == queue.hash
                and previous.nextIndex <= #jobs then
                session = previous
                break
            end
        end
        if not session then
            session = { locale = locale, build = build, queueHash = queue.hash, catalogHash = queue.catalogHash,
                startedAt = time(), nextIndex = 1, results = {} }
            table.insert(RosettaSourceProbeData.sessions, session)
        end
    end
    if session.locale ~= locale or session.build ~= build or session.queueHash ~= queue.hash then
        Print("Client locale, build, or queue changed. Reload before starting a separate session."); return
    end
    if not Transition("run.start") then return end
    sessionDeadline = GetTime() + SESSION_LIMIT
    nextRequestAt = math.max(nextRequestAt or 0, GetTime())
    Print("Started. /frssource pause stops new requests.")
    Status()
end

local function Pause()
    if Transition("run.pause") then
        Print(state == "pausing" and "Finishing the current request, then pausing." or "Paused.")
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("QUEST_DATA_LOAD_RESULT")
frame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
frame:RegisterEvent("SPELL_DATA_LOAD_RESULT")
frame:RegisterEvent("SPELL_TEXT_UPDATE")
frame:SetScript("OnEvent", function(_, event, id, success)
    if event == "ADDON_LOADED" then
        if id ~= addonName or not Transition("addon.loaded") then return end
        if RosettaSourceProbeData == nil then
            RosettaSourceProbeData = { schemaVersion = 1, sessions = {} }
        elseif not ValidSavedData(RosettaSourceProbeData) then
            state = "invalid"
            Print("Saved data is invalid or unsupported; preserve it and resolve it before starting.")
            return
        end
        Print("Loaded; collection never starts automatically. /frssource start.")
        return
    end
    if not current or id ~= current.id then return end
    if event == "SPELL_TEXT_UPDATE" and current.kind == "spells" and spellSettleDeadline then
        CompleteLoaded(true)
        return
    end
    if (event == "QUEST_DATA_LOAD_RESULT" and current.kind == "quests")
        or (event == "ITEM_DATA_LOAD_RESULT" and current.kind == "items")
        or (event == "SPELL_DATA_LOAD_RESULT" and current.kind == "spells") then
        CompleteLoaded(success)
    end
end)

frame:SetScript("OnUpdate", function()
    if state == "waiting" or state == "pausing" then
        if spellSettleDeadline and GetTime() >= spellSettleDeadline then CompleteLoaded(true, true)
        elseif GetTime() >= deadline then Finish("timeout") end
        return
    end
    if state ~= "cooldown" then return end
    if session.nextIndex > #jobs then
        Transition("run.complete")
        Status()
        Print("All jobs attempted; see /frssource report for failures and unavailable results.")
        Print("Quit WoW to save observations and the quest cache.")
        return
    end
    if GetTime() >= sessionDeadline then Pause(); Print("Two-hour session limit reached."); return end
    if GetTime() < nextRequestAt or InCombatLockdown() then return end
    if not Transition("request.start") then return end
    current = jobs[session.nextIndex]
    requestedAt = time()
    deadline = GetTime() + REQUEST_TIMEOUT
    nextRequestAt = GetTime() + REQUEST_INTERVAL
    local ok, reason = pcall(Request, current)
    if not ok and current then Finish("requestError", nil, tostring(reason)) end
end)

SLASH_ROSETTASOURCEPROBE1 = "/frssource"
SlashCmdList.ROSETTASOURCEPROBE = function(command)
    command = command:lower():match("^%s*(.-)%s*$")
    if command == "start" then Start()
    elseif command == "pause" then Pause(); Status()
    elseif command == "" or command == "status" then Status()
    elseif command == "report" then Report()
    else Print("Commands: start, pause, status, report") end
end
