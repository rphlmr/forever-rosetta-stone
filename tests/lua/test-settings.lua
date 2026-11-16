local Addon, fixture = ...
local checks = 0
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    checks = checks + 1
end

local panel, category = Addon.settingsPanel, Addon.settingsCategory
local databaseAPI = ForeverRosettaStoneDB
local button = Addon.minimapButton
equal(button:GetParent(), Minimap, "launcher is attached to the native minimap")
Addon:CreateMinimapButton()
equal(Addon.minimapButton, button, "initialization reuses one minimap button")
local oldCenter, oldCursor = Minimap.GetCenter, GetCursorPosition
local oldScale = Minimap:GetScale()
Minimap:SetScale(0.8)
Minimap.GetCenter = function() return 100, 100 end
GetCursorPosition = function() return 200 * Minimap:GetEffectiveScale(), 100 * Minimap:GetEffectiveScale() end
button:Fire("OnDragStart")
equal(button.dragState, "dragging", "drag enters dragging state")
button:Fire("OnUpdate", 0.1)
equal(button.angle, 0, "cursor right of minimap snaps to the east edge")
button:Fire("OnDragStop")
equal(Addon.preferences.minimapAngle, 0, "release saves the angle")
equal(button:GetScript("OnUpdate"), nil, "release stops drag updates")
local categoryBeforeDrag = Settings.openedCategory
button:Fire("OnClick", "LeftButton")
equal(Settings.openedCategory, categoryBeforeDrag, "drag release does not open settings")
Addon:LoadPreferences()
Addon:CreateMinimapButton()
equal(button.angle, 0, "saved position survives preferences loading and initialization")
button:Fire("OnMouseDown", "LeftButton")
equal(button.dragState, "idle", "next press restores normal clicks")
GetCursorPosition = function() return 100 * Minimap:GetEffectiveScale(), 200 * Minimap:GetEffectiveScale() end
button:Fire("OnDragStart")
equal(button.angle, 90, "cursor above minimap reaches the north edge")
button:Hide()
equal(button:GetScript("OnUpdate"), nil, "hiding interrupts drag updates")
equal(Addon.preferences.minimapAngle, 90, "interrupted drag retains its position")
button:Show()
Minimap.GetCenter, GetCursorPosition = oldCenter, oldCursor
Minimap:SetScale(oldScale)
button:Fire("OnClick", "LeftButton")
equal(Settings.openedCategory, category:GetID(), "left-click opens settings")
equal(Addon.minimapMenu, nil, "minimap menu has been removed")
SettingsPanel:Hide()
local nativeWindow = CreateFrame("Frame", nil, UIParent)
local openSettings, settingsOpens = Addon.OpenSettings, 0
local isShiftKeyDown = IsShiftKeyDown
IsShiftKeyDown = function() return false end
button:Fire("OnClick", "RightButton")
equal(SettingsPanel:IsShown(), true, "plain right-click keeps opening settings")
equal(Addon:IsDebugPicking(), false, "plain right-click never starts inspection")
SettingsPanel:Hide()
IsShiftKeyDown = function() return true end
Addon.OpenSettings = function(...) settingsOpens = settingsOpens + 1; return openSettings(...) end
button:Fire("OnClick", "RightButton")
equal(settingsOpens, 0, "right-click inspection bypasses settings and their native panel transitions")
equal(Addon:IsDebugPicking(), true, "right-click starts inspection directly")
equal(nativeWindow:IsShown(), true, "right-click leaves the inspected window open")
equal(SettingsPanel:IsShown(), false, "right-click never opens settings")
button:Fire("OnClick", "RightButton")
equal(Addon:IsDebugPicking(), true, "repeated right-click keeps the current inspection")
Addon:MoveDebugPicker("stop")
Addon:MoveDebugPicker("clear")
Addon.errorDialog.frame:Hide()
Addon.OpenSettings = openSettings
IsShiftKeyDown = isShiftKeyDown
nativeWindow:Hide()
equal(Addon:GetTargetLocale(), "enUS", "translation language defaults to English")
equal(pcall(Addon.SetTargetLocale, Addon, "enGB"), false, "removed English locale is not selectable")
ForeverRosettaStoneSettings.locale = "enGB"
Addon:LoadPreferences()
equal(Addon:GetTargetLocale(), "enUS", "saved British English uses the single English preference")
local settings = Addon.settings
equal(panel.FeatureScroll, nil, "native settings owns scrolling without a nested addon scroll frame")
local preview = panel.TooltipPreview
local setPreviewItem = preview.native.SetItemByID
local requests = 0
preview.native.SetItemByID = function() requests = requests + 1 end
Addon:RefreshTooltipPreview()
equal(requests, 0, "hidden preview does not request tooltip data before canvas layout")
preview.native.SetItemByID = setPreviewItem
equal(settings.tooltipMode:GetValue(), Addon.preferences.tooltipMode, "native display reads saved preference")
settings.tooltipCoverage:SetValue("name")
equal(Addon.preferences.tooltipCoverage, "name", "native dropdown applies coverage")
Addon:LoadPreferences()
equal(Addon.preferences.tooltipCoverage, "name", "coverage survives preferences loading")
equal(pcall(Addon.SetTooltipCoverage, Addon, "unknown"), false, "coverage rejects unknown values")
Addon.preferences.tooltipCoverage = "unknown"
Addon:LoadPreferences()
Addon:RefreshSettingsUI()
equal(settings.tooltipCoverage.displayedValue, "full", "native control refreshes repaired preferences")
for _, position in ipairs({ "left", "right", "bottom", "top" }) do
    settings.npcTooltipPosition:SetValue(position)
    equal(Addon.preferences.npcTooltipPosition, position, "native NPC dropdown applies position")
    Addon:LoadPreferences()
    equal(settings.npcTooltipPosition:GetValue(), position, "position survives preferences loading")
