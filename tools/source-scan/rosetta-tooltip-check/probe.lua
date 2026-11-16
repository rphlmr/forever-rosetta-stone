local addonName, Probe = ...
local frame = CreateFrame("Frame")
local active, loaded, warned
local MAX_SAMPLES = 600

local function Print(text)
    print("Rosetta check : " .. text)
end

local function Readable(value)
    return (not canaccessallvalues or canaccessallvalues(value))
        and (not issecretvalue or not issecretvalue(value))
end

local function Snapshot(value, seen)
    if not Readable(value) then return "<restricted>" end
    local kind = type(value)
    if kind == "number" then
        return value == value and math.abs(value) < math.huge and value or "<nonfinite>"
    end
    if kind ~= "table" then
        if kind == "nil" then return "<nil>" end
        if kind == "string" or kind == "boolean" then return value end
        return "<" .. kind .. ">"
    end
    seen = seen or {}
    if seen[value] then return "<cycle>" end
    seen[value] = true
    local result, restricted = {}, 0
    for key, child in pairs(value) do
        if Readable(key) and (type(key) == "number" or type(key) == "string") then
            result[key] = Snapshot(child, seen)
        else
            restricted = restricted + 1
            result["<unreadable key " .. restricted .. ">"] = "<restricted>"
        end
    end
    seen[value] = nil
    return result
end

local function Pack(...) return {n = select("#", ...), ...} end

local function Call(callback, ...)
    if type(callback) ~= "function" then return {status = "missing API"} end
    local results = Pack(pcall(callback, ...))
    if not results[1] then return {status = "error", error = Snapshot(results[2])} end
    local values = {}
    for index = 2, results.n do values[index - 1] = Snapshot(results[index]) end
    return {status = "ok", returnCount = results.n - 1, values = values}
end

local function Context()
    local result = {
        time = Call(GetTime), level = Call(UnitLevel, "player"),
        healingBonus = Call(GetSpellBonusHealing), damageBySchool = {},
        spirit = Call(UnitStat, "player", 5), attackPower = Call(UnitAttackPower, "player"),
        combat = Call(InCombatLockdown), traitConfigs = {},
        class = Call(UnitClass, "player"), sex = Call(UnitSex, "player"),
        faction = Call(UnitFactionGroup, "player"), race = Call(UnitRace, "player"),
        form = Call(GetShapeshiftFormID), stealth = Call(IsStealthed),
        powerType = Call(UnitPowerType, "player"), power = Call(UnitPower, "player"),
    }
    for school = 1, 7 do result.damageBySchool[school] = Call(GetSpellBonusDamage, school) end
    local configs = Call(C_Traits and C_Traits.GetConfigsByType,
        Enum and Enum.TraitConfigType and Enum.TraitConfigType.Generic)
    result.traitConfigLookup = configs
    if configs.status == "ok" and type(configs.values[1]) == "table" then
        for _, configID in pairs(configs.values[1]) do
            if type(configID) == "number" then
                local nodes = {}
                for _, node in ipairs(Probe.cases.traitNodes) do
                    nodes[node] = Call(C_Traits and C_Traits.GetNodeInfo, configID, node)
                end
                result.traitConfigs[configID] = {nodes = nodes,
                    staged = Call(C_Traits and C_Traits.GetStagedChanges, configID)}
            end
        end
    end
    return result
end

