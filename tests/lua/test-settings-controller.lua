local Addon, press, flushTimers = ...
local checks = 0
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    checks = checks + 1
end

local manager = GamepadMode.FrameControlsManager
local categoryButton = CreateFrame("Button", nil, SettingsPanel)
local nativeControl = CreateFrame("Button", nil, SettingsPanel)
SettingsPanel.categoryButton, SettingsPanel.nativeDefaultButton = categoryButton, nativeControl
SettingsPanel.CloseButton = CreateFrame("Button", nil, SettingsPanel)
SettingsPanel.CloseButton:SetScript("OnClick", function() SettingsPanel:Hide() end)
categoryButton:SetScript("OnClick", function() SettingsPanel:FocusContainer() end)
SettingsPanel:HookScript("OnShow", function(owner) manager:FrameShown(owner) end)
SettingsPanel:HookScript("OnHide", function(owner)
    owner.containerFocused = false
    manager:FrameHidden(owner)
    SmartNavigation:RemovePanelInfo(owner)
end)
Addon:OpenSettings()
SmartNavigation:SelectButton(categoryButton)
press("PAD1")
equal(SmartNavigation:GetCurrentButton(), nativeControl, "addon does not replace native content focus")
equal(SmartNavigation.targetButtons[SettingsPanel], nil, "native settings has no addon focus target")
equal(Addon.settingsPanel.FeatureScroll, nil, "addon no longer owns a settings scroll frame")
equal(Addon.settingsPanel.Relayout, nil, "addon no longer overrides control layout")
press("PAD2")
equal(SettingsPanel:IsShown(), true, "native first B returns to categories")
equal(SmartNavigation:GetCurrentButton(), categoryButton, "native B focuses category")
press("PAD2")
equal(SettingsPanel:IsShown(), false, "native second B closes settings")
equal(manager:GetActiveFrame(), WorldMapFrame, "closing returns native map focus")
equal(Addon.lifecycle, "ready", "native settings leaves addon ready")
flushTimers()
local openCategory = Settings.OpenToCategory
local reopenCount = 0
Settings.OpenToCategory = function(id)
    reopenCount = reopenCount + 1
    openCategory(id)
    SettingsPanel:FocusContainer()
end
local confirmation = Addon.settingsResetDialog
for _, action in ipairs({ "cancel", "reset" }) do
    Addon:OpenSettings()
    SmartNavigation.targetButtons[confirmation.window] = confirmation.accept
    Addon:ShowSettingsResetDialog()
    equal(SmartNavigation:GetCurrentButton(), nil, action .. " opens without preselecting confirmation")
    equal(SmartNavigation.targetButtons[confirmation.window], nil, action .. " clears a previous default target")
    press("PAD1")
    equal(confirmation.frame:IsShown(), true, "A cannot confirm before navigating to a button")
    local before = reopenCount
    if action == "reset" then
        SmartNavigation:SelectButton(confirmation.accept)
        press("PAD1")
    else press("PAD2") end
    equal(confirmation.frame:IsShown(), false, action .. " closes confirmation from controller")
    equal(reopenCount, before, action .. " waits for native popup teardown")
    SettingsPanel.containerFocused = false
    SmartNavigation.currentButton = nil
    flushTimers()
    equal(reopenCount, before + 1, action .. " reactivates the same native category after teardown")
    equal(SmartNavigation:GetCurrentButton(), nativeControl, action .. " restores controller selection")
    press("PAD2")
    equal(SmartNavigation:GetCurrentButton(), categoryButton, action .. " preserves B to categories")
    press("PAD2")
    equal(SettingsPanel:IsShown(), false, action .. " preserves B to close Settings")
end
Addon:OpenSettings()
Addon:ShowSettingsResetDialog()
local before = reopenCount
confirmation.cancel:Fire("OnClick")
SettingsPanel:Hide()
flushTimers()
equal(reopenCount, before, "closing Settings while popup closes does not reopen it")
Addon:OpenSettings()
Addon:ShowSettingsResetDialog()
before = reopenCount
confirmation.cancel:Fire("OnClick")
local unrelated = Settings.RegisterVerticalLayoutCategory("Controller test category")
SettingsPanel:DisplayCategory(unrelated)
flushTimers()
equal(reopenCount, before, "changing categories before deferred return preserves the new page")
SettingsPanel:Hide()
Settings.OpenToCategory = openCategory
return checks