end
Addon.preferences.npcTooltipPosition = "invalid"
Addon:LoadPreferences()
equal(Addon.preferences.npcTooltipPosition, "top", "invalid position recovers to Top")
equal(pcall(Addon.SetNpcTooltipPosition, Addon, "invalid"), false, "position setter rejects unknown values")
local sectionNames = {}
for _, initializer in ipairs(category.initializers) do
    if initializer.kind == "header" then sectionNames[initializer.name] = true end
end
for _, group in ipairs({ "Quests", "Items", "Spells", "Talents", "NPCs", "Locations", "Collections", "Character", "Professions", "Books" }) do
    equal(sectionNames[Addon:SettingsGroupName(group)], true, "feature group has a section heading: " .. group)
end
equal(Addon.settingsGroups, nil, "feature groups do not create subcategories")
for _, feature in ipairs(Addon.features) do
    equal(settings[feature.id].category, category, "every feature lives on the main page")
    settings[feature.id]:SetValue(false)
    equal(Addon:IsFeatureEnabled(feature.id), false, "native checkbox disables only its feature")
    settings[feature.id]:SetValueToDefault()
    equal(Addon:IsFeatureEnabled(feature.id), true, "native Defaults restores feature")
end
ForeverRosettaStoneSettings.tooltipMode = "inline"
Addon:LoadPreferences()
equal(Addon.preferences.tooltipMode, "stacked", "saved Inline migrates to Stacked")
equal(pcall(Addon.SetTooltipMode, Addon, "inline"), false, "removed Inline mode cannot be selected")
settings.tooltipMode:SetValue("separate")
equal(Addon.preferences.tooltipMode, "separate", "native dropdown applies display mode")
equal(pcall(Addon.SetTooltipMode, Addon, "unknown"), false, "display rejects unknown values")
Addon:OpenSettings()
local languageList, positionList = Addon.radioLists.locale, Addon.radioLists.npcTooltipPosition
equal(languageList:IsVisible(), true, "language choices are listed inline on the main page")
local available = {}
for _, button in ipairs(languageList.buttons) do
    button:Fire("OnClick")
    available[button.value] = true
    equal(Addon:GetTargetLocale(), button.value, "language radio applies its language: " .. button.value)
    equal(button.text:GetText(), ForeverRosettaStoneDB:GetLocales()[button.value], "language radio shows its name")
    equal(button.selected, true, "chosen language radio is selected")
    local selectedCount = 0
    for _, other in ipairs(languageList.buttons) do
        if other.selected then selectedCount = selectedCount + 1 end
    end
    equal(selectedCount, 1, "exactly one language radio is selected")
