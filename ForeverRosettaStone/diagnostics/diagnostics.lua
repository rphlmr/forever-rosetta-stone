local addonName, Addon = ...

local PICK_LIMIT = 30
local QUEST_QUERY_LIMIT = 20
local QUEST_QUERY_TIMEOUT = 5
local unitEvents = {
    PLAYER_TARGET_CHANGED = "target", PLAYER_SOFT_INTERACT_CHANGED = "softinteract",
    PLAYER_SOFT_ENEMY_CHANGED = "softenemy", PLAYER_SOFT_FRIEND_CHANGED = "softfriend",
}
local transitions = {
    idle = { start = "picking", clear = "idle" },
    picking = { stop = "idle", close = "idle", clear = "idle" },
}
local picker = { state = "idle", entries = {}, byID = {} }
Addon.debugPicker = picker

local function Snapshot(value, depth, seen)
    if not canaccessallvalues(value) then return "<restricted>" end
    local kind = type(value)
    if kind ~= "table" then
        if kind == "string" or kind == "number" or kind == "boolean" or kind == "nil" then return value end
        return "<" .. kind .. ">"
    end
    if depth == 0 then return "<depth limit>" end
    seen = seen or {}
    if seen[value] then return "<cycle>" end
    seen[value] = true
    local result, count = {}, 0
    for key, child in pairs(value) do
        if canaccessallvalues(key) and (type(key) == "string" or type(key) == "number") then
            count = count + 1
            if depth and count > 100 then result["<truncated>"] = "More than 100 fields"; break end
            result[key] = Snapshot(child, depth and depth - 1, seen)
        elseif not canaccessallvalues(key) then
            count = count + 1
            result["<restricted key " .. count .. ">"] = "<restricted>"
        else
            count = count + 1
            result["<" .. type(key) .. " key " .. count .. ">"] = Snapshot(child, depth and depth - 1, seen)
        end
    end
    seen[value] = nil
    return result
end

