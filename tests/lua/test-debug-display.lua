local Addon = ...
local checks = 0
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    checks = checks + 1
end

local originalPinnedHyperlink, originalSetHyperlink = ItemRefTooltip.SetHyperlink, GameTooltip.SetHyperlink
local originalSetUnit, originalUnitExists = GameTooltip.SetUnit, UnitExists
local originalUnitLevel = UnitLevel
local originalCompare, originalHideShopping = GameTooltip_ShowCompareItem, GameTooltip_HideShoppingTooltips
local compared
GameTooltip_ShowCompareItem = function(source) compared = source end
GameTooltip_HideShoppingTooltips = function(source)
    local tooltips = source == GameTooltip and { ShoppingTooltip1, ShoppingTooltip2 }
        or { ItemRefShoppingTooltip1, ItemRefShoppingTooltip2 }
    for _, tip in ipairs(tooltips) do tip:Hide() end
end
UnitLevel = function() return 60 end
local opened, pinned, unit
ItemRefTooltip.SetHyperlink = function(_, link) pinned = link end
GameTooltip.SetHyperlink = function(_, link) opened = link end
GameTooltip.SetUnit = function(_, value) unit = value end
UnitExists = function() return true end
Addon:RunDebugCommand("display")
local dialog = Addon.errorDialog
equal(dialog.display:IsShown(), true, "display command opens native preview controls")
equal(dialog.home:IsShown(), false, "display replaces home actions")
equal(dialog.scroll:IsShown(), false, "display hides the report field")
equal(dialog.displayToggle.template, "LargeSideTabButtonTemplate", "UI components uses native right-side icon tabs")
equal(dialog.displayToggle:GetChecked(), true, "UI components tab is selected")
equal(dialog.consoleTab:GetChecked(), false, "console tab is not selected during component display")
equal(dialog.list:IsShown(), false, "component tab hides the capture list")
equal(dialog.commandBox:IsShown(), false, "component tab hides the console command field")
local nativeOwner, nativeShown = GameTooltip:GetOwner(), GameTooltip:IsShown()
dialog.consoleTab:Fire("OnEnter")
local widgetTip = Addon:GetWidgetTooltip()
equal(widgetTip:IsOwned(dialog.consoleTab), true, "debug tab owns the addon widget tooltip")
equal(widgetTip:IsShown(), true, "debug tab hint is visible")
equal(GameTooltip:GetOwner(), nativeOwner, "debug tab does not replace the native tooltip owner")
equal(GameTooltip:IsShown(), nativeShown, "debug tab preserves native visibility")
dialog.consoleTab:Fire("OnLeave")
equal(widgetTip:IsShown(), false, "leaving the tab hides its widget tooltip")
dialog.capturesTab:Fire("OnEnter")
dialog.consoleTab:Fire("OnLeave")
equal(widgetTip:IsShown(), true, "leaving an old tab preserves the new owner's hint")
dialog.capturesTab:Fire("OnLeave")
local savedMode = Addon.preferences.tooltipMode
dialog.displaySeparate:Fire("OnClick")
dialog.displayInput:SetText("")
dialog.displayShow:Fire("OnClick")
equal(opened, "item:117", "empty ID displays the selected component default")
equal(Addon:GetTooltipDisplayMode(GameTooltip), "separate", "preview offers original and translated tooltips side by side")
equal(Addon:GetTooltipDisplayMode(ItemRefTooltip), savedMode, "preview layout does not affect unrelated tooltips")
equal(Addon.preferences.tooltipMode, savedMode, "preview layout leaves saved settings unchanged")
equal(Addon:GetTooltipComponent("quest").ResolveData(GameTooltip,
    { type = Enum.TooltipDataType.Quest, id = 783 }), 783,
    "debug quest hover can resolve a translation outside the pinned tooltip")
equal(dialog.previewReturnPanel:IsShown(), true, "preview keeps a visible return control")
equal(Addon:MoveDebugPreview("start"), false, "repeated preview start is refused")
opened=nil
dialog.previewReturnPanel:Fire("OnEvent","MODIFIER_STATE_CHANGED","LSHIFT",1)
equal(opened,"item:117","modifier changes refresh the active native hyperlink preview")
local savedCombat=InCombatLockdown
InCombatLockdown=function() return true end
opened=nil
dialog.previewReturnPanel:Fire("OnEvent","MODIFIER_STATE_CHANGED","LSHIFT",0)
equal(opened,nil,"modifier refreshes do not rebuild tooltips during combat")
InCombatLockdown=savedCombat
local escapeRegistered = false
for _, name in ipairs(UISpecialFrames) do
    if name == dialog.previewReturnPanel:GetName() then escapeRegistered = true end