end
equal(languageList.buttons[1].OnSmartNavClick ~= nil, true, "language radios accept controller selection")
do
    local getWidth = languageList.GetWidth
    local resolvedWidth = 0
    languageList.GetWidth = function() return resolvedWidth end
    -- Native size callbacks can precede the anchor-derived GetWidth update.
    languageList:Fire("OnSizeChanged", 635, 206)
    equal(languageList.buttons[1]:GetWidth(), 188.75, "size callback uses its resolved width instead of stale GetWidth")
    local host = languageList:GetParent()
    Addon:AttachRadioList(host, "locale")
    equal(languageList.buttons[1]:GetWidth(), 188.75, "an unresolved zero width does not replace the last valid grid")
    resolvedWidth = 635
    fixture.flushTimers()
    local _, _, _, x = languageList.buttons[1]:GetPoint(1)
    equal(x, 237.5, "deferred layout places the first radio inside the resolved host")
    equal(languageList.buttons[1]:GetWidth(), 188.75, "deferred layout uses the full settings row width")
    languageList.GetWidth = getWidth
    Addon:LayoutRadioList(languageList)
end
do
    -- Lists are created under UIParent; once attached they must draw above the HIGH, toplevel settings panel.
    local host = languageList:GetParent()
    host:SetFrameStrata("HIGH")
    host:SetFrameLevel(700)
    host:Hide()
    host:Show()
    equal(languageList:GetFrameStrata(), "HIGH", "language list draws in its settings row strata")
    equal(languageList:GetFrameLevel() > host:GetFrameLevel(), true, "language list draws above its settings row")