local function Format(value, indent)
    if type(value) ~= "table" then return type(value) == "string" and string.format("%q", value) or tostring(value) end
    indent = indent or ""
    local keys, lines = {}, { "{" }
    for key in pairs(value) do keys[#keys + 1] = key end
    -- Numeric keys keep list order (1, 2, ..., 10); other keys follow alphabetically.
    table.sort(keys, function(a, b)
        local aNumber, bNumber = type(a) == "number", type(b) == "number"
        if aNumber ~= bNumber then return aNumber end
        if aNumber then return a < b end
        return tostring(a) < tostring(b)
    end)
    for _, key in ipairs(keys) do
        lines[#lines + 1] = indent .. "  " .. tostring(key) .. " = " .. Format(value[key], indent .. "  ")
    end
    lines[#lines + 1] = indent .. "}"
    return table.concat(lines, "\n")
end

local function Read(callback)
    local ok, result = pcall(callback)
    if not ok then return "<unavailable: " .. tostring(result) .. ">" end
    if result == nil then return "<not available>" end
    return result
end

local function Pack(...)
    return { n = select("#", ...), ... }
end

local function CaptureReturns(callback)
    local results = Pack(pcall(callback))
    if not results[1] then return { status = "error", error = Snapshot(results[2]) } end
    local values = {}
    for index = 2, results.n do
        local value = results[index]
        if not canaccessallvalues(value) then values[index - 1] = "<restricted>"
        elseif value == nil then values[index - 1] = "<nil>"
        else values[index - 1] = Snapshot(value) end
    end
    return { status = "ok", returnCount = results.n - 1, values = values }
end

local function CaptureReplayContext(evidence, native)
    local context = { schemaVersion = 1, calls = {}, issues = {},
        scope = "Live readable replay context at pick time. Optional API failures and restricted values remain explicit; hidden engine state is not inferred." }
    local function Issue(reason) context.issues[#context.issues + 1] = reason end
    local function Call(path, required, ...)
        local args = Pack(...)
        local ok, callback = pcall(function()
            local value = _G
            for part in path:gmatch("[^%.]+") do
                if not canaccessallvalues(value) or type(value) ~= "table" then return nil end
                value = value[part]
            end
            return value
        end)
        local result
        if not ok then result = { status = "lookup error", error = Snapshot(callback) }
        elseif not canaccessallvalues(callback) or type(callback) ~= "function" then
            result = { status = "missing API" }
        elseif not canaccessallvalues(unpack(args, 1, args.n)) then result = { status = "restricted arguments" }
        else result = CaptureReturns(function() return callback(unpack(args, 1, args.n)) end) end
        context.calls[path] = context.calls[path] or {}
        context.calls[path][#context.calls[path] + 1] = { arguments = Snapshot(args), result = result }
        if required and (result.status ~= "ok" or not result.values or result.values[1] == nil
            or result.values[1] == "<nil>" or result.values[1] == "<restricted>") then Issue(path) end
        return result
    end
    local function First(result)
        return result and result.status == "ok" and result.values and result.values[1]
    end
    context.player = {}
    for _, api in ipairs({ "UnitSex", "UnitFactionGroup", "UnitRace", "UnitClass", "UnitLevel", "UnitGUID" }) do
        context.player[api] = Call(api, api ~= "UnitGUID", "player")
    end
    context.clientLocale = Call("GetLocale", true)
    context.build = Call("GetBuildInfo", true)
    context.addonVersion = Call("C_AddOns.GetAddOnMetadata", false, addonName, "Version")
    context.catalogVersion = Read(function() return ForeverRosettaStoneDB.catalogVersion end)
    context.time = Call("GetTime", false)
    context.bindLocation = Call("GetBindLocation", false)
    for _, api in ipairs({ "GetShapeshiftFormID", "IsStealthed", "GetSpellBonusHealing" }) do Call(api, false) end
    for _, api in ipairs({ "UnitAttackPower", "UnitRangedAttackPower", "UnitPowerType",
        "UnitAttackSpeed", "UnitDamage", "UnitRangedDamage" }) do Call(api, false, "player") end
    for school = 1, 7 do Call("GetSpellBonusDamage", false, school) end
    for stat = 1, 5 do Call("UnitStat", false, "player", stat) end
    if evidence.unitToken then
        context.unitSex = Call("UnitSex", true, evidence.unitToken)
        context.unitGuild = Call("GetGuildInfo", false, evidence.unitToken)
        context.unitGUID = Call("UnitGUID", true, evidence.unitToken)
        local prior = evidence.unitAPIs and First(evidence.unitAPIs.UnitGUID)
        if type(prior) == "string" and prior ~= First(context.unitGUID) then Issue("Unit changed during capture") end
        if evidence.unitAPIs and First(evidence.unitAPIs.UnitIsPlayer) == true then
            for _, api in ipairs({ "UnitRace", "UnitClass" }) do
                local value = First(evidence.unitAPIs[api])
                if value == nil or value == "<nil>" or value == "<restricted>" then Issue(api .. " for picked player") end
            end
        end
    end

    local function Table(value) return canaccessallvalues(value) and type(value) == "table" and value end
    local function Field(value, key)
        value = Table(value)
        local result = value and value[key]
        if canaccessallvalues(result) then return result end
    end
    local spells, count, conditions, conditionCount = {}, 0, {}, 0
    local function Spell(id)
        if not canaccessallvalues(id) or type(id) ~= "number" or id <= 0 or spells[id] then return end
        spells[id], count = true, count + 1
        if count > 32 then
            if count == 33 then Issue("Linked-spell API budget exhausted; original payload is retained") end
            return
        end
        Call("C_Spell.GetSpellInfo", false, id)
        Call("C_Spell.GetSpellDescription", false, id)
        Call("C_Spell.GetSpellPowerCost", false, id)
        Call("C_SpellBook.IsSpellKnown", false, id)
        Call("C_TradeSkillUI.GetRecipeSchematic", false, id, false)
        local db = ForeverRosettaStoneDB
        local ok, details = pcall(function() return db and db.GetSpellDetails and db:GetSpellDetails(id, "enUS") end)
        if ok and type(details) == "table" then
            for _, field in ipairs({ "description", "auraDescription", "variables" }) do
                local text = details[field]
                if type(text) == "string" then
                    if text:find("$z", 1, true) then
                        local location = First(context.bindLocation)
                        if type(location) ~= "string" or location == "<nil>" or location == "<restricted>" then
                            Issue("GetBindLocation required by owned spell text")
                        end
                    end
                    for predicate in text:gmatch("%$%?([^%[]+)%[") do
                        for reference in predicate:gmatch("s(%d+)") do
                            reference = tonumber(reference)
                            if not conditions[reference] then
                                conditions[reference], conditionCount = true, conditionCount + 1
                                if conditionCount <= 32 then Call("C_SpellBook.IsSpellKnown", true, reference)
                                elseif conditionCount == 33 then Issue("Known-condition API budget exhausted") end
                            end
                        end
                    end
                end
            end
        end
    end
    Spell(evidence.spell and evidence.spell.values and evidence.spell.values[2])
    local dataType = Field(native, "type")
    local types = Enum and Enum.TooltipDataType or {}
    if dataType == types.Spell and dataType ~= nil then Spell(Field(native, "id")) end
    for _, line in pairs(Table(Field(native, "lines")) or {}) do Spell(Field(line, "spellID")) end
    if dataType ~= nil and dataType == types.Item then
        local id = Field(native, "id")
        local link = evidence.item and evidence.item.values and evidence.item.values[2]
        if type(link) ~= "string" or not link:find("item:", 1, true) then link = nil end
        if type(id) == "number" and id > 0 then
            context.item = { id = id, link = link,
                info = Call("C_Item.GetItemInfo", false, link or id),
                instant = Call("C_Item.GetItemInfoInstant", false, link or id),
                stats = Call("C_Item.GetItemStats", false, link or ("item:" .. id)),
                name = Call("C_Item.GetItemNameByID", false, id) }
        end
    end

    local indexGetters = { GetUnitAura = true, GetUnitBuff = "HELPFUL", GetUnitDebuff = "HARMFUL" }
    local instanceGetters = { GetUnitAuraByAuraInstanceID = true,
        GetUnitBuffByAuraInstanceID = true, GetUnitDebuffByAuraInstanceID = true }
    local auraInfo
    for _, info in ipairs({ evidence.processingInfo, evidence.primaryInfo }) do
        local name = Field(info, "getterName")
        if type(name) == "string" and (indexGetters[name] or instanceGetters[name]) then auraInfo = info; break end
    end
    if auraInfo or (dataType ~= nil and dataType == types.UnitAura) then
        context.aura = {}
        local name, args = Field(auraInfo, "getterName"), Table(Field(auraInfo, "getterArgs"))
        local unit, key = Field(args, 1), Field(args, 2)
        if type(unit) ~= "string" or type(key) ~= "number" then Issue("Aura getter arguments unavailable")
        else
            context.aura.unit, context.aura.getter, context.aura.arguments = unit, name, Snapshot(args)
            local result
            if indexGetters[name] then
                local filter = Field(args, 3)
                if filter == nil and type(indexGetters[name]) == "string" then filter = indexGetters[name] end
                result = Call("C_UnitAuras.GetAuraDataByIndex", true, unit, key, filter)
            else result = Call("C_UnitAuras.GetAuraDataByAuraInstanceID", true, unit, key) end
            context.aura.lookup = result
            local aura = Table(First(result))
            if not aura then Issue("Readable aura instance unavailable")
            else
                context.aura.instanceID, context.aura.spellID = aura.auraInstanceID, aura.spellId
                if type(aura.auraInstanceID) ~= "number" or type(aura.spellId) ~= "number" then
                    Issue("Aura identity unavailable")
                else
                    Spell(aura.spellId)
                    context.aura.byInstance = Call("C_UnitAuras.GetAuraDataByAuraInstanceID", true, unit, aura.auraInstanceID)
                    local same = Table(First(context.aura.byInstance))
                    if not same or same.auraInstanceID ~= aura.auraInstanceID or same.spellId ~= aura.spellId then
                        Issue("Aura instance expired or changed during capture")
                    end
                    local expected = Field(native, "id")
                    if type(expected) == "number" and expected ~= aura.spellId then Issue("Aura spell differs from native tooltip") end
                end
                if type(aura.sourceUnit) == "string" and aura.sourceUnit ~= "<restricted>" then
                    context.aura.caster = { unit = aura.sourceUnit,
                        guid = Call("UnitGUID", false, aura.sourceUnit), level = Call("UnitLevel", true, aura.sourceUnit),
                        sex = Call("UnitSex", false, aura.sourceUnit) }
                else context.aura.caster = { status = "unavailable" }; Issue("Aura caster unavailable") end
            end
            context.aura.unitSex = Call("UnitSex", true, unit)
        end
    end
    context.status = #context.issues == 0 and "captured" or "partial"
    return context
end

local function CaptureTooltipEvidence(source, native)
    local unit
    local evidence = {
        scope = "All readable enumerable tooltip payload and info fields; no depth or field-count truncation. "
            .. "Functions and opaque objects are marked; hidden engine data is not enumerable.",
        primaryData = Read(function() return source:GetPrimaryTooltipData() end),
        primaryInfo = Read(function() return source:GetPrimaryTooltipInfo() end),
        processingInfo = Read(function() return source:GetProcessingTooltipInfo() end),
        infoList = Read(function() return source.infoList end),
        enumDefinitions = {
            dataTypes = Read(function() return Enum.TooltipDataType end),
            lineTypes = Read(function() return Enum.TooltipDataLineType end),
        },
        unit = CaptureReturns(function()
            local results = Pack(source:GetUnit())
            if canaccessallvalues(results[2]) and type(results[2]) == "string" then unit = results[2] end
            return unpack(results, 1, results.n)
        end),
        item = CaptureReturns(function() return source:GetItem() end),
        spell = CaptureReturns(function() return source:GetSpell() end),
    }
    if not unit and canaccessallvalues(native) and type(native) == "table" then
        if canaccessallvalues(native.unitToken) and type(native.unitToken) == "string" then unit = native.unitToken end
        if not unit and canaccessallvalues(native.lines) and type(native.lines) == "table" then
            for _, line in ipairs(native.lines) do
                if canaccessallvalues(line) and type(line) == "table"
                    and canaccessallvalues(line.unitToken) and type(line.unitToken) == "string" then
                    unit = line.unitToken
                    break
                end
            end
        end
    end
    evidence.unitToken = unit
    if unit then
        evidence.unitAPIs = {}
        for _, name in ipairs({ "UnitGUID", "UnitName", "UnitFactionGroup", "UnitReputationReaction",
            "UnitCreatureType", "UnitCreatureFamily", "UnitClassification", "UnitRace", "UnitClass",
            "UnitLevel", "UnitSex", "GetGuildInfo", "UnitIsDead", "UnitIsCorpse", "UnitIsTapDenied",
            "UnitIsPlayer", "UnitReaction", "UnitIsFriend", "UnitIsEnemy" }) do
            local callback = _G[name]
            if type(callback) ~= "function" then evidence.unitAPIs[name] = { status = "missing API" }
            else
                evidence.unitAPIs[name] = CaptureReturns(function()
                    if name == "UnitReaction" or name == "UnitIsFriend" or name == "UnitIsEnemy" then
                        return callback(unit, "player")
                    end
                    return callback(unit)
                end)
            end
        end
    end
    local ok, context = pcall(CaptureReplayContext, evidence, native)
    evidence.replayContext = ok and context or { status = "partial", error = Snapshot(context),
        issues = { "Replay context collector failed; native tooltip evidence is retained" } }
    return Snapshot(evidence)
end

-- Frame field graphs can contain shared UI trees. Bound the diagnostic work and report every limit.
local function LocationSnapshot(value, depth, seen, budget)
    if not canaccessallvalues(value) then return "<restricted>" end
    if type(value) ~= "table" then return Snapshot(value) end
    if depth == 0 then return "<depth limit>" end
    if seen[value] then return "<cycle>" end
    seen[value] = true
    local result = {}
    for key, child in pairs(value) do
        if budget.remaining == 0 then result["<truncated>"] = "Frame field budget exhausted"; break end
        budget.remaining = budget.remaining - 1
        if canaccessallvalues(key) and (type(key) == "string" or type(key) == "number") then
            result[key] = LocationSnapshot(child, depth - 1, seen, budget)
        end
    end
    seen[value] = nil
    return result
end

local function CaptureLocationFrame(frame)
    local result = { fields = {}, idFields = {}, attributes = {} }
    if not canaccessallvalues(frame) or type(frame) ~= "table"
        or Read(function() return frame:IsForbidden() end) ~= false then
        result.unavailable = Snapshot(frame, 1)
        return result
    end
    result.name = Read(function() return frame:GetName() end)
    result.objectType = Read(function() return frame:GetObjectType() end)
    result.frameID = Read(function() return frame:GetID() end)
    result.fields = Read(function() return LocationSnapshot(frame, 6, {}, { remaining = 1500 }) end)
    if type(result.fields) == "table" then
        for key, value in pairs(result.fields) do
            if type(key) == "string" and key:lower():find("id", 1, true) then result.idFields[key] = value end
        end
    end
    for _, key in ipairs({ "id", "areaID", "areaId", "zoneID", "zoneId", "subzoneID", "subZoneID", "mapID", "mapId", "uiMapID" }) do
        result.attributes[key] = Read(function() return frame:GetAttribute(key) end)
    end
    return result
end

local function CaptureLocation(source)
    local owner = Read(function() return source:GetOwner() end)
    local parent = Read(function() return owner:GetParent() end)
    local ownerData = CaptureLocationFrame(owner)

    local mapID = Read(function() return C_Map.GetBestMapForUnit("player") end)
    local position, mapInfo, areaIDs = "<not available>", "<not available>", "<not available>"
    local mapInfoAtPosition = "<not available>"
    if canaccessallvalues(mapID) and type(mapID) == "number" then
        mapInfo = Read(function() return C_Map.GetMapInfo(mapID) end)
        position = Read(function() return C_Map.GetPlayerMapPosition(mapID, "player") end)
        if canaccessallvalues(position) and type(position) == "table" then
            areaIDs = Read(function() return C_MapExplorationInfo.GetExploredAreaIDsAtPosition(mapID, position) end)
            mapInfoAtPosition = Read(function()
                local x, y = position:GetXY()
                return C_Map.GetMapInfoAtPosition(mapID, x, y)
            end)
            position = Read(function() local x, y = position:GetXY(); return { x = x, y = y } end)
        end
    end
    local areas = {}
    if canaccessallvalues(areaIDs) and type(areaIDs) == "table" then
        for index, areaID in ipairs(areaIDs) do
            areas[index] = { areaID = Snapshot(areaID, 1) }
            if canaccessallvalues(areaID) and type(areaID) == "number" then
                areas[index].nativeName = Read(function() return C_Map.GetAreaInfo(areaID) end)
            end
        end
    end

    return {
        zoneText = Read(function() return GetZoneText() end),
        subzoneText = Read(function() return GetSubZoneText() end),
        minimapZoneText = Read(function() return GetMinimapZoneText() end),
        realZoneText = Read(function() return GetRealZoneText() end),
        uiMapID = mapID,
        mapInfo = mapInfo,
        mapInfoAtPosition = mapInfoAtPosition,
        position = position,
        candidateAreaIDs = areaIDs,
        candidateAreas = areas,
        resolvedLocation = Read(function() return ForeverRosettaStoneDB:GetPlayerLocation(Addon:GetTargetLocale()) end),
        owner = ownerData,
        ownerParent = CaptureLocationFrame(parent),
        tooltipFrame = CaptureLocationFrame(source),
        primaryTooltipData = Read(function() return source:GetPrimaryTooltipData() end),
        limits = "All readable enumerable tooltip, owner and owner-parent fields, including tables under arbitrary keys. "
            .. "Each frame graph is limited to depth 6 and 1500 fields total; limits and cycles are marked. "
            .. "Functions and opaque objects are marked, not executed. Only listed attributes are probed; "
            .. "hidden engine fields, other attributes and further ancestors are not inspected.",
    }
end

function Addon:RecordAuraResolution(reason)
    -- Bounded public reason counters only; never store restricted aura values.
    self.auraResolutionDiagnostics = self.auraResolutionDiagnostics or { inCombat = {}, outOfCombat = {} }
    local phase = InCombatLockdown() and "inCombat" or "outOfCombat"
    local counts = self.auraResolutionDiagnostics[phase]
    counts[reason] = (counts[reason] or 0) + 1
    self.auraResolutionDiagnostics.last = { phase = phase, reason = reason }
end

local function Environment()
    local preferences = Snapshot(Addon.preferences, 4)
    if type(preferences) == "table" then preferences.debugReport, preferences.errorLog = nil, nil end
    return {
        addonVersion = Read(function() return C_AddOns.GetAddOnMetadata(addonName, "Version") end),
        client = Read(function() local version, build = GetBuildInfo(); return version .. " / " .. build end),
        clientLocale = GetLocale(),
        targetLocale = Addon.preferences and Addon.preferences.locale,
        catalog = ForeverRosettaStoneDB.catalogVersion,
        lifecycle = Addon.lifecycle,
        preferences = preferences,
        questState = Snapshot(Addon.current, 2),
        errorLog = Addon.GetErrorLogNewestFirst and Addon:GetErrorLogNewestFirst() or Snapshot(Addon.errorLog, 2),
        benchmarkState = Addon.benchmark and Addon.benchmark.state,
        developerTrace = Addon.GetDevTraceStatus and Addon:GetDevTraceStatus() or "Developer capture not loaded",
        auraResolution = Snapshot(Addon.auraResolutionDiagnostics, 4),
    }
end

local function IssueReport(title, details)
    return table.concat({
        title, "", Addon:DebugText("reportHint"),
        "https://github.com/rphlmr/forever-rosetta-stone/issues/new", "",
        Addon:DebugText("steps") .. ": [...]", Addon:DebugText("expected") .. ": [...]",
        Addon:DebugText("actual") .. ": [...]", "", Addon:DebugText("details"), "```text", details, "```",
    }, "\n")
end

function Addon:FormatDebugReport(title, report)
    return IssueReport(title, Format(Snapshot(report)))
end

function Addon:GetGossipDebugReport()
    local report = {
        capturedAt = Read(function() return date("%Y-%m-%d %H:%M:%S") end),
        client = CaptureReturns(GetBuildInfo),
        clientLocale = GetLocale(),
        targetLocale = self:GetTargetLocale(),
        menuVisible = Read(function() return GossipFrame and GossipFrame:IsVisible() or false end),
    }
    if report.menuVisible ~= true then
        report.status = "Open an NPC dialogue, then run /frs gossip while its options are visible."
    else
        report.npc = {
            name = Read(function() return UnitName("npc") end),
            guid = Read(function() return UnitGUID("npc") end),
        }
        report.text = Read(function() return C_GossipInfo.GetText() end)
        report.options = Read(function() return C_GossipInfo.GetOptions() end)
        if canaccessallvalues(report.options) and type(report.options) == "table" then
            report.optionCount = #report.options
            report.status = "captured"
        else
            report.status = "options unavailable"
        end
    end
    return self:FormatDebugReport("Forever Rosetta Stone · Gossip menu capture", report)
end

function Addon:IsDebugPicking()
    return picker.state == "picking"
end

function Addon:GetDebugWelcome()
    return table.concat({
        "Forever Rosetta Stone · " .. self:DebugText("title"), "", self:DebugText("inspectHint"),
        self:DebugText("addonHint"), self:DebugText("shareHint"),
    }, "\n")
end

function Addon:GetDebugPickedList()
    local lines = { self:DebugText("inspectHint"), self:DebugText("count", #picker.entries, PICK_LIMIT), "" }
    for index, entry in ipairs(picker.entries) do
        lines[#lines + 1] = index .. ". " .. self:GetDebugKindLabel(entry.kind) .. " " .. entry.id .. " · " .. entry.name
    end
    if picker.full then lines[#lines + 1] = self:DebugText("limit") end
    return table.concat(lines, "\n")
end

function Addon:RecordDebugUnit(unit)
    if not self:IsDebugPicking() or not C_TooltipInfo or not C_TooltipInfo.GetUnit then return end
    local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
    if ok and data then self:RecordDebugTooltip(UIParent, data) end
end

function Addon:MoveDebugPicker(event)
    local nextState = transitions[picker.state][event]
    if not nextState then return false end
    if event == "start" and (not self.errorDialog or not self.errorDialog.console
        or not self.errorDialog.frame:IsShown()) then self:ShowDebugConsole(self:GetDebugPickedList(), true) end
    picker.state = nextState
    if event == "start" or event == "clear" then
        picker.entries, picker.byID, picker.full, picker.captureError = {}, {}, false, nil
    end
    self:SetDebugPickerView(nextState == "picking")
    if not picker.unitEvents then
        picker.unitEvents = CreateFrame("Frame")
        picker.unitEvents:SetScript("OnEvent", function(_, unitEvent)
            self:RecordDebugUnit(unitEvents[unitEvent])
        end)
    end
    picker.unitEvents:UnregisterAllEvents()
    if event == "start" then
        for unitEvent, unit in pairs(unitEvents) do
            picker.unitEvents:RegisterEvent(unitEvent)
            self:RecordDebugUnit(unit)
        end
        if self.errorDialog.display then self.errorDialog.display:Hide() end
        for source, spec in pairs(self.nameTooltips or {}) do
            if not source:IsForbidden() and source:IsShown() and spec.kind and spec.id then
                self:RecordDebugSurface(source, spec.kind, spec.id, "visible", spec.data, { name = spec.name })
            end
        end
        if self.panel and self.panel:IsShown() and self.current.questID then
            self:RecordDebugSurface(self.panel, "quest", self.current.questID, "questPanel", nil,
                self:GetQuest(self.current.questID))
        end
    end
    if event == "stop" then self:ShowDebugConsole(self:GetDebugPickedList()) end
    if event == "clear" then
        self.preferences.debugReport = nil
        self:ShowDebugConsole(self:GetDebugWelcome())
        self.errorDialog.commandBox:SetText("")
    end
    return true
end

function Addon:CaptureDebugSurface(source, kind, id, context, native, translated)
    if not self:IsDebugPicking() or self.tooltipRendering or not source or source:IsForbidden()
        or not canaccessallvalues(id) or (type(id) ~= "number" and type(id) ~= "string") then return end
    if kind == "minimapLocation" then native = CaptureLocation(source) end
    if not native and kind:lower():find("quest", 1, true) then
        native = {
            title = Read(function() return C_QuestLog.GetTitleForQuestID(id) end),
            objectives = Read(function() return C_QuestLog.GetQuestObjectives(id) end),
            complete = Read(function() return C_QuestLog.IsComplete(id) end),
        }
        local index = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id)
        if type(index) == "number" and index > 0 and C_QuestLog.GetQuestIDForLogIndex(index) == id then
            native.description, native.summary = GetQuestLogQuestText(index)
        end
    end
    local key = kind .. ":" .. id
    local entry = picker.byID[key]
    if not entry then
        if #picker.entries >= PICK_LIMIT then picker.full = true; return end
        entry = { kind = kind, id = id, name = tostring(id) }
        picker.entries[#picker.entries + 1] = entry
        picker.byID[key] = entry
    end
    local lines = {}
    if source.NumLines and source.GetLeftLine then
        for index = 1, source:NumLines() do
            local left, right = source:GetLeftLine(index), source.GetRightLine and source:GetRightLine(index)
            lines[index] = { leftText = left and left:GetText(), rightText = right and right:GetText() }
        end
    end
    local first = lines[1]
    entry.name = first and canaccessallvalues(first.leftText) and first.leftText or tostring(id)
    if type(native) == "table" and canaccessallvalues(native) and canaccessallvalues(native.name, native.title) then
        entry.name = native.name or native.title or entry.name
        local row = canaccessallvalues(native.lines) and native.lines and native.lines[1]
        if row and canaccessallvalues(row) and canaccessallvalues(row.leftText) then entry.name = row.leftText or entry.name end
    end
    if canaccessallvalues(native) and type(native) == "string" then entry.name = native end
    entry.data = Snapshot(native)
    entry.lines = Snapshot(lines)
    entry.tooltipEvidence = CaptureTooltipEvidence(source, native)
    entry.context = context
    entry.inputMode = self:GetTooltipInputMode()
    entry.time = GetTime()
    entry.source = source:GetName() or "<anonymous>"
    entry.translation = Snapshot(translated, 5)
    entry.surfaces = entry.surfaces or {}
    entry.surfaces[context or kind] = { native = entry.data, lines = entry.lines, translated = entry.translation,
        source = entry.source, inputMode = entry.inputMode, tooltipEvidence = entry.tooltipEvidence }
    self:RefreshDebugPickedList()
end

function Addon:RecordDebugSurface(source, kind, id, context, native, translated)
    if not self:IsDebugPicking() then return end
    local ok, reason = pcall(self.CaptureDebugSurface, self, source, kind, id, context, native, translated)
    if not ok then picker.captureError = tostring(reason) end
end

function Addon:RecordDebugRenderedTooltip(spec)
    if not self:IsDebugPicking() then return end
    local entry = picker.byID[spec.kind .. ":" .. spec.id]
    if not entry or not spec.tip or spec.tip:IsForbidden() then return end
    local lines = {}
    for index = 1, spec.tip:NumLines() do
        local left, right = spec.tip:GetLeftLine(index), spec.tip.GetRightLine and spec.tip:GetRightLine(index)
        lines[index] = { leftText = left and left:GetText(), rightText = right and right:GetText() }
    end
    entry.renderedTranslation = Snapshot({ name = spec.name, lines = lines,
        tooltipMode = self.preferences.tooltipMode, tooltipCoverage = self.preferences.tooltipCoverage })
    if spec.debugNativeTalentLines then
        entry.nativeLinesAtRender = Snapshot(spec.debugNativeTalentLines)
        spec.debugNativeTalentLines = nil
    end
    local surface = entry.surfaces[spec.context or entry.context or spec.kind]
    if surface then
        surface.renderedTranslation = entry.renderedTranslation
        surface.nativeLinesAtRender = entry.nativeLinesAtRender
    end
end

function Addon:CaptureDebugTooltip(source, data)
    if not data or source:IsForbidden() then return end
    local spec = self.nameTooltips and self.nameTooltips[source]
    local kind, id
    local resolutionErrors = {}
    local readable = canaccessallvalues(data) and type(data) == "table"
    if readable and canaccessallvalues(data.type) then
        for _, component in ipairs(self:GetTooltipComponents()) do
            local ok, resolved = pcall(component.ResolveData, source, data)
            if not ok then resolutionErrors[component.kind] = Snapshot(resolved)
            elseif canaccessallvalues(resolved) and resolved then id, kind = resolved, component.kind; break end
        end
    end
    if not kind and readable and canaccessallvalues(data.type, data.id) and data.type == Enum.TooltipDataType.Quest then
        kind, id = "quest", data.id
    end
    if not kind then
        local titleLine = source:NumLines() > 0 and source:GetLeftLine(1)
        local title = titleLine and titleLine:GetText()
        kind = "tooltip"
        id = canaccessallvalues(title) and type(title) == "string" and title ~= "" and title
            or source:GetName() or "<anonymous tooltip>"
    end
    local component = self:GetTooltipComponent(kind)
    self:CaptureDebugSurface(source, kind, id, component and component.GetPlacementContext(source), data,
        spec and spec.kind == kind and spec.id == id and { name = spec.name,
            lifecycle = spec.group and spec.group.lifecycle, tooltipMode = self.preferences.tooltipMode,
            tooltipCoverage = self.preferences.tooltipCoverage } or nil)
    local entry = picker.byID[kind .. ":" .. id]
    if entry then entry.resolutionErrors = next(resolutionErrors) and resolutionErrors or nil end
end

function Addon:RecordDebugTooltip(source, data)
    if not self:IsDebugPicking() then return end
    local ok, reason = pcall(self.CaptureDebugTooltip, self, source, data)
    if not ok then picker.captureError = tostring(reason) end
end

function Addon:RecordDebugTooltipText(source)
    if not self:IsDebugPicking() or self.tooltipRendering or source:IsForbidden()
        or not source.GetPrimaryTooltipData or not source.NumLines or not source.GetLeftLine then return end
    local ok, reason = pcall(function()
        local data = source:GetPrimaryTooltipData()
        if data then return end
        local titleLine = source:NumLines() > 0 and source:GetLeftLine(1)
        local title = titleLine and titleLine:GetText()
        if canaccessallvalues(title) and type(title) == "string" and title ~= "" then
            local spec = self.nameTooltips[source]
            local known = spec and spec.kind and spec.id and picker.byID[spec.kind .. ":" .. spec.id]
            if known and known.lines and known.lines[1] and known.lines[1].leftText == title then return end
            self:CaptureDebugSurface(source, "tooltip", title, "tooltip", { name = title })
        end
    end)
    if not ok then picker.captureError = tostring(reason) end
end

function Addon:GetEntityDebugReport(kind, id)
    local db, locale = ForeverRosettaStoneDB, self:GetTargetLocale()
    local component = self:GetTooltipComponent(kind)
    local spell = kind == "spell" or kind == "talent" or kind == "mount"
    local detailMethod = kind == "item" and "GetItemDetails" or spell and "GetSpellDetails"
        or kind:lower():find("quest", 1, true) and "GetQuest"
    local category = kind == "item" and "items" or spell and "spells" or kind == "npc" and "npcs"
        or kind:lower():find("quest", 1, true) and "quests" or kind == "map" and "maps"
        or kind == "gossipOption" and "gossipoptions"
    local function Name(language)
        if component then return component.GetName(id, language) end
        if kind == "map" then return db:GetMapName(id, language) end
        if kind == "area" then return db:GetAreaName(id, language) end
    end
    local captured = picker.byID[kind .. ":" .. id]
    local report = {
        environment = Environment(),
        entity = { kind = kind, id = id, targetLocale = locale },
        catalogNameInClientLocale = Read(function() return Name(GetLocale()) end),
        targetName = Read(function() return Name(locale) end),
        catalogDetailsInClientLocale = detailMethod and Read(function() return db[detailMethod](db, id, GetLocale()) end),
        targetDetails = detailMethod and Read(function() return db[detailMethod](db, id, locale) end),
        hasAITranslation = category and Read(function() return db:IsAITranslated(category, id, locale) end),
        capturedTooltip = captured or self:DebugText("noCapture"),
        captureError = picker.captureError,
    }
    if kind == "npc" then
        local factionID = Read(function() return db:GetNpcFactionID(id) end)
        report.catalogFaction = { id = factionID, source = "Owned NPC catalog relationship; not a live API result" }
        if canaccessallvalues(factionID) and type(factionID) == "number" then
            report.catalogFaction.name = Read(function() return db:GetFactionName(factionID, locale) end)
        end
    end
    return self:FormatDebugReport("Forever Rosetta Stone · " .. self:GetDebugKindLabel(kind) .. " " .. id, report)
end

function Addon:GetCommandHelp()
    local groups = {
        { "home", { "/frs", "/frs help", "/frs report" } },
        { "inspect", { "/frs item 25", "/frs spell 133", "/frs npc 8956", "/frs questid 783",
            "/frs questdata 783 7", "/frs map 27",
            "/frs debug item 25" } },
        { "captures", { "/frs pick", "/frs stop", "/frs list", "/frs clear", "/frs gossip" } },
        { "display", { "/frs display", "/frs display item 117", "/frs display spell 133",
            "/frs display quest 783", "/frs display recipe 7418", "/frs display comparison",
            "/frs display target", "/frs pin quest 783" } },
        { "addon", { "/frs status", "/frs error", "/frs api on", "/frs api off", "/frs api auto", "/frs api status" } },
        { "recovery", { "/frs settings", "/frs language frFR", "/frs quest", "/frs reset" } },
    }
    if self.RunAPIProbe then
        table.insert(groups[2][2], '/frs dump C_TooltipInfo.GetHyperlink("spell:430")')
    end
    if self.BenchmarkCommand then
        table.insert(groups, { "performance", { "/frs bench start", "/frs bench stop", "/frs bench report" } })
    end
    local lines = { self:DebugText("commands"), "", self:DebugText("inspectHint"), self:DebugText("shareHint"), "" }
    for _, group in ipairs(groups) do
        lines[#lines + 1] = self:DebugText(group[1])
        for _, example in ipairs(group[2]) do lines[#lines + 1] = "  " .. example end
        lines[#lines + 1] = ""
    end
    local locales = {}
    for locale in pairs(ForeverRosettaStoneDB:GetLocales()) do locales[#locales + 1] = locale end
    table.sort(locales)
    lines[#lines + 1] = self:DebugText("languages") .. ": " .. table.concat(locales, ", ")
    return table.concat(lines, "\n")
end

function Addon:QueryDebugQuestData(argument)
    local quests, pending = {}, {}
    for word in argument:gmatch("%S+") do
        local id = tonumber(word:match("^%d+$"))
        if not self:IsReadableEntityID(id) or id > 2147483647 then return false end
        if not pending[id] then
            if #quests == QUEST_QUERY_LIMIT then return false end
            local quest = { questID = id, apiErrors = {} }
            quests[#quests + 1], pending[id] = quest, quest
        end
    end
    if #quests == 0 then return false end

    local frame = self.debugQuestDataEvents
    if not frame or frame.generation ~= self.generation then
        frame = self:NewFrame("Frame")
        frame.generation = self.generation
        self.debugQuestDataEvents = frame
    end

    local version, build = GetBuildInfo()
    local report = { schemaVersion = 1, version = version, build = build, locale = GetLocale(), quests = quests }
    local heading = "Forever Rosetta Stone · Native quest data"
    local loading = heading .. "\n\n"
        .. ("Loading %d quest(s) · Build %s · %s"):format(#quests, report.build, report.locale)
    self:ShowDebugConsole(loading)

    local remaining = #quests
    local function Complete(id, status, requestError)
        local quest = pending[id]
        if not quest then return end
        pending[id] = nil
        quest.status, quest.requestError = status, requestError
        self:CaptureQuestReport(quest)
        local title = quest.title
        if not canaccessallvalues(title) then
            quest.titleStatus = "restricted"
        elseif type(title) == "string" and title ~= "" then
            quest.titleStatus = "available"
        else
            quest.titleStatus = "unavailable"
        end
        remaining = remaining - 1
        if remaining > 0 then return end

        frame:UnregisterAllEvents()
        if self.errorDialog and self.errorDialog.frame:IsShown() and self.errorDialog.report == loading then
            self:ShowDebugConsole(heading .. "\n\n" .. Format(Snapshot(report)))
        end
    end
    self:SetScript(frame, "OnEvent", function(_, _, id, success)
        if canaccessallvalues(id, success) then Complete(id, success and "loaded" or "load failed") end
    end)
    frame:RegisterEvent("QUEST_DATA_LOAD_RESULT")

    for _, quest in ipairs(quests) do
        local ok, reason = pcall(function() C_QuestLog.RequestLoadQuestByID(quest.questID) end)
        if not ok then Complete(quest.questID, "request error", tostring(reason)) end
    end
    local onEvent = frame:GetScript("OnEvent")
    if remaining > 0 then
        C_Timer.After(QUEST_QUERY_TIMEOUT, self:Wrap("debug quest data timeout", function()
            if frame:GetScript("OnEvent") ~= onEvent then return end
            for _, quest in ipairs(quests) do Complete(quest.questID, "timed out") end
        end))
    end
    return true
end

function Addon:RunDebugCommand(command)
    local action, argument = (command or ""):match("^%s*(%S*)%s*(.-)%s*$")
    action = action:lower()
    if action == "debug" or action == "/frs" then return self:RunDebugCommand(argument) end
    if action == "gossip" then self:ShowDebugConsole(self:GetGossipDebugReport()); return end
    if (action == "dump" or action == "/dump") and self.RunAPIProbe then self:RunAPIProbe(argument); return end
    if action == "pick" then self:MoveDebugPicker("start"); return end
    if action == "stop" then self:MoveDebugPicker("stop"); return end
    if action == "list" then self:ShowDebugConsole(self:GetDebugPickedList()); return end
    if action == "clear" then self:MoveDebugPicker("clear"); return end
    if action == "display" or action == "pin" then
        self:ShowDebugDisplay()
        if argument ~= "" then
            local kind, input = argument:match("^(%S+)%s*(.-)$")
            self:DisplayDebugTooltip(kind:lower(), input, action == "pin")
        end
        return
    end
    argument = argument:lower()
    if action == "questdata" or action == "questtitle" then
        if self:QueryDebugQuestData(argument) then return end
    elseif action == "item" or action == "spell" or action == "npc" or action == "map" or action == "questid" then
        local id = tonumber(argument:match("^(%d+)$") or argument:match("|h" .. action .. ":(%d+)"))
        if id and id > 0 then
            self:ShowDebugConsole(self:GetEntityDebugReport(action == "questid" and "quest" or action, id)); return
        end
    elseif action == "error" then self:ShowErrorDialog(); return
    elseif action == "bench" and self.BenchmarkCommand then self:BenchmarkCommand(argument); return
    elseif action == "settings" then self:OpenSettings(); return
    elseif action == "quest" then
        if self.errorDialog then self.errorDialog.frame:Hide() end
        self:ToggleReading()
        return
    elseif action == "reset" then self:Restart(); return
    elseif action == "language" then
        for locale in pairs(ForeverRosettaStoneDB:GetLocales()) do
            if locale:lower() == argument then self:SetTargetLocale(locale); return end
        end
        self:ShowDebugConsole(self:DebugText("invalid") .. ": " .. argument .. "\n\n" .. self:GetCommandHelp())
        return
    elseif action == "status" then
        self:ShowDebugConsole(IssueReport("Forever Rosetta Stone · " .. self:DebugText("addon"), Format(Snapshot(Environment(), 6))))
        return
    elseif action == "report" then
        self:ShowDebugConsole(table.concat({ self:DebugText("help"), "", self:DebugText("shareHint"), "",
            self:DebugText("reportHint"), "https://github.com/rphlmr/forever-rosetta-stone/issues/new", "",
            self:DebugText("saved") }, "\n"))
        return
    elseif action == "" then
        self:ShowDebugConsole(self:GetDebugWelcome())
        return
    elseif action == "help" then
        self:ShowDebugConsole(self:GetCommandHelp())
        return
    end
    self:ShowDebugConsole(self:DebugText("invalid") .. ": " .. tostring(command)
        .. "\n\n" .. self:GetCommandHelp())
end