end
equal(escapeRegistered, true, "Escape closes the preview return panel")
dialog.previewReturnPanel:Hide()
equal(GameTooltip:IsShown(), false, "Escape closes the rendered tooltip")
equal(dialog.frame:IsShown(), true, "Escape restores the existing debug window")
equal(dialog.display:IsShown(), true, "Escape restores the component tab")
equal(dialog.displayInput:GetText(), "", "return preserves the ID field")
equal(Addon:MoveDebugPreview("return"), false, "repeated return cannot reopen the console")
opened=nil
dialog.previewReturnPanel:Fire("OnEvent","MODIFIER_STATE_CHANGED","LSHIFT",1)
equal(opened,nil,"closed previews do not refresh on modifiers")
equal(Addon:GetTooltipDisplayMode(GameTooltip), savedMode, "return removes the temporary source layout")
equal(Addon:GetTooltipComponent("quest").ResolveData(GameTooltip,
    { type = Enum.TooltipDataType.Quest, id = 783 }), nil,
    "quest hover translation remains scoped to the active debug preview")
dialog.displayKinds.comparison:Fire("OnClick")
dialog.displayPin:Fire("OnClick")
equal(pinned, "item:19019", "equipped comparison has a default native item sample")
equal(compared, ItemRefTooltip, "pinned comparison invokes the native equipment comparison renderer")
equal(Addon:GetTooltipDisplayMode(ItemRefShoppingTooltip1), "separate", "equipped comparison inherits side-by-side translation mode")
ItemRefShoppingTooltip1:Show()
ItemRefShoppingTooltip2:Show()
dialog.previewReturnPanel:Hide()
equal(ItemRefShoppingTooltip1:IsShown(), false, "return closes the first native comparison")
equal(ItemRefShoppingTooltip2:IsShown(), false, "return closes the second native comparison")
dialog.displayStacked:Fire("OnClick")
dialog.displayShow:Fire("OnClick")
equal(Addon:GetTooltipDisplayMode(GameTooltip), "stacked", "stacked previews remain selectable")
equal(compared, GameTooltip, "hover comparison also uses the native renderer")
dialog.previewReturnPanel:Hide()
Addon:RunDebugCommand("display")
dialog.displayKinds.quest:Fire("OnClick")
dialog.displayInput:SetText("   ")
dialog.displayPin:Fire("OnClick")
equal(pinned:match("^quest:783:"), "quest:783:", "quest pins use a native quest link")
equal(ItemRefTooltip:IsShown(), true, "quest pin explicitly shows the native tooltip")
equal(ItemRefTooltip:GetOwner(), UIParent, "pinned tooltip is independent of the hidden console")
equal(dialog.frame:IsShown(), false, "pin closes the console overlay")
dialog.previewReturn:Fire("OnClick")
equal(ItemRefTooltip:IsShown(), false, "return button closes pinned quests")
equal(dialog.displayKind, "quest", "return preserves the selected component")
equal(dialog.displayInput:GetText(), "   ", "return preserves a custom input")
local previousGamepad = InputUtil.IsGamepadUIEnabled
InputUtil.IsGamepadUIEnabled = function() return true end
Addon:SyncDebugController()
dialog.displayPin:OnSmartNavClick()
equal(SmartNavigation:GetActiveFrame(), dialog.previewReturnPanel, "gamepad focuses the preview return control")
equal(SmartNavigation:GetCurrentButton(), nil, "preview opens without preselecting Return")
equal(dialog.previewFooter.frame:IsShown(), true, "preview displays Select and Back prompts")
equal(dialog.previewReturnPanel:SmartNavigationCloseHandler(), true, "gamepad Back handles the preview")
equal(ItemRefTooltip:IsShown(), false, "gamepad Back closes the pinned tooltip")
equal(dialog.display:IsShown(), true, "gamepad Back restores the component tab")
equal(SmartNavigation:GetCurrentButton(), nil, "returning to debug does not preselect a component")
equal(dialog.previewFooter.frame:IsShown(), false, "return hides preview prompts")
dialog.displayShow:OnSmartNavClick()
dialog.previewReturn:OnSmartNavClick()
equal(dialog.frame:IsShown(), true, "gamepad Select also returns to debug tools")
InputUtil.IsGamepadUIEnabled = previousGamepad
Addon:SyncDebugController()
Addon:RunDebugCommand("display recipe 7418")
equal(opened, "enchant:7418", "recipe uses a crafting hyperlink rather than an item ID")
Addon:RunDebugCommand("pin quest 783")
equal(pinned:match("^quest:783:"), "quest:783:", "quest pin command is available")
Addon:RunDebugCommand("/frs PIN ITEM |cffffffff|Hitem:25:0:0|h[Test Item]|h|r")
equal(pinned, "item:25:0:0", "slash commands preserve full hyperlink syntax")
Addon:RunDebugCommand("display")
equal(dialog.previewReturnPanel:IsShown(), false, "opening tools dismisses the preview return panel")
equal(Addon:MoveDebugPreview("return"), false, "dismissed preview cannot restore an obsolete view")
dialog.displayKinds.item:Fire("OnClick")
dialog.displayInput:SetText("|cffffffff|Hitem:25:0:0:0:0:0:0:0|h[Test]|h|r")
dialog.displayShow:Fire("OnClick")
equal(opened, "item:25:0:0:0:0:0:0:0", "item preview preserves link parameters")
Addon:RunDebugCommand("display")
dialog.displayKinds.quest:Fire("OnClick")
dialog.displayInput:SetText("item:25")
opened = nil
dialog.displayShow:Fire("OnClick")
equal(opened, nil, "wrong link type cannot display a different entity")
equal(dialog.frame:IsShown(), true, "invalid input keeps controls open")
equal(dialog.displayStatus:GetText(), Addon:DebugText("displayInvalid"), "invalid input has visible feedback")
dialog.displayTarget:Fire("OnClick")
equal(unit, "target", "target preview uses the live unit")
Addon:RunDebugCommand("display")
UnitExists = function() return false end
unit = nil
dialog.displayTarget:Fire("OnClick")
equal(unit, nil, "missing target does not show stale unit data")
equal(dialog.frame:IsShown(), true, "missing target leaves controls available")
local originalCombat = InCombatLockdown
InCombatLockdown = function() return true end
opened = nil
dialog.displayShow:Fire("OnClick")
equal(opened, nil, "combat refuses tooltip previews")
equal(dialog.displayStatus:GetText(), Addon:DebugText("displayCombat"), "combat refusal is visible")
InCombatLockdown = originalCombat
local oldLifecycle = Addon.lifecycle
Addon.lifecycle = "suspended"
dialog.displayPin:Fire("OnClick")
equal(dialog.displayStatus:GetText(), Addon:DebugText("displayPaused"), "paused addon refuses previews but keeps diagnostics usable")
Addon.lifecycle = oldLifecycle
dialog.consoleTab:Fire("OnClick")
equal(dialog.home:IsShown(), true, "Console tab restores the console start screen")
dialog.addonReport:Fire("OnClick")
equal(dialog.display:IsShown(), false, "report navigation leaves display view")
equal(dialog.scroll:IsShown(), true, "report text is restored")
equal(dialog.capturesTab:GetChecked(), true, "report selects the captures tab")
Addon:RunDebugCommand("display")
dialog.consoleTab:Fire("OnClick")
dialog.pick:Fire("OnClick")
equal(dialog.display:IsShown(), false, "picking leaves display view")
Addon:MoveDebugPicker("stop")
Addon:RunDebugCommand("help")
equal(dialog.report:find("/frs pin quest 783", 1, true) ~= nil, true, "help documents quest pinning")
ItemRefTooltip.SetHyperlink, GameTooltip.SetHyperlink = originalPinnedHyperlink, originalSetHyperlink
GameTooltip.SetUnit, UnitExists = originalSetUnit, originalUnitExists
UnitLevel = originalUnitLevel
GameTooltip_ShowCompareItem, GameTooltip_HideShoppingTooltips = originalCompare, originalHideShopping
dialog.frame:Hide()
ItemRefTooltip:Hide()
return checks