end
do
    -- Choices start in the native control column (CENTER - 80) so D-pad down reaches the checkboxes below.
    local controlColumn = languageList:GetWidth() / 2 - 80
    for index, button in ipairs(languageList.buttons) do
        local _, _, _, x = button:GetPoint(1)
        equal(index % 2 == 1 and x == controlColumn or x > controlColumn, true,
            "language radio sits in the native control column: " .. button.value)
    end
    local _, _, _, positionX = positionList.buttons[1]:GetPoint(1)
    equal(positionX, positionList:GetWidth() / 2 - 80, "position radios share the native control column")
    -- Native rows are navigated from their LEFT edge; first-column choices share that anchor.
    for index, button in ipairs(languageList.buttons) do
        if index % 2 == 1 then
            equal(button.cursorAnchor and button.cursorAnchor.relativePoint, "LEFT",
                "first-column language uses the native row anchor: " .. button.value)
            local _, relativeTo, _, x = button.cursorAnchor.relativeTo:GetPoint(1)
            equal(relativeTo == languageList and x == 0, true, "native row anchor starts at the row edge")
        else
            equal(button.cursorAnchor, nil, "later columns keep their own position: " .. button.value)
        end
    end
    local navigation = SmartNavigation.GetButtonInfoInDirection
    local searchedFrom
    SmartNavigation.GetButtonInfoInDirection = function(_, from)
        searchedFrom = from
        return { button = "native-row" }
    end
    local count = #languageList.buttons
    local lastRight = count % 2 == 0 and count or count - 1
    equal(languageList.buttons[lastRight].navigationOverrides.down(), "native-row",
        "last right-column choice leaves the grid downward")
    equal(searchedFrom, languageList.buttons[lastRight - 1], "downward exit searches from its row's native anchor")
    local rightTop = languageList.buttons[2]
    equal(rightTop.navigationOverrides.down(), nil, "right column keeps moving down within the grid")
    equal(rightTop.navigationOverrides.up(), "native-row", "top right choice leaves the grid upward from its row")
    equal(searchedFrom, languageList.buttons[1], "upward exit searches from the native row anchor")
    equal(positionList.buttons[3].navigationOverrides.down(), "native-row", "position choices leave downward like native rows")
    equal(searchedFrom, positionList.buttons[1], "downward exit searches from the first position choice")
    SmartNavigation.GetButtonInfoInDirection = function() return nil end
    equal(positionList.buttons[3].navigationOverrides.down(), true, "no row below keeps focus in place")
    SmartNavigation.GetButtonInfoInDirection = navigation
    local rows = math.ceil(#languageList.buttons / 2)
    equal(4 + rows * 22 + 4 <= 206, true, "language template height fits every language row")
end
for locale in pairs(ForeverRosettaStoneDB:GetLocales()) do
    equal(available[locale] ~= nil, locale ~= "enGB" and locale:sub(1, 2) ~= GetLocale():sub(1, 2),
        "native language page exposes supported translations: " .. locale)
end
local displayControl, coverageControl
for _, initializer in ipairs(category.initializers) do
    if initializer.setting == settings.tooltipModeEnabled then displayControl = initializer end
    if initializer.setting == settings.tooltipCoverageEnabled then coverageControl = initializer end
end
equal(displayControl.kind, "checkbox", "two-value display choice uses a native checkbox")
equal(coverageControl.kind, "checkbox", "two-value coverage choice uses a native checkbox")
local savedPosition = Addon.preferences.npcTooltipPosition
settings.tooltipModeEnabled:SetValue(false)
equal(Addon.preferences.tooltipMode, "stacked", "unchecked separate tooltip selects stacked")
equal(positionList.buttons[4]:IsEnabled(), false, "stacked disables the NPC position radios")
positionList.buttons[4]:Fire("OnClick")
equal(Addon.preferences.npcTooltipPosition, savedPosition, "disabled position radios keep the chosen position")
settings.tooltipModeEnabled:SetValue(true)
equal(Addon.preferences.tooltipMode, "separate", "checked separate tooltip selects separate")
equal(positionList.buttons[4]:IsEnabled(), true, "separate enables the NPC position radios")
settings.tooltipCoverageEnabled:SetValue(false)
equal(Addon.preferences.tooltipCoverage, "name", "unchecked full text selects name only")
settings.tooltipCoverageEnabled:SetValueToDefault()
equal(Addon.preferences.tooltipCoverage, "full", "coverage checkbox defaults to full text")
settings.tooltipCoverageEnabled:SetValue(false)
positionList.buttons[4]:Fire("OnClick")
equal(Addon.preferences.npcTooltipPosition, "bottom", "position radio selects bottom")
equal(positionList.buttons[4].text:GetText(), Addon:SettingsText("bottom"), "position labels follow the client language")
for _, nativeCategory in ipairs(Settings.allCategories) do
    if nativeCategory:GetID():find(category:GetID(), 1, true) == 1 then
        for _, initializer in ipairs(nativeCategory.initializers) do
            equal(initializer.kind == "dropdown", false, "addon choices avoid the unsafe native popup transition")
        end
    end
end
settings.locale:SetValue("deDE")
equal(Addon:GetTargetLocale(), "deDE", "native language dropdown applies immediately")
equal(ForeverRosettaStoneDB, databaseAPI, "language change preserves database API")
equal(ForeverRosettaStoneSettings.locale, "deDE", "language saves in preferences")
settings.locale:SetValue("frFR")
equal(Addon.page.body.sections[1]:GetText():find("Débuts modestes", 1, true) ~= nil, true,
    "language dropdown updates current translated quest")
settings.locale:SetValue("enUS")
equal(Addon.page.body.sections[1]:GetText():find("Humble Beginnings", 1, true) ~= nil, true,
    "switching back restores English")
Addon:OpenSettings()
equal(panel:IsVisible(), true, "default page displays the live preview")
do
    local preview = panel.TooltipPreview
    local function Rendered()
        return (Addon.stackedTooltips and Addon.stackedTooltips[preview.native] ~= nil) or preview.translated:IsShown()
    end
    local itemAPI, itemMixin = C_Item, Item
    local cached, loads, onLoad = false, 0, nil
    C_Item = { IsItemDataCachedByID = function() return cached end }
    Item = { CreateFromItemID = function()
        return { ContinueOnItemLoad = function(_, callback) loads = loads + 1; onLoad = callback end }
    end }
    Addon:ClearStackedTooltip(preview.native)
    preview.translated:Hide()
    Addon:RefreshTooltipPreview()
    Addon:RefreshTooltipPreview()
    equal(preview.native:IsShown(), false, "uncached preview item never shows the loading placeholder")
    equal(loads, 1, "preview requests the uncached item once")
    cached = true
    onLoad()
    equal(Rendered(), true, "preview renders once item data arrives")
    C_Item, Item = itemAPI, itemMixin
    SettingsPanel:Hide()
    equal(preview.native:IsVisible() or preview.translated:IsVisible(), false, "closing settings hides preview tooltips")
    Addon:OpenSettings()
    equal(Rendered(), true, "reopening settings renders the preview again")
end
equal(panel:GetParent().smartNavigationCanFocus, true, "preview row participates in native controller scrolling")
equal(panel:GetParent().cursorAnchor.relativePoint, "LEFT", "preview focus aligns with native settings rows")
equal(SmartNavigation.scrollFrames[SettingsPanel], SettingsPanel:GetSettingsList().ScrollBox,
    "settings registers its list for native right-stick scrolling")
equal(panel.smartNavigationIgnored, true, "preview tooltips do not steal focus from their native scroll row")
local debugIndex, previewIndex, questsIndex
for index, initializer in ipairs(category.initializers) do
    if initializer.kind == "button" and initializer.name == Addon:DebugText("title") then debugIndex = index end
    if initializer.kind == "panel" then previewIndex = index end
    if initializer.kind == "header" and initializer.name == Addon:SettingsGroupName("Quests") then questsIndex = index end
end
equal(previewIndex + 1, questsIndex, "preview sits immediately before the Quests section")
equal(questsIndex < debugIndex, true, "debug console follows the feature sections")
local runDebugCommand = Addon.RunDebugCommand
local openedDebug
Addon.RunDebugCommand = function(_, command) openedDebug = command end
Settings.FindButton(category, Addon:DebugText("title")).callback()
equal(openedDebug, "", "settings button opens the debug console")
equal(SettingsPanel:IsShown(), false, "opening debug closes settings")
Addon.RunDebugCommand = runDebugCommand
Addon:OpenSettings()
equal(Addon.settingsPreviewCategory, nil, "preview has no separate menu")
for _, id in ipairs({ "locale", "tooltipModeEnabled", "tooltipCoverageEnabled", "npcTooltipPosition" }) do
    equal(settings[id].category, category, "tooltip control stays beside the preview: " .. id)
end
SettingsPanel:Hide()
equal(panel:IsVisible(), false, "closing settings hides the main page preview")
Addon:OpenSettings()
equal(panel:IsVisible(), true, "returning to default page restores the preview")
settings.questTooltip:SetValue(false)
local generation = Addon.generation
SettingsPanel:Hide()
SlashCmdList.FOREVERROSETTASTONE("reset")
equal(Addon.generation, generation + 1, "reset creates a fresh addon generation")
equal(Addon:IsFeatureEnabled("questTooltip"), false, "reset preserves opt-outs")
equal(Addon.settingsCategory, category, "reset reuses registered native categories")
equal(Addon.settings, settings, "native callbacks survive reset")
settings.questTooltip:SetValue(true)
equal(Addon:IsFeatureEnabled("questTooltip"), true, "persistent native control uses current runtime")
local defaults = SettingsPanel:GetSettingsList().Header.DefaultsButton
local nativeDefaults = defaults:GetScript("OnClick")
local gamepadUI = InputUtil.IsGamepadUIEnabled
InputUtil.IsGamepadUIEnabled = function() return false end
Addon:OpenSettings()
settings.questPanel:SetValue(false)
defaults:Fire("OnClick")
local confirmation = Addon.settingsResetDialog
equal(confirmation.frame:IsShown(), true, "header opens addon-only confirmation")
equal(Addon:IsFeatureEnabled("questPanel"), false, "opening confirmation does not reset preferences")
equal(confirmation.accept:GetText(), Addon:SettingsText("resetAccept"), "confirmation identifies addon-only scope")
equal(confirmation.window:SmartNavigationCloseHandler(), true, "B closes only the confirmation")
equal(confirmation.frame:IsShown(), false, "B cancels without resetting")
Addon:OpenSettings()
defaults:Fire("OnClick")
equal(confirmation.frame:IsShown(), true, "single page keeps addon-only confirmation after reopening")
confirmation.cancel:Fire("OnClick")
local unrelated = Settings.RegisterVerticalLayoutCategory("Unrelated addon")
Settings.OpenToCategory(unrelated:GetID())
equal(defaults:GetScript("OnClick"), nativeDefaults, "other categories retain the original Defaults action")
equal(SmartNavigation.scrollFrames[SettingsPanel], nil, "leaving addon categories releases their stick scroll target")
defaults:Fire("OnClick")
equal(StaticPopupDialogs.shown, "GAME_SETTINGS_APPLY_DEFAULTS", "other categories retain native confirmation")
Addon:OpenSettings()
SettingsPanel:Hide()
equal(defaults:GetScript("OnClick"), nativeDefaults, "closing Settings restores the original header action")
equal(SmartNavigation.scrollFrames[SettingsPanel], nil, "closing Settings releases its stick scroll target")
Addon:OpenSettings()
defaults:Fire("OnClick")
equal(confirmation.frame:IsShown(), true, "reopening Rosetta restores scoped reset")
equal(StaticPopupDialogs.shown, "GAME_SETTINGS_APPLY_DEFAULTS", "addon confirmation does not enter native static popup handling")
local previousCaptures, previousLog = Addon.debugPicker.entries, Addon.errorLog
local previousAngle = Addon.preferences.minimapAngle
local resetCalls = 0
local globalReset = SettingsPanel.SetAllSettingsToDefaults
SettingsPanel.SetAllSettingsToDefaults = function() resetCalls = resetCalls + 1 end
confirmation.accept:Fire("OnClick")
SettingsPanel.SetAllSettingsToDefaults = globalReset
equal(resetCalls, 0, "addon-only reset never calls WoW's global reset")
equal(Addon.debugPicker.entries, previousCaptures, "addon-only reset preserves captures")
equal(Addon.errorLog, previousLog, "addon-only reset preserves saved error history")
equal(Addon.preferences.minimapAngle, previousAngle, "addon-only reset preserves minimap position")
equal(Addon:GetTargetLocale(), "enUS", "reset all restores English")
equal(Addon.preferences.tooltipMode, "stacked", "reset all restores Stacked")
equal(Addon.preferences.tooltipCoverage, "full", "reset all restores Full text")
equal(Addon.preferences.npcTooltipPosition, "top", "reset all restores Top")
equal(#Settings.categories, 1, "only one native root category is registered")
Addon:SetTooltipMode("separate")
InputUtil.IsGamepadUIEnabled = gamepadUI

fixture.setMouseFoci({})
SmartNavigation:HideCursor()
local row = CreateFrame("Button", nil, QuestScrollFrame)
row.questID = 399
GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
GameTooltip:Show()
Addon:ShowTranslationTooltip()
equal(Addon.tooltip:IsShown(), true, "enabled quest-list companion appears")
Addon:OpenSettings()
equal(Addon.tooltip:IsShown(), true, "opening settings preserves map/quest hover companions")
Addon.input:Fire("OnUpdate", 0.2)
equal(Addon.tooltip:IsShown(), true, "map hover remains translated with settings open")
equal(Addon.mapContextLabel:IsShown(), false, "map context label stays behind the settings screen")
SettingsPanel:Hide()
Addon:ShowTranslationTooltip()
Addon:SetFeatureEnabled("questTooltip", false)
equal(Addon.tooltip:IsShown(), false, "list opt-out clears visible tooltip immediately")
GameTooltip:SetOwner(fixture.questPin, "ANCHOR_RIGHT")
Addon:ShowTranslationTooltip()
equal(Addon.tooltip:IsShown(), true, "list opt-out leaves map quests enabled")
Addon:SetFeatureEnabled("mapQuestTooltip", false)
equal(Addon.tooltip:IsShown(), false, "map quest opt-out clears companion immediately")
Addon:SetFeatureEnabled("questTooltip", true)
GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
Addon:ShowTranslationTooltip()
equal(Addon.tooltip:IsShown(), true, "map quest opt-out leaves quest-list companion enabled")
GameTooltip:Hide()

local info = C_QuestLog.GetInfo(fixture.locationHeader.questLogIndex)
info.title, info.isHeader = "Hurlevent", true
fixture.setMouseFoci({fixture.locationHeader})
Addon:ShowTranslationTooltip()
equal(Addon.locationTooltip:IsShown(), false, "title-only location headers stay native")
SettingsPanel:Show()
Addon:ShowLocationTooltip()
equal(Addon.locationTooltip:IsShown(), false, "settings do not identify title-only location headers")
SettingsPanel:Hide()
Addon:SetFeatureEnabled("locationTooltip", false)
equal(Addon.locationTooltip:IsShown(), false, "header opt-out clears location tooltip")
fixture.setMouseFoci({})
fixture.nativeAreaLabel.Name:SetText("Comté-de-l'Or")
Addon:ShowMapLocationLabel()
equal(Addon.mapLocationLabel:IsShown(), false, "title-only map hover stays native")
Addon:SetFeatureEnabled("mapLocationLabel", false)
equal(Addon.mapLocationLabel:IsShown(), false, "map hover-name opt-out clears subtitle")
equal(fixture.nativeAreaLabel.Name:GetText(), "Comté-de-l'Or", "opt-out leaves native map name intact")
Addon:SetFeatureEnabled("mapContext", false)
equal(Addon.mapContextLabel:IsShown(), false, "map context opt-out clears breadcrumb")
equal(Addon.playerLocationLabel:IsShown(), true, "breadcrumb opt-out leaves player suffix enabled")
Addon:SetFeatureEnabled("playerLocation", false)
equal(Addon.playerLocationLabel:IsShown(), false, "player-location opt-out clears suffix")
Addon:SetFeatureEnabled("mapContext", true)
equal(Addon.mapContextLabel:IsShown(), true, "player-location opt-out leaves breadcrumb enabled")
local menu = fixture.createMapMenu(fixture.mapMenuArrow, {"Hurlevent"})
menu.elements[1]:Enter(fixture.menuRow)
equal(Addon.mapMenuTooltip:IsShown(), false, "title-only dropdown rows stay native")
Addon:SetFeatureEnabled("mapDropdown", false)
equal(Addon.mapMenuTooltip:IsShown(), false, "dropdown opt-out clears current translation")
menu.elements[1]:Enter(fixture.menuRow)
equal(Addon.mapMenuTooltip:IsShown(), false, "existing menu callbacks honor disabled preference")
Addon:SetFeatureEnabled("mapDropdown", true)
menu.elements[1]:Enter(fixture.menuRow)
equal(Addon.mapMenuTooltip:IsShown(), false, "re-enabling does not identify a title-only dropdown row")
Addon:SetTargetLocale("frFR")
menu.elements[1]:Enter(fixture.menuRow)
equal(Addon.mapMenuTooltip:IsShown(), false, "changing target language does not identify a title-only row")
Addon:SetTargetLocale("enUS")
menu:Release()

fixture.press("PADRTRIGGER")
equal(Addon.current.mode, "reading", "panel opt-out test starts with English focused")
Addon:SetFeatureEnabled("questPanel", false)
equal(Addon.current.mode, "unavailable", "panel opt-out passes through unavailable state")
equal(Addon.panel:IsShown(), false, "panel opt-out hides the English window")
equal(Addon.toggle:IsShown(), false, "panel opt-out removes its bookmark")
equal(Addon.registeredPanel, nil, "panel opt-out releases native controller registration")
equal(Addon:Transition({mode = "reading", questID = 399}, "quest.select", 399).mode, "unavailable",
    "state machine refuses quest selection while panel is disabled")
SlashCmdList.FOREVERROSETTASTONE("quest")
equal(Addon.panel:IsShown(), false, "reading command cannot reopen an opted-out panel")
Addon:SetFeatureEnabled("questPanel", true)
equal(Addon.panel:IsShown(), true, "panel re-enables without reload")
equal(GamepadMode.FrameControlsManager:GetActiveFrame(), WorldMapFrame, "re-enabling panel does not steal focus")
fixture.press("PADRTRIGGER")
local registered = Addon.registeredPanel
fixture.setCombat(true)
Addon:SetFeatureEnabled("questPanel", false)
equal(Addon.panel:IsShown(), false, "combat opt-out immediately hides English UI")
equal(Addon.registeredPanel, registered, "protected native teardown waits for combat end")
fixture.setCombat(false)
Addon:RefreshSelection()
equal(Addon.registeredPanel, nil, "combat end releases disabled panel registration")
Addon:SetFeatureEnabled("questPanel", true)
local oldRewards, oldQuest = MapQuestInfoRewardsFrame.activeRewardElements, QuestMapFrame.DetailsFrame.questID
MapQuestInfoRewardsFrame.activeRewardElements = fixture.nativeChoices
QuestMapFrame.DetailsFrame.questID = 943
Addon:RefreshSelection()
fixture.press("PADRTRIGGER")
local reward = Addon.page.rewardButtons[2]
reward.left, reward.top = 1000, 700
SmartNavigation:SelectButton(reward)
Addon:UpdateRewardTooltips()
equal(Addon.rewardTooltips[1]:IsShown(), true, "reward opt-out starts with an actual focused comparison")
Addon:SetFeatureEnabled("rewardComparison", false)
equal(Addon.rewardTooltips[1]:IsShown(), false, "reward comparison opt-out clears reward tooltip")
equal(Addon.rewardTooltips[2]:IsShown(), false, "reward comparison opt-out clears equipment tooltip")
equal(reward.mouseEnabled, false, "opted-out reward comparisons remove interactive reward targets")
equal(SmartNavigation:GetCurrentButton() == reward, false, "reward opt-out clears obsolete controller selection")
Addon:UpdateRewardTooltips(reward)
equal(Addon.rewardTooltips[1]:IsShown(), false, "disabled comparison cannot reopen through an old hover callback")
fixture.press("PADLTRIGGER")
MapQuestInfoRewardsFrame.activeRewardElements, QuestMapFrame.DetailsFrame.questID = oldRewards, oldQuest
Addon:RefreshSelection()

ForeverRosettaStoneSettings.features.questTooltip = "invalid"
ForeverRosettaStoneSettings.features.mapContext = false
Addon:LoadPreferences()
equal(Addon:IsFeatureEnabled("questTooltip"), true, "invalid saved boolean returns to default")
equal(Addon:IsFeatureEnabled("mapContext"), false, "saved opt-out survives repairing another setting")
local oldSettings = ForeverRosettaStoneSettings
ForeverRosettaStoneSettings = { features = 42 }
Addon:LoadPreferences()
equal(Addon:IsFeatureEnabled("questPanel"), true, "invalid saved feature container is repaired")
ForeverRosettaStoneSettings = "invalid"
Addon:LoadPreferences()
equal(Addon:IsFeatureEnabled("questPanel"), true, "invalid saved root is repaired")
ForeverRosettaStoneSettings = oldSettings
Addon:LoadPreferences()
Addon:ResetFeatureSettings()
for _, feature in ipairs(Addon.features) do
    equal(Addon:IsFeatureEnabled(feature.id), true, feature.id .. " restores to default")
end
equal(#Settings.categories, 1, "all preference changes leave a single settings category")
equal(Addon.lifecycle, "ready", "settings transitions do not suspend addon")
local previousLocale = Addon:GetTargetLocale()
local loadLocale = ForeverRosettaStoneDB.LoadLocale
ForeverRosettaStoneDB.LoadLocale = function() error("injected missing language pack") end
local switched = pcall(Addon.SetTargetLocale, Addon, "deDE")
ForeverRosettaStoneDB.LoadLocale = loadLocale
equal(switched, false, "missing language pack reports the load failure")
equal(Addon:GetTargetLocale(), previousLocale, "failed language change preserves the previous selection")
fixture.nativeAreaLabel.Name:SetText("")
Addon:RefreshFeatures()

for locale, localized in pairs(Addon.settingsTranslations) do
    for key in pairs(Addon.settingsTranslations.enUS.text) do
        equal(type(localized.text[key]), "string", "settings text is complete: " .. locale .. " " .. key)
    end
    for group in pairs(Addon.settingsTranslations.enUS.groups) do
        equal(type(localized.groups[group]), "string", "settings group is translated: " .. locale .. " " .. group)
    end
    if locale:sub(1, 2) ~= "en" then
        for _, feature in ipairs(Addon.features) do
            local text = localized.features[feature.id]
            equal(text ~= nil and type(text[1]) == "string" and type(text[2]) == "string", true,
                "feature text is translated: " .. locale .. " " .. feature.id)
        end
    end
end

return checks
