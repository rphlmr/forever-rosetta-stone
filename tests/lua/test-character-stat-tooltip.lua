local Addon, flushTimers, hooks = ...
local ClientApi = assert(loadfile("tests/lua/support/client-api-fixture.lua"))()
local accurateLines = GameTooltip.accurateLines
GameTooltip.accurateLines = true
local checks = 0
local function Check(condition, message)
    assert(condition, message)
    checks = checks + 1
end
ClientApi.InstallGlobals("frFR", {"HEALTH", "STAT_HEALTH_TOOLTIP", "RESISTANCE_TYPE4", "DAMAGE_SCHOOL5", "DAMAGE", "STAT_FORMAT"})
-- Simplified template: the captured one needs the client |2 grammar formatter.
RESISTANCE_TOOLTIP_SUBTEXT = "Résistance au %s : %d%%"
local formats = Addon.characterStatFormats.enUS
local healthText, resistanceText = formats.STAT_HEALTH_TOOLTIP, formats.RESISTANCE_TOOLTIP_SUBTEXT
formats.STAT_HEALTH_TOOLTIP = "Current health."
formats.RESISTANCE_TOOLTIP_SUBTEXT = "Resistance to %s: %d%%"
local row = CreateFrame("Frame", nil, UIParent)
row.Label, row.Value = row:CreateFontString(), row:CreateFontString()
local function Show(title, body)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:SetText(title)
    GameTooltip:AddLine(body, 1, 0.8, 0, true)
    GameTooltip:Show()
    flushTimers()
    return Addon.nameTooltips[GameTooltip]
end
Addon:SetTargetLocale("enUS")
Addon:SetTooltipMode("separate")
PaperDollFrame_SetLabelAndText(row, HEALTH, "103")
hooks.PaperDollFrame_SetLabelAndText(row, HEALTH, "103")
local spec = Show("|cffffffffVie 103|r", STAT_HEALTH_TOOLTIP)
Check(spec.kind == "characterStat" and spec.tip:IsShown(), "stat row displays a separate translation")
Check(spec.tip:GetLeftLine(1):GetText() == "|cffffffffHealth 103|r", "title uses the live displayed health")
Check(spec.tip:GetLeftLine(2):GetText() == "Current health.", "description uses the selected target")
Check(GameTooltip:GetLeftLine(2):GetText() == STAT_HEALTH_TOOLTIP, "original French explanation is preserved")
Check(select(2, spec.tip:GetLeftLine(2):GetTextColor()) == 0.8, "row colors are preserved")
GameTooltip:Hide()
Check(not spec.tip:IsShown(), "native hide removes the translated stat tooltip")

PaperDollFrame_SetResistanceTooltips({}, DAMAGE_SCHOOL5, 25, "player", 4)
CharacterStatFrameScrollBoxBaseElementMixin.Init(row, { labelText = DAMAGE_SCHOOL5 })
spec = Show("|cffffffffGivre 25|r", "Résistance au givre : 35%")
Check(spec.tip:GetLeftLine(1):GetText() == "|cffffffffFrost 25|r", "unnamed resistance frame is translated")
Check(spec.tip:GetLeftLine(2):GetText() == "Resistance to frost: 35%", "resistance keeps client values")
GameTooltip:AddDoubleLine(STAT_FORMAT:format(DAMAGE), "4 - 7", 1, 1, 0, 0, 1, 0)
GameTooltip:GetRightLine(3):SetTextColor(0, 1, 0)
GameTooltip:Show()
flushTimers()
Check(spec.tip:GetRightLine(3):GetText() == "4 - 7", "specialized double rows retain their right-hand values")
Check(select(2, spec.tip:GetRightLine(3):GetTextColor()) == 1, "right-hand colors are retained")

-- A native tooltip need not allocate right-hand FontStrings for single-column rows.
local sparseTip = CreateFrame("GameTooltip", nil, UIParent)
local getRightLine, addLine = sparseTip.GetRightLine, sparseTip.AddLine
sparseTip.AddLine = function(self, ...)
    self.GetRightLine = getRightLine
    addLine(self, ...)
    self.GetRightLine = function(frame, index)
        if type(frame.lines[index]) == "table" then return getRightLine(frame, index) end
    end
end
Addon:GetTooltipComponent("characterStat").FillTooltip(sparseTip, GameTooltip, nil, nil, nil, nil, spec)
Check(sparseTip:GetLeftLine(2):GetText() == "Resistance to frost: 35%", "missing right FontStrings retain single-column stat text")
Check(sparseTip:GetRightLine(3):GetText() == "4 - 7", "allocated right FontStrings retain double-column stat text")
CharacterStatFrameScrollBoxBaseElementMixin.Init(row, nil)
CharacterStatFrameScrollBoxBaseElementMixin.Init(row, 42)
GameTooltip:Hide()
GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
GameTooltip:ClearLines()
GameTooltip:AddLine("Givre 25")
GameTooltip:AddLine("Résistance au givre : 35%")
local nativeRight = GameTooltip.GetRightLine
GameTooltip.GetRightLine = function() return nil end
GameTooltip:Show()
flushTimers()
GameTooltip.GetRightLine = nativeRight
Check(spec.tip:GetLeftLine(2):GetText() == "Resistance to frost: 35%", "capture tolerates absent native right columns and recycled row data")

Addon:SetTooltipMode("stacked")
spec = Show("|cffffffffGivre 25|r", "Résistance au givre : 35%")
local firstCount = GameTooltip:NumLines()
GameTooltip:Show()
flushTimers()
Check(VisibleTooltipLines(GameTooltip) == firstCount, "repeated native Show cannot duplicate embedded stat translations")
Check(Addon.stackedTooltips[GameTooltip] ~= nil, "stat translations use the selected stacked mode")
Addon.preferences.features.characterStatTooltip = false
Show("|cffffffffGivre 30|r", "Résistance au givre : 40%")
Check(not spec.tip:IsShown() and not Addon.stackedTooltips[GameTooltip], "disabled stat feature restores the native tooltip")
Addon.preferences.features.characterStatTooltip = true
Show("|cffffffffGivre 30|r", "Résistance au givre : 40%")
Check(GameTooltip:GetLeftLine(1):GetText() == "|cffffffffGivre 30|r", "pooled row reuse keeps current native values")
Addon:SetTooltipMode("separate")
Show("|cffffffffGivre 30|r", "Unknown future explanation")
Check(spec.tip:GetLeftLine(2):GetText() == "Unknown future explanation", "unrecognized text remains visible")
Check(spec.tip:GetLeftLine(3):GetText() == Addon:GetIncompleteTranslationNotice(), "missing text is explicitly marked")
GameTooltip:Hide()
formats.STAT_HEALTH_TOOLTIP, formats.RESISTANCE_TOOLTIP_SUBTEXT = healthText, resistanceText
GameTooltip.accurateLines = accurateLines
return checks
