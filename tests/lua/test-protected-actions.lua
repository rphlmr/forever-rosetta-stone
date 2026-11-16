local Addon = ...
local checks = 0
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    checks = checks + 1
end

local events = Addon.protectedActionEvents
assert(events, "opening diagnostics arms protected-action monitoring")
Addon:InitializeSafetyMonitoring()
equal(Addon.protectedActionEvents, events, "reopening diagnostics reuses the same monitoring listener")
equal(events.events.ADDON_ACTION_BLOCKED, true, "blocked action event is registered")
equal(events.events.ADDON_ACTION_FORBIDDEN, true, "forbidden action event is registered")
local count, lifecycle = #Addon.blockedActions, Addon.lifecycle
events:Fire("OnEvent", "ADDON_ACTION_BLOCKED", "OtherAddon", "SomeFunction()")
equal(#Addon.blockedActions, count + 1, "shared UI blocked actions from other addons are retained")
equal(Addon.errorLog[#Addon.errorLog]:find("OtherAddon / SomeFunction()", 1, true) ~= nil, true,
    "saved blocked actions identify the source addon")
events:Fire("OnEvent", "ADDON_ACTION_BLOCKED", "ForeverRosettaStone", "SomeFunction()")
equal(Addon.blockedActions[#Addon.blockedActions],
    "ADDON_ACTION_BLOCKED: ForeverRosettaStone / SomeFunction()\nstack line 1\nstack line 2",
    "event, action and synchronous call stack are captured")
equal(Addon.lifecycle, lifecycle, "a blocked action does not suspend the addon")
Addon:ShowErrorDialog()
equal(Addon.errorDialog.report:find("SomeFunction()", 1, true) ~= nil, true,
    "error report includes the protected function")
equal(Addon.errorDialog.report:find("stack line 1\nstack line 2", 1, true) ~= nil, true,
    "error report includes the protected action call stack")
Addon.errorDialog.frame:Hide()
local savedCount = #Addon.errorLog
DisplayInterfaceActionBlockedMessage()
equal(#Addon.errorLog, math.min(savedCount + 1, 10), "generic navigation rejections enter saved error history")
equal(Addon.blockedActions[#Addon.blockedActions], "Interface action blocked\nstack line 1\nstack line 2",
    "generic navigation rejections retain the synchronous call stack")
equal(Addon.lifecycle, lifecycle, "a generic blocked action does not suspend translations")
local originalIsSecureVariable = issecurevariable
local originalButton = SmartNavigation.currentButton
SmartNavigation.currentButton = originalButton or {}
issecurevariable = function(_, field) return field ~= "currentButton", field == "currentButton" and "ForeverRosettaStone" or nil end
DisplayInterfaceActionBlockedMessage()
issecurevariable = originalIsSecureVariable
SmartNavigation.currentButton = originalButton
equal(Addon.blockedActions[#Addon.blockedActions]:find("SmartNavigation.currentButton: source=ForeverRosettaStone", 1, true) ~= nil,
    true, "navigation rejections identify tainted gamepad fields without modifying them")
local manager = GamepadMode.FrameControlsManager
local previousShown = manager.shownFrames
local nativeWindow = CreateFrame("Frame", "DiagnosticNativeWindow", UIParent)
manager.shownFrames = { nativeWindow }
issecurevariable = function(owner, key)
    if owner == manager.shownFrames and key == 1 then return false, "ForeverRosettaStone" end
    return true
end
DisplayInterfaceActionBlockedMessage()
equal(Addon.blockedActions[#Addon.blockedActions]:find(
    "FrameControlsManager.shownFrames.1=DiagnosticNativeWindow: source=ForeverRosettaStone", 1, true) ~= nil,
    true, "blocked-action diagnostics identify nested tainted slots and their native frame")
manager.shownFrames, issecurevariable = previousShown, originalIsSecureVariable
return checks
