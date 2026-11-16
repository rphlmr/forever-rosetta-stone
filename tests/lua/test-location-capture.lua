local Addon = {}
canaccessallvalues = function(...)
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if type(value) == "table" and value.restricted then return false end
    end
    return true
end
GetTime = function() return 123 end
GetZoneText = function() return "Dun Morogh" end
GetSubZoneText = function() return "Anvilmar" end
GetMinimapZoneText = GetSubZoneText
GetRealZoneText = GetZoneText
local owner = {
    areaID = 77, mapID = 1426, data = { areaID = 77 },
    unanticipatedContext = { location = { subregion = 77 } },
    secretAreaID = { restricted = true },
    GetName = function() return "MinimapCluster.ZoneTextButton" end,
    GetObjectType = function() return "Button" end,
    GetID = function() return 0 end,
    IsForbidden = function() return false end,
    GetAttribute = function(_, key) if key == "areaID" then return 77 end end,
    GetParent = function() return {
        inheritedContext = { subregion = 77 },
        IsForbidden = function() return false end,
    } end,
}
owner.cycle = owner
owner.deep = { child = { child = { child = { child = { child = { child = { hidden = 77 } } } } } } }
local source = {
    extraContext = { region = 77 },
    IsForbidden = function() return false end,
    GetName = function() return "GameTooltip" end,
    GetOwner = function() return owner end,
    GetPrimaryTooltipData = function() return nil end,
    NumLines = function() return 2 end,
    GetLeftLine = function(_, index)
        return { GetText = function() return index == 1 and "Dun Morogh" or "Anvilmar" end }
    end,
    GetRightLine = function() return { GetText = function() end } end,
}
C_Map = {
    GetBestMapForUnit = function() return 1426 end,
    GetMapInfo = function(id) return { mapID = id, parentMapID = 1415 } end,
    GetMapInfoAtPosition = function(id) return { mapID = id } end,
    GetPlayerMapPosition = function() return { GetXY = function() return 0.29, 0.68 end } end,
    GetAreaInfo = function(id) return id == 77 and "Anvilmar" or "Coldridge Valley" end,
}
C_MapExplorationInfo = { GetExploredAreaIDsAtPosition = function() return { 132, 77 } end }
assert(loadfile("ForeverRosettaStone/diagnostics/diagnostics.lua"))("ForeverRosettaStone", Addon)
Addon.IsDebugPicking = function() return true end
Addon.GetTooltipInputMode = function() return "gamepad" end
Addon.RefreshDebugPickedList = function() end
Addon.GetTargetLocale = function() return "frFR" end
ForeverRosettaStoneDB = { GetPlayerLocation = function(_, locale)
    assert(locale == "frFR")
    return { zone = { areaID = 77, name = "Courbenclume", status = "resolved" }, subzone = { status = "empty" } }
end }
Addon:RecordDebugSurface(source, "minimapLocation", "Anvilmar", "zoneHeader")
assert(not Addon.debugPicker.captureError)
local entry = Addon.debugPicker.byID["minimapLocation:Anvilmar"]
local location = entry.data
assert(location.zoneText == "Dun Morogh" and location.subzoneText == "Anvilmar")
assert(location.uiMapID == 1426 and location.mapInfo.parentMapID == 1415)
assert(location.mapInfoAtPosition.mapID == 1426 and location.owner.frameID == 0)
assert(location.position.x == 0.29 and location.position.y == 0.68)
assert(location.candidateAreaIDs[1] == 132 and location.candidateAreaIDs[2] == 77)
assert(location.candidateAreas[2].areaID == 77 and location.candidateAreas[2].nativeName == "Anvilmar")
assert(location.owner.idFields.areaID == 77 and location.owner.attributes.areaID == 77)
assert(location.owner.idFields.secretAreaID == "<restricted>")
assert(location.owner.fields.data.areaID == 77)
assert(location.owner.fields.unanticipatedContext.location.subregion == 77,
    "Do not omit tables merely because their key is not an expected data or ID field")
assert(location.owner.fields.cycle == "<cycle>")
assert(location.owner.fields.deep.child.child.child.child.child == "<depth limit>")
assert(location.ownerParent.fields.inheritedContext.subregion == 77)
assert(location.tooltipFrame.fields.extraContext.region == 77)
assert(location.primaryTooltipData == "<not available>")
assert(location.resolvedLocation.zone.areaID == 77 and location.resolvedLocation.subzone.status == "empty")
assert(entry.lines[1].leftText == "Dun Morogh" and entry.lines[2].leftText == "Anvilmar")
GetSubZoneText = function() return "Coldridge Valley" end
owner.data.areaID = 132
assert(location.subzoneText == "Anvilmar" and location.owner.fields.data.areaID == 77,
    "hover snapshot must not change when the live location or owner changes")
C_Map = nil
C_MapExplorationInfo = nil
Addon:RecordDebugSurface(source, "minimapLocation", "Coldridge Valley", "zoneHeader")
assert(not Addon.debugPicker.captureError, "missing APIs must not discard the capture")
location = Addon.debugPicker.byID["minimapLocation:Coldridge Valley"].data
assert(location.subzoneText == "Coldridge Valley")
assert(location.uiMapID:find("<unavailable:", 1, true))
assert(location.candidateAreaIDs == "<not available>")
owner.wide = {}
for index = 1, 2000 do owner.wide["entry" .. index] = index end
Addon:RecordDebugSurface(source, "minimapLocation", "Coldridge Valley", "zoneHeader")
location = Addon.debugPicker.byID["minimapLocation:Coldridge Valley"].data
assert(location.owner.fields["<truncated>"] or location.owner.fields.wide["<truncated>"],
    "Large frame graphs must explicitly report a bounded capture rather than stalling the picker")
print("PASS: hover-time zone/subzone, candidate IDs, owner data, restricted values and missing location APIs")
