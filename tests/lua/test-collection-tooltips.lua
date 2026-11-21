local Addon, context = ...
local ClientApi = assert(loadfile("tests/lua/support/client-api-fixture.lua"))()
local checks = 0
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    checks = checks + 1
end
Addon:SetTargetLocale("enUS")
Addon:SetTooltipMode("separate")
Addon.preferences.tooltipNameOnly.mount = false
Enum.TooltipDataLineType.SpellDescription = Enum.TooltipDataLineType.SpellDescription or 29
local translate = Addon.TranslateLiveSpellDescription
Addon.TranslateLiveSpellDescription = function(_, id, locale, text)
    if locale == "enUS" and text == "Description native" then return "Translated summon " .. id end
end
local function emit(getter, id)
    GameTooltip:Hide()
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("Native name")
    GameTooltip:AddLine("Description native")
    local data = {type = Enum.TooltipDataType.Spell, id = id, lines = {
        {type = Enum.TooltipDataLineType.SpellName, leftText = "Native name", lineIndex = 1},
        {type = Enum.TooltipDataLineType.SpellDescription, leftText = "Description native", lineIndex = 2},
    }}
    GameTooltip.processingInfo = {getterName = getter, getterArgs = {id}, tooltipData = data}
    for _, callback in ipairs(context.callbacks) do callback(GameTooltip, data) end
    GameTooltip:Show()
    context.flushTimers()
    return Addon.nameTooltips[GameTooltip]
