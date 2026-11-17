local Addon = ...
local checks = 0
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    checks = checks + 1
end
local source = Addon:CreateCompanionTooltip(nil, UIParent)
local translated = Addon:CreateCompanionTooltip(nil, UIParent)
source.accurateLines, translated.accurateLines = true, true
local label = Addon:GetTooltipTranslationLabel()
local function hasLabel(tip)
    for index = 1, tip:NumLines() do
        if tip:GetLeftLine(index):GetText() == label then return true end
    end
    return false
end
equal(Addon.preferences.translationHeader, true, "translation headers are enabled by default")
equal(Addon.settings.translationHeader:GetValue(), true, "native Settings exposes the default")
source:SetText("Native title")
translated:SetText("Translated title")
Addon:FillStackedTooltip(source, translated, "same-content")
equal(hasLabel(source), true, "stacked translations show the header by default")
Addon.settings.translationHeader:SetValue(false)
Addon:FillStackedTooltip(source, translated, "same-content")
equal(hasLabel(source), false, "disabling headers removes their text and icon from cached stacked content")
equal(source:GetLeftLine(1):GetText(), "Native title", "native title stays intact")
translated:ClearLines()
Addon:SetStandaloneTooltipTitle(translated, "Translated title")
equal(translated:GetLeftLine(1):GetText(), "Translated title", "standalone title becomes the first row without a header")
equal(hasLabel(translated), false, "standalone tooltips also hide the header")
Addon:LoadPreferences()
equal(Addon.preferences.translationHeader, false, "header opt-out survives preferences loading")
Addon.settings.translationHeader:SetValueToDefault()
equal(Addon.preferences.translationHeader, true, "native Defaults restores headers")
translated:ClearLines()
Addon:SetStandaloneTooltipTitle(translated, "Translated title")
equal(translated:GetLeftLine(2):GetText(), "Translated title", "standalone title follows the restored header")
equal(hasLabel(translated), true, "standalone header returns after restoring defaults")
Addon:ClearStackedTooltip(source)
Addon:ClearStackedTooltip(source, true)
source:ClearLines()
source:AddLine("Native title")
source:AddLine("Restricted native amount")
local nativeLine = source:GetLeftLine(2)
local originalGetText, reads = nativeLine.GetText, 0
nativeLine.GetText = function() reads = reads + 1; return { secret = true } end
translated:ClearLines()
translated:SetOwner(UIParent, "ANCHOR_NONE")
translated:SetText("Translated aura")
translated:Show()
Addon:FillStackedTooltip(source, translated, "restricted-native-row")
equal(translated:IsShown(), false, "stacked mode never leaves a second companion visible")
equal(reads, 0, "stacking does not need to read the original restricted rows")
equal(source:GetLeftLine(source:NumLines()):GetText(), "Translated aura", "translation is appended after restricted native content")
equal(source:GetLeftLine(1):GetText(), "Native title", "stacking preserves the native title")
nativeLine.GetText = originalGetText
Addon:ClearStackedTooltip(source)
source:Hide()
translated:Hide()

-- FontString getters can return restricted text even on an addon-owned companion.
-- Lua 5.1 cannot model secret strings, so verify that neither column reaches the target.
local restricted = { secret = true }
for index, columns in ipairs({
    { "Restricted amount", restricted },
    { restricted, "Readable amount" },
    { restricted, restricted },
}) do
    local native = Addon:CreateCompanionTooltip(nil, UIParent)
    native.accurateLines = true
    native:SetText("Native title")
    translated:ClearLines()
    translated:AddLine("Translated title")
    translated:AddDoubleLine("Temporary label", "Temporary amount")
    translated:GetLeftLine(2).GetText = function() return columns[1] end
    translated:GetRightLine(2).GetText = function() return columns[2] end
    translated:AddDoubleLine("Damage", "4 - 7")
    translated:Show()
    local ok = Addon:Run("stack restricted companion text", function()
        Addon:FillStackedTooltip(native, translated, "restricted-companion-" .. index)
    end)
    equal(ok, true, "restricted companion text does not fail the safety wrapper")
    equal(Addon.lifecycle, "ready", "restricted companion text keeps the addon running")
    equal(native:NumLines(), 5, "restricted rows are omitted without leaving partial columns")
    equal(native:GetLeftLine(1):GetText(), "Native title", "restricted rows leave native content intact")
    equal(native:GetLeftLine(4):GetText(), "Translated title", "readable translated rows are retained")
    equal(native:GetRightLine(5):GetText(), "4 - 7", "readable double-column rows are retained")
    equal(translated:IsShown(), false, "restricted companion text still hides the companion")
    equal(Addon.tooltipRendering, nil, "restricted companion text leaves rendering state clear")
    translated:GetLeftLine(2).GetText = originalGetText
    translated:GetRightLine(2).GetText = originalGetText
    Addon:ClearStackedTooltip(native)
    native:Hide()
end
return checks
