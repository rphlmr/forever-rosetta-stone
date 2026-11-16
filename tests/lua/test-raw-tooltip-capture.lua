local Addon = { preferences = { locale = "frFR" } }
canaccessallvalues = function(...)
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if type(value) == "table" and value.restricted then return false end
    end
    return true
end
GetTime = function() return 10 end
GetLocale = function() return "enUS" end
GetBuildInfo = function() return "1.60.1", "70888" end
C_AddOns = { GetAddOnMetadata = function() return "test" end }
assert(loadfile("ForeverRosettaStone/diagnostics/diagnostics.lua"))("ForeverRosettaStone", Addon)
Addon.IsDebugPicking = function() return true end
Addon.GetTooltipInputMode = function() return "mouse" end
Addon.RefreshDebugPickedList = function() end
Addon.GetTargetLocale = function() return "frFR" end
Addon.GetTooltipComponent = function() end
Addon.GetDebugKindLabel = function(_, value) return value end
Addon.DebugText = function(_, value) return value end
ForeverRosettaStoneDB = { catalogVersion = "test" }

local payload = { type = 2, lines = { { leftText = "Deputy Willem", unitToken = "nameplate11" } } }
for index = 1, 250 do payload["field" .. index] = index end
local nested = payload
for index = 1, 15 do nested.child = {}; nested = nested.child end
nested.deepest = "preserved-deep-value"
payload.secret = { restricted = true }
payload.self = payload
local info = { getterName = "GetUnit", getterArgs = { n = 3, "nameplate11", nil, false }, tooltipData = payload }
local appended = { getterName = "GetHyperlink", getterArgs = { "spell:1" }, tooltipData = { extra = "appended" } }
local source = {
    infoList = { info, appended },
    IsForbidden = function() return false end,
    GetName = function() return "GameTooltip" end,
    GetPrimaryTooltipData = function() return payload end,
    GetPrimaryTooltipInfo = function() return info end,
    GetProcessingTooltipInfo = function() return appended end,
    GetUnit = function() return "Deputy Willem", "nameplate11" end,
    GetItem = function() return nil, nil end,
    GetSpell = function() return nil end,
    NumLines = function() return 1 end,
    GetLeftLine = function() return { GetText = function() return "Deputy Willem" end } end,
    GetRightLine = function() return { GetText = function() end } end,
}
UnitFactionGroup = function(unit)
    assert(unit == "nameplate11")
    return "Alliance", nil, false, nil
end
UnitGUID = function() return "Creature-0-7096-0-4-823-test" end
UnitReaction = function() error("unavailable unit reaction") end
Addon:RecordDebugSurface(source, "npc", 823, "unit", payload)
assert(not Addon.debugPicker.captureError, Addon.debugPicker.captureError)
local entry = Addon.debugPicker.byID["npc:823"]
assert(entry.data.field250 == 250, "Do not truncate tooltip tables at 100 fields")
nested = entry.data
for index = 1, 15 do nested = nested.child end
assert(nested.deepest == "preserved-deep-value", "Do not truncate nested tooltip data")
assert(entry.data.self == "<cycle>" and entry.data.secret == "<restricted>")
local evidence = entry.tooltipEvidence
assert(evidence.primaryInfo.getterName == "GetUnit")
assert(evidence.processingInfo.getterName == "GetHyperlink")
assert(evidence.infoList[2].tooltipData.extra == "appended")
assert(evidence.primaryInfo.getterArgs.n == 3 and evidence.primaryInfo.getterArgs[3] == false)
assert(evidence.unitToken == "nameplate11")
assert(evidence.unitAPIs.UnitFactionGroup.returnCount == 4)
assert(evidence.unitAPIs.UnitFactionGroup.values[1] == "Alliance")
assert(evidence.unitAPIs.UnitFactionGroup.values[2] == "<nil>")
assert(evidence.unitAPIs.UnitFactionGroup.values[3] == false)
assert(evidence.unitAPIs.UnitFactionGroup.values[4] == "<nil>")
assert(evidence.unitAPIs.UnitReaction.error:find("unavailable unit reaction", 1, true))
assert(evidence.unitAPIs.UnitCreatureType.status == "missing API")
payload.field250 = 999
assert(entry.data.field250 == 250, "Capture evidence must not follow later payload changes")
local report = Addon:GetEntityDebugReport("npc", 823)
assert(report:find("field250 = 250", 1, true) and report:find("preserved-deep-value", 1, true))
assert(report:find('extra = "appended"', 1, true))
assert(not report:find("<depth limit>", 1, true) and not report:find("<truncated>", 1, true))
Enum = { TooltipDataType = { Quest = 10 } }
Addon.GetTooltipComponents = function()
    return { { kind = "brokenResolver", ResolveData = function() error("resolver failed") end } }
end
payload.id = { restricted = true }
Addon:RecordDebugTooltip(source, payload)
assert(not Addon.debugPicker.captureError)
entry = Addon.debugPicker.byID["tooltip:Deputy Willem"]
assert(entry.data.id == "<restricted>" and entry.data.field250 == 999)
assert(entry.resolutionErrors.brokenResolver:find("resolver failed", 1, true))
Addon:RecordDebugTooltip(source, { restricted = true })
assert(not Addon.debugPicker.captureError)
assert(Addon.debugPicker.byID["tooltip:Deputy Willem"].data == "<restricted>",
    "A restricted payload must be marked instead of silently dropping the tooltip")
print("PASS: complete readable tooltip payloads, appended data, getter arguments, unit API returns and explicit restrictions")