end
local spec = emit("GetMountBySpellID", 458)
equal(spec.kind, "mount", "mount keeps its independent feature")
equal(spec.tip.lines[2], "Translated summon 458", "mount body uses the summon spell renderer")
Addon.preferences.tooltipNameOnly.mount = true
spec = emit("GetMountBySpellID", 458)
equal(#spec.tip.lines, 1, "name-only mode still suppresses mount descriptions")
Addon.preferences.tooltipNameOnly.mount = false
spec = emit("GetCompanionPet", 17707)
equal(spec.kind, "pet", "companion-pet getter takes precedence over generic spells")
equal(spec.tip.lines[1], "Summon Panda", "pet summon title uses the owned spell")
equal(spec.tip.lines[2], "Translated summon 17707", "pet summon body uses the spell renderer")
Addon:SetFeatureEnabled("petTooltip", false)
equal(spec.tip:IsShown(), false, "pet feature disables the native collection tooltip too")
Addon:SetFeatureEnabled("petTooltip", true)
Addon.TranslateLiveSpellDescription = translate

GameTooltip:Hide()
GameTooltip.processingInfo = nil
local accurateLines = GameTooltip.accurateLines
GameTooltip.accurateLines = true
C_TransmogCollection = {GetSourceInfo = function(id)
    if id == 10 then return {itemID = 5626} end
    if id == 20 then return {itemID = 999999999} end
end}
CollectionWardrobeUtil = {
    GetDefaultSourceIndex = function(sources, primary)
        for index, entry in ipairs(sources) do if entry.sourceID == primary then return index end end
        return 1
    end,
    GetValidIndexForNumSources = function(index, count) return (index - 1) % count + 1 end,
    SetAppearanceTooltip = function(source)
        source:ClearLines()
        source:SetText("Native appearance")
        source:AddLine("Native appearance instructions")
        source:Show()
    end,
}
WardrobeItemsCollectionSlotButtonMixin = {OnEnter = function() end}
Addon:GetTooltipComponent("appearance").Install()
local appearance = {sources = {{sourceID = 10}, {sourceID = 20}}, primarySourceID = 10}
CollectionWardrobeUtil.SetAppearanceTooltip(GameTooltip, appearance)
context.flushTimers()
equal(spec.kind, "appearance", "manual appearance tooltip uses its own feature")
equal(spec.id, 5626, "appearance resolves the selected source's item ID")
equal(spec.tip.lines[1], "Skullchipper", "appearance reuses the owned item name")
equal(spec.tip.lines[2], "Native appearance instructions", "missing appearance wording stays native")
appearance.selectedIndex = 2
CollectionWardrobeUtil.SetAppearanceTooltip(GameTooltip, appearance)
context.flushTimers()
equal(spec.tip:IsShown(), false, "cycling to an unknown item clears the previous translation")
appearance.sources = {{sourceID = 10, isHideVisual = true}}
appearance.selectedIndex = nil
CollectionWardrobeUtil.SetAppearanceTooltip(GameTooltip, appearance)
context.flushTimers()
equal(spec.tip:IsShown(), false, "hide-visual appearances never borrow an item name")
GameTooltip:Hide()

-- XML copies mixin handlers before the collections addon finishes loading.
-- Calling that original handler must still reach the translation hook.
WardrobeCollectionFrame = CreateFrame("Frame", "FRSTestWardrobe", UIParent)
local slot = CreateFrame("Button", nil, WardrobeCollectionFrame)
slot.slot = "CHESTSLOT"
ClientApi.InstallGlobals("frFR", {"CHESTSLOT"})
local getClientLabel = Addon.GetClientLabel
Addon.GetClientLabel = function(_, key, locale)
    local id = ForeverRosettaStoneDB:GetGlobalStringKeys()[key]
    return id and ForeverRosettaStoneDB:GetGlobalString(id, locale)
end
local function copiedSlotOnEnter(button)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:SetText(CHESTSLOT)
    GameTooltip:Show()
end
copiedSlotOnEnter(slot)
context.flushTimers()
equal(spec.kind, "appearanceSlot", "copied category handlers use their own tooltip feature")
equal(spec.tip.lines[1], "Chest", "category name resolves its owned GlobalString key")
Addon:SetFeatureEnabled("appearanceTooltip", false)
copiedSlotOnEnter(slot)
context.flushTimers()
equal(spec.tip:IsShown(), true, "categories remain enabled when appearance items are disabled")
Addon:SetFeatureEnabled("appearanceSlotTooltip", false)
equal(spec.tip:IsShown(), false, "category setting disables the current category translation")
Addon:SetFeatureEnabled("appearanceSlotTooltip", true)
Addon:SetFeatureEnabled("appearanceTooltip", true)
copiedSlotOnEnter(slot)
context.flushTimers()
equal(spec.tip:IsShown(), true, "category setting restores translations")
Addon:SetTooltipMode("stacked")
for index = 1, 2 do
    copiedSlotOnEnter(slot)
    context.flushTimers()
end
local translatedCategoryCount = 0
for index = 1, GameTooltip:NumLines() do
    if GameTooltip:GetLeftLine(index):GetText() == "Chest" then translatedCategoryCount = translatedCategoryCount + 1 end
end
equal(translatedCategoryCount, 1, "repeated category hovers append one stacked translation")
equal(GameTooltip:GetLeftLine(1):GetText(), "Torse", "stacked category translation retains the native title")
Addon:SetTooltipMode("separate")
slot:SetParent(UIParent)
copiedSlotOnEnter(slot)
context.flushTimers()
equal(spec.tip:IsShown(), false, "similar slot fields outside the wardrobe never trigger category translation")
Addon.GetClientLabel = getClientLabel
WardrobeCollectionFrame:Hide()
GameTooltip:Hide()

GameTooltip.accurateLines = accurateLines
LFGListingFrame = CreateFrame("Frame", "FRSTestGroupFinder", UIParent)
LFGListingFrame:Show()
local row = CreateFrame("Button", nil, LFGListingFrame)
local child = CreateFrame("Button", nil, row)
local activityID = 796
function row:GetElementData() return {GetData = function() return {activityID = activityID} end} end
row.left, row.top = 300, 600
row:SetSize(200, 30)
row:Show()
child:Show()
context.setMouseFoci({child})
local activity = Addon:GetTooltipComponent("activity")
activity.Update()
equal(Addon.activityTooltip:GetLeftLine(2):GetText(), "Wailing Caverns", "group finder resolves tree-node activity IDs")
equal(Addon.activityTooltip:IsShown(), true, "hovering a child button displays the activity translation")
activityID = 919
activity.Update()
equal(Addon.activityTooltip:GetLeftLine(2):GetText(), "Warsong Gulch", "battleground activities use their own catalog IDs")
local unrelated = CreateFrame("Button", nil, UIParent)
unrelated.GetElementData = row.GetElementData
context.setMouseFoci({unrelated})
activity.Update()
equal(Addon.activityTooltip:IsShown(), false, "activity-like rows outside group finder never trigger a translation")
context.setMouseFoci({child})
activityID = 999999999
activity.Update()
equal(Addon.activityTooltip:IsShown(), false, "recycled rows with unknown IDs clear stale activity names")
activityID = 796
Addon:SetFeatureEnabled("activityTooltip", false)
activity.Update()
equal(Addon.activityTooltip:IsShown(), false, "activity feature switch suppresses hover translations")
Addon:SetFeatureEnabled("activityTooltip", true)
context.setMouseFoci({})
activity.Update()
equal(Addon.activityTooltip:IsShown(), false, "leaving group finder rows hides the translation")

local isGamepad = InputUtil.IsGamepadUIEnabled
local activeFrame, currentButton = SmartNavigation.activeFrame, SmartNavigation.currentButton
InputUtil.IsGamepadUIEnabled = function() return true end
local panel = CreateFrame("Frame", nil, UIParent)
LFGListingFrame:SetParent(panel)
SmartNavigation.activeFrame, SmartNavigation.currentButton = panel, child
activity.Update()
equal(Addon.activityTooltip:IsShown(), true, "gamepad resolves activity rows inside the active parent panel")
equal(Addon.activityTooltip:GetLeftLine(2):GetText(), "Wailing Caverns", "gamepad and mouse render the same activity name")

local otherRow = CreateFrame("Button", nil, LFGListingFrame)
function otherRow:GetElementData() return {activityID = 919} end
context.setMouseFoci({otherRow})
activity.Update()
equal(Addon.activityTooltip:GetLeftLine(2):GetText(), "Wailing Caverns", "gamepad selection takes priority over a parked mouse")
SmartNavigation.activeFrame = row
activity.Update()
equal(Addon.activityTooltip:GetLeftLine(2):GetText(), "Wailing Caverns", "nested navigation panels preserve gamepad translations")
context.setMouseFoci({})
SmartNavigation.currentButton = unrelated
activity.Update()
equal(Addon.activityTooltip:IsShown(), false, "gamepad focus outside group finder clears the translation")
SmartNavigation.currentButton = child
SmartNavigation.activeFrame = unrelated
activity.Update()
equal(Addon.activityTooltip:IsShown(), false, "stale selections outside the active panel are ignored")
SmartNavigation.activeFrame = panel
SmartNavigation.currentButton = nil
activity.Update()
equal(Addon.activityTooltip:IsShown(), false, "hidden gamepad cursor clears the translation")
SmartNavigation.activeFrame, SmartNavigation.currentButton = activeFrame, currentButton
InputUtil.IsGamepadUIEnabled = isGamepad
LFGListingFrame:Hide()
return checks