local function Store(kind, details)
    if not active then return end
    if #active.samples >= MAX_SAMPLES then
        active.stoppedReason = "sample limit"
        active = nil
        Print("Limite atteinte. Capture arrêtée ; les données précédentes sont conservées.")
        return
    end
    active.samples[#active.samples + 1] = {kind = kind, context = Context(), details = details}
end

local function CaptureSpell(case, reason)
    Store("spell", {code = case.code, id = case.id, reason = reason,
        info = Call(C_Spell and C_Spell.GetSpellInfo, case.id),
        description = Call(C_Spell and C_Spell.GetSpellDescription, case.id),
        tooltip = Call(C_TooltipInfo and C_TooltipInfo.GetSpellByID, case.id),
        known = Call(C_SpellBook and C_SpellBook.IsSpellKnown, case.id),
    })
end

local function CaptureItem(case, reason)
    Store("item", {code = case.code, id = case.id, reason = reason,
        info = Call(C_Item and C_Item.GetItemInfo, case.id),
        tooltip = Call(C_TooltipInfo and C_TooltipInfo.GetItemByID, case.id),
        stats = Call(C_Item and C_Item.GetItemStats, "item:" .. case.id),
    })
end

local function CaptureAuras(unit, reason)
    local wanted = {}
    for _, id in ipairs(Probe.cases.auraSpells) do wanted[id] = true end
    for _, filter in ipairs({"HELPFUL", "HARMFUL"}) do
        for index = 1, 255 do
            local result = Call(C_UnitAuras and C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
            if result.status ~= "ok" then
                Store("aura lookup", {unit = unit, filter = filter, reason = reason, result = result})
                break
            end
            local aura = result.values[1]
            if type(aura) ~= "table" then
                if aura == "<restricted>" then
                    Store("aura lookup", {unit = unit, filter = filter, reason = reason, result = result})
                end
                break
            end
            if aura.spellId == "<restricted>" then
                Store("aura lookup", {unit = unit, filter = filter, reason = reason, result = result})
            end
            if type(aura.spellId) == "number"
                and (wanted[aura.spellId] or active.profile == "cible" or active.profile == "auras") then
                Store("aura", {unit = unit, filter = filter, index = index, reason = reason,
                    aura = result,
                    unitSex = Call(UnitSex, unit),
                    tooltipGetter = "C_TooltipInfo.GetUnitAuraByAuraInstanceID",
                    tooltipArguments = Snapshot({unit, aura.auraInstanceID, n = 2}),
                    byInstance = Call(C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID,
                        unit, aura.auraInstanceID),
                    tooltip = Call(C_TooltipInfo and C_TooltipInfo.GetUnitAuraByAuraInstanceID,
                        unit, aura.auraInstanceID),
                    casterLevel = type(aura.sourceUnit) == "string"
                        and Call(UnitLevel, aura.sourceUnit) or {status = "caster unavailable"},
                })
            end
        end
    end
end

-- Unit tooltips: record every unit API the FRS NPC renderer reads, with all return slots.
local UNIT_APIS = {"UnitGUID", "UnitName", "UnitCreatureType", "UnitCreatureFamily", "UnitClassification",
    "UnitClass", "UnitRace", "UnitLevel", "UnitSex", "UnitFactionGroup", "GetGuildInfo",
    "UnitIsPlayer", "UnitIsDead", "UnitIsCorpse", "UnitIsTapDenied"}

local function CaptureUnit(tip)
    local token = Call(tip.GetUnit, tip)
    local unit = token.status == "ok" and token.values[2]
    local result = {token = token, corpseLabel = Snapshot(_G.CORPSE)}
    if type(unit) ~= "string" then return result end
    result.apis = {}
    for _, name in ipairs(UNIT_APIS) do result.apis[name] = Call(_G[name], unit) end
    return result
end

local CaptureDependencies, CaptureGlobals

local function CaptureHover(tip, data, kind, phase)
    if not active or active.profile == "api" then return end
    if active.profile == "auras" and kind ~= "UnitAura" then return end
    if active.profile == "cible" and kind == "Unit" then return end
    local visible = {}
    local record = {data = Snapshot(data), visible = visible, dataType = kind, phase = phase}
    if tip and kind == "Unit" then record.unit = CaptureUnit(tip) end
    if tip then
        record.primaryData = Call(tip.GetPrimaryTooltipData, tip)
        record.primaryInfo = Call(tip.GetPrimaryTooltipInfo, tip)
        record.processingInfo = Call(tip.GetProcessingTooltipInfo, tip)
        record.item = Call(tip.GetItem, tip)
        record.spell = Call(tip.GetSpell, tip)
        local count = Call(tip.NumLines, tip)
        if count.status == "ok" and type(count.values[1]) == "number" then
            for index = 1, count.values[1] do
                local left = tip.GetLeftLine and tip:GetLeftLine(index)
                local right = tip.GetRightLine and tip:GetRightLine(index)
                visible[index] = {left = left and Call(left.GetText, left),
                    right = right and Call(right.GetText, right)}
            end
        end
        local addon = _G.ForeverRosettaStone
        local stacked = addon and addon.stackedTooltips and addon.stackedTooltips[tip]
        if Readable(stacked) and type(stacked) == "table" and Readable(stacked.first) and Readable(stacked.last)
            and type(stacked.first) == "number" and type(stacked.last) == "number" then
            record.translationRange = {first = stacked.first, last = stacked.last}
            record.nativeVisible = {}
            for index, row in ipairs(visible) do
                if index < stacked.first or index > stacked.last then
                    record.nativeVisible[#record.nativeVisible + 1] = row
                end
            end
        end
    end
    record.dependencies = CaptureDependencies(record, kind)
    Store("hover", record)
end

-- API fixture pass: one snapshot of every configured data API, keyed for offline replay.
-- ArgumentKey must stay identical to tests/lua/support/client-api-fixture.lua.
local function ArgumentKey(...)
    local parts = {}
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if type(value) == "string" then parts[index] = string.format("%q", value)
        elseif type(value) == "number" and value == math.floor(value) and math.abs(value) < 2 ^ 53 then
            parts[index] = string.format("%d", value)
        elseif type(value) == "number" then parts[index] = string.format("%.17g", value)
        else parts[index] = tostring(value) end
    end
    return table.concat(parts, ", ")
end

local function Resolve(path)
    local value = _G
    for part in path:gmatch("[^%.]+") do
        if type(value) ~= "table" then return nil end
        value = value[part]
    end
    return value
end

CaptureGlobals = function()
    local globals = {}
    for _, key in ipairs(Probe.cases.api and Probe.cases.api.globals or {}) do globals[key] = Snapshot(_G[key]) end
    return globals
end

CaptureDependencies = function(record, kind)
    local calls = {}
    local function Read(path, ...)
        calls[path] = calls[path] or {}
        local result = Call(Resolve(path), ...)
        calls[path][ArgumentKey(...)] = result
        return result
    end
    local id = type(record.data) == "table" and record.data.id
    Read("UnitSex", "player")
    Read("UnitFactionGroup", "player")
    Read("GetBindLocation")
    if kind == "UnitAura" then
        local info = record.processingInfo
        info = info and info.status == "ok" and info.values[1]
        local name, args = type(info) == "table" and info.getterName, type(info) == "table" and info.getterArgs
        local result
        if type(args) == "table" then
            if type(args[1]) == "string" then Read("UnitSex", args[1]) end
            if name == "GetUnitAuraByAuraInstanceID" or name == "GetUnitBuffByAuraInstanceID"
                or name == "GetUnitDebuffByAuraInstanceID" then
                result = Read("C_UnitAuras.GetAuraDataByAuraInstanceID", args[1], args[2])
            elseif name == "GetUnitAura" or name == "GetUnitBuff" or name == "GetUnitDebuff" then
                local filter = args[3] ~= "<nil>" and args[3] or nil
                filter = filter or (name == "GetUnitBuff" and "HELPFUL" or name == "GetUnitDebuff" and "HARMFUL" or nil)
                result = Read("C_UnitAuras.GetAuraDataByIndex", args[1], args[2], filter)
            end
        end
        local aura = result and result.status == "ok" and result.values[1]
        id = type(aura) == "table" and aura.spellId
    elseif kind == "Spell" and type(id) ~= "number" then
        id = record.spell and record.spell.status == "ok" and record.spell.values[2]
    end
    if kind ~= "Item" and type(id) == "number" then
        Read("C_TradeSkillUI.GetRecipeSchematic", id, false)
        Read("C_Spell.GetSpellPowerCost", id)
    end
    record.entityID = type(id) == "number" and id or nil
    return calls
end

local function ApiArguments(spec, id)
    local format = type(spec) == "table" and spec.format
    local args = id == false and {n = 0} or {n = 1, format and string.format(format, id) or id}
    for _, value in ipairs(type(spec) == "table" and spec.suffix or {}) do
        args.n = args.n + 1
        args[args.n] = value
    end
    return args
end

local function CaptureApi(run)
    local api, calls = Probe.cases.api, {}
    for kind, specs in pairs(api.calls) do
        local ids = kind == "none" and {false} or api.ids[kind] or {}
        for _, spec in ipairs(specs) do
            local path = type(spec) == "table" and spec.api or spec
            calls[path] = calls[path] or {}
            for _, id in ipairs(ids) do
                local args = ApiArguments(spec, id)
                local key = ArgumentKey(unpack(args, 1, args.n))
                calls[path][key] = Call(Resolve(path), unpack(args, 1, args.n))
            end
        end
    end
    calls.UnitSex = calls.UnitSex or {}
    for _, spec in ipairs(api.exactCalls or {}) do
        calls[spec.api] = calls[spec.api] or {}
        local args = spec.args or {}
        calls[spec.api][ArgumentKey(unpack(args, 1, args.n or #args))] =
            Call(Resolve(spec.api), unpack(args, 1, args.n or #args))
    end
    calls.UnitSex[ArgumentKey("player")] = Call(UnitSex, "player")
    calls.UnitFactionGroup = {[ArgumentKey("player")] = Call(UnitFactionGroup, "player")}
    calls.GetBindLocation = {[""] = Call(GetBindLocation)}
    local globals = CaptureGlobals()
    local pending = {}
    for kind, ids in pairs(run.pending) do
        for id in pairs(ids) do pending[#pending + 1] = kind .. ":" .. id end
    end
    table.sort(pending)
    Store("api", {calls = calls, globals = globals, pendingAtCapture = pending,
        loadResults = Snapshot(run.loadResults), settleRounds = run.settleRounds or 0})
end

-- Tooltip rows that still show the client's loading placeholder for a referenced item
-- (a reagent, a set piece); the client requests those items when the tooltip is built.
local function UnloadedTooltips()
    local marker, api, count = _G.RETRIEVING_ITEM_INFO, Probe.cases.api, 0
    if type(marker) ~= "string" or marker == "" then return 0 end
    for kind, specs in pairs(api.calls) do
        for _, spec in ipairs(specs) do
            local path = type(spec) == "string" and spec or nil
            local method = path and path:match("^C_TooltipInfo%.") and Resolve(path)
            for _, id in ipairs(method and api.ids[kind] or {}) do
                local result = Call(method, id)
                local data = result.status == "ok" and result.values[1]
                for _, line in ipairs(type(data) == "table" and type(data.lines) == "table" and data.lines or {}) do
                    if type(line.leftText) == "string" and line.leftText:find(marker, 1, true) then
                        count = count + 1
                        break
                    end
                end
            end
        end
    end
    return count
end

local function FinishApi(run, reason, settling)
    if active ~= run or run.captured or (run.settling and not settling) then return end
    local api = Probe.cases.api
    local rounds = api.settleRounds or 6
    if C_Timer and C_Timer.After and (run.settleRounds or 0) < rounds then
        local unloaded = UnloadedTooltips()
        if unloaded > 0 then
            run.settling, run.settleRounds = true, (run.settleRounds or 0) + 1
            Print("Capture « api » : " .. unloaded .. " tooltip(s) attendent encore des objets liés ("
                .. run.settleRounds .. "/" .. rounds .. ")…")
            C_Timer.After(api.settleDelay or 5, function() FinishApi(run, reason, true) end)
            return
        end
    end
    run.captured = true
    CaptureApi(run)
    run.stoppedReason = reason
    run.pending = nil
    active = nil
    Print("Capture « api » terminée (" .. reason .. "). Fais /reload pour écrire le fichier SavedVariables.")
end

local function PendingCount(run)
    local count = 0
    for _, ids in pairs(run.pending) do for _ in pairs(ids) do count = count + 1 end end
    return count
end

local function StartApi(run)
    local api = Probe.cases.api
    run.pending = {spell = {}, item = {}}
    run.loadResults = {spell = {}, item = {}}
    local loaders = {
        spell = {cached = C_Spell and C_Spell.IsSpellDataCached, request = C_Spell and C_Spell.RequestLoadSpellData},
        item = {cached = C_Item and C_Item.IsItemDataCachedByID, request = C_Item and C_Item.RequestLoadItemDataByID},
    }
    for kind, loader in pairs(loaders) do
        for _, id in ipairs(api.ids[kind] or {}) do
            local cached = Call(loader.cached, id)
            if not (cached.status == "ok" and cached.values[1] == true) and type(loader.request) == "function" then
                run.pending[kind][id] = true
                Call(loader.request, id)
            end
        end
    end
    if PendingCount(run) == 0 or not (C_Timer and C_Timer.After) then
        FinishApi(run, PendingCount(run) == 0 and "api complete" or "api timeout")
        return
    end
    Print("Capture « api » : chargement de " .. PendingCount(run) .. " entrée(s) du cache client…")
    C_Timer.After(api.loadTimeout or 10, function() FinishApi(run, "api timeout") end)
end

local function ApiLoaded(kind, id, success)
    local run = active
    if not run or run.profile ~= "api" or not run.pending or not run.pending[kind] then return end
    if not run.pending[kind][id] then return end
    run.loadResults[kind][id] = Snapshot(success)
    run.pending[kind][id] = nil
    if PendingCount(run) == 0 then FinishApi(run, "api complete") end
end

local function Status()
    local runs = RosettaTooltipCheckData and RosettaTooltipCheckData.runs
    Print(active and ("Capture « " .. active.profile .. " » : " .. #active.samples .. " relevés.")
        or ("Arrêté. " .. tostring(runs and #runs or 0) .. " session(s) conservée(s)."))
end

local function Start(profile, label)
    if not loaded then Print("Données non prêtes ; aucune capture démarrée."); return end
    if InCombatLockdown and InCombatLockdown() then Print("Démarre hors combat."); return end
    if active then active.stoppedReason = "new profile" end
    active = {profile = profile, startedAt = time(), build = Call(GetBuildInfo),
        locale = Call(GetLocale), cases = Snapshot(Probe.cases), samples = {},
        tooltipTypes = Snapshot(Enum and Enum.TooltipDataType)}
    active.label = label
    -- Client UI labels are stable within one locale/run. Store them once, not per hover.
    active.globals = CaptureGlobals()
    table.insert(RosettaTooltipCheckData.runs, active)
    if profile == "api" then
        StartApi(active)
        return
    end
    if profile == "auras" then
        CaptureAuras("player", "profile start")
        CaptureAuras("target", "profile start")
        Print("Aura capture started for player and target. Changes are recorded automatically; /frsverify stop ends capture.")
        return
    end
    if profile == "unites" then
        Print("Capture « unites » démarrée. Survole des PNJ et des mobs (vivants et morts) ; /frsverify stop pour terminer.")
        return
    end
    if profile == "cible" then
        Print("Capture ciblée démarrée. Survole sorts, objets et auras ; /frsverify stop pour terminer.")
        return
    end
    Print("Capture « " .. profile .. " » démarrée. Survole les objets et les auras ; /frsverify stop pour terminer.")
    for _, case in ipairs(Probe.cases.spells) do
        Call(C_Spell and C_Spell.RequestLoadSpellData, case.id)
        CaptureSpell(case, "profile start")
    end
    for _, case in ipairs(Probe.cases.items) do
        Call(C_Item and C_Item.RequestLoadItemDataByID, case.id)
        CaptureItem(case, "profile start")
    end
    CaptureAuras("player", "profile start")
    CaptureAuras("target", "profile start")
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
frame:RegisterEvent("SPELL_DATA_LOAD_RESULT")
frame:RegisterEvent("SPELL_TEXT_UPDATE")
frame:SetScript("OnEvent", function(_, event, ...)
    local argument = ...
    if event == "ADDON_LOADED" then
        if argument ~= addonName then return end
        if RosettaTooltipCheckData == nil then RosettaTooltipCheckData = {schemaVersion = 1, runs = {}} end
        local data = RosettaTooltipCheckData
        if type(data) ~= "table" or data.schemaVersion ~= 1 or type(data.runs) ~= "table" then
            Print("Données sauvegardées incompatibles. Aucun écrasement effectué."); return
        end
        loaded = true
        Print("Prêt. Aucune collecte automatique. /frsverify equip, zero, unites, api, auras ou cible.")
        return
    end
    if not active then return end
    local success = select(2, ...)
    local ok, error = pcall(function()
        if active.profile == "api" then
            if event == "ITEM_DATA_LOAD_RESULT" then ApiLoaded("item", argument, success)
            elseif event == "SPELL_DATA_LOAD_RESULT" then ApiLoaded("spell", argument, success) end
        elseif event == "UNIT_AURA" and (argument == "player" or argument == "target") then
            CaptureAuras(argument, event)
        elseif event == "PLAYER_TARGET_CHANGED" then CaptureAuras("target", event)
        elseif event == "ITEM_DATA_LOAD_RESULT" then
            for _, case in ipairs(Probe.cases.items) do
                if case.id == argument then CaptureItem(case, event) end
            end
        elseif event == "SPELL_DATA_LOAD_RESULT" or event == "SPELL_TEXT_UPDATE" then
            for _, case in ipairs(Probe.cases.spells) do
                if case.id == argument then CaptureSpell(case, event) end
            end
        end
    end)
    if not ok then Store("collector error", {event = event, error = Snapshot(error)}) end
end)

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    for _, key in ipairs({"Item", "Spell", "UnitAura", "Unit"}) do
        local value = Enum.TooltipDataType[key]
        if value then
            TooltipDataProcessor.AddTooltipPostCall(value, function(tip, data)
                if not active or active.profile == "api" then return end
                local ok, error = pcall(CaptureHover, tip, data, key, "postCall")
                if not ok then Store("collector error", {source = "hover", error = Snapshot(error)}) end
                local info = tip and Call(tip.GetProcessingTooltipInfo, tip)
                info = info and info.status == "ok" and info.values[1]
                if key == "Spell" and type(info) == "table" and info.getterName == "GetTraitEntry"
                    and Readable(data.dataInstanceID) and type(data.dataInstanceID) == "number"
                    and C_Timer and C_Timer.After then
                    local run, instance = active, data.dataInstanceID
                    C_Timer.After(0, function()
                        if active ~= run then return end
                        local current = Call(tip.GetPrimaryTooltipData, tip)
                        current = current.status == "ok" and current.values[1]
                        if type(current) ~= "table" or current.dataInstanceID ~= instance then return end
                        local captured, failure = pcall(CaptureHover, tip, current, key, "nextFrame")
                        if not captured then Store("collector error", {source = "talent next frame", error = Snapshot(failure)}) end
                    end)
                end
            end)
        end
    end
else
    warned = true
end

SLASH_ROSETTATOOLTIPCHECK1 = "/frsverify"
SlashCmdList.ROSETTATOOLTIPCHECK = function(command)
    command = command:lower():match("^%s*(.-)%s*$")
    local label = command:match("^cible%s+(.+)$")
    if label then command = "cible" end
    if command == "equip" or command == "zero" or command == "partial" or command == "autre"
        or command == "unites" or command == "api" or command == "cible" or command == "auras" then
        local ok, error = pcall(Start, command, label)
        if not ok then Store("collector error", {source = "start", error = Snapshot(error)}); Print(tostring(error)) end
        if warned then Print("Capture au survol indisponible ; les appels directs restent enregistrés.") end
    elseif command == "clear" then
        -- Stop first so deferred callbacks cannot repopulate the cleared SavedVariables.
        if active then active.stoppedReason = "manual clear" end
        active = nil
        RosettaTooltipCheckData = {schemaVersion = 1, runs = {}}
        loaded = true
        Print("Toutes les captures du probe ont été effacées. Aucune collecte active. Fais /reload pour sauvegarder le fichier vide.")
    elseif command == "stop" then
        if active then active.stoppedReason = "manual stop"; active = nil end
        Status()
        Print("Fais /reload pour écrire le fichier SavedVariables ; les anciennes sessions sont conservées.")
    elseif command == "" or command == "status" then Status()
    else Print("Commandes : equip, zero, partial, autre, unites, api, auras, cible, stop, clear, status.") end
end
