local Addon, callbacks, flushTimers = ...
local checks = 0
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    checks = checks + 1
end
local previousAuras, previousType, previousCombat = C_UnitAuras, Enum.TooltipDataType.UnitAura, InCombatLockdown
local previousPrimary = GameTooltip.GetPrimaryTooltipInfo
local previousProcessing = GameTooltip.GetProcessingTooltipInfo
local oldLocale, oldMode, oldCoverage = Addon:GetTargetLocale(), Addon.preferences.tooltipMode, Addon.preferences.tooltipNameOnly.aura
local restricted = true
Enum.TooltipDataType.UnitAura = 7
C_UnitAuras = { GetAuraDataByAuraInstanceID = function(unit, instance)
    equal(unit, "player", "aura recovery reads the original unit")
    equal(instance, 41, "aura recovery uses the live instance ID")
    return { spellId = restricted and { secret = true } or 133 }
end }
InCombatLockdown = function() return restricted end
Addon:SetTargetLocale("enUS")
Addon:SetTooltipMode("stacked")
Addon:SetTooltipNameOnly("aura", false)
GameTooltip:Hide()
GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
GameTooltip:ClearLines()
GameTooltip:AddLine("Boule de feu")
GameTooltip:AddLine("Native aura details")
local data = { type = 7, id = 41, lines = {
    { type = 13, leftText = "Boule de feu", lineIndex = 1 },
    { type = 0, leftText = "Native aura details", lineIndex = 2 },
} }
local info = { getterName = "GetUnitAuraByAuraInstanceID", getterArgs = { "player", 41 }, tooltipData = data }
GameTooltip.processingInfo = info
GameTooltip.GetPrimaryTooltipInfo = function() return info end
for _, callback in ipairs(callbacks) do callback(GameTooltip, data) end
GameTooltip:Show()
flushTimers()
equal(Addon.nameTooltips[GameTooltip].id, nil, "a restricted spell ID is never guessed from the aura ID")
GameTooltip.GetProcessingTooltipInfo = function() return nil end
Addon:RefreshNameTooltips()
flushTimers()
equal(Addon.nameTooltips[GameTooltip].id, nil, "a refresh cannot recover an identity while it remains restricted")
restricted = false
Addon:RefreshNameTooltips()
flushTimers()
equal(Addon.nameTooltips[GameTooltip].id, 133, "combat-end refresh resolves an aura without a previous identity")
equal(Addon.nameTooltips[GameTooltip].name, ForeverRosettaStoneDB:GetSpellName(133, "enUS"),
    "combat-end recovery loads the spell translation")
local spec = Addon.nameTooltips[GameTooltip]
Addon:SetTooltipMode("separate")
flushTimers()
equal(spec.tip:GetLeftLine(2):GetText(), "Native aura details", "full aura coverage preserves the details")
Addon:SetFeatureEnabled("spellTooltip", false)
flushTimers()
equal(spec.tip:IsShown(), true, "disabling spell tooltips keeps active aura translations")
Addon:SetFeatureEnabled("auraTooltip", false)
flushTimers()
equal(spec.tip:IsShown(), false, "auras can be disabled independently")
Addon:SetFeatureEnabled("spellTooltip", true)
flushTimers()
equal(spec.tip:IsShown(), false, "enabling spell tooltips leaves auras disabled")
Addon:SetFeatureEnabled("auraTooltip", true)
Addon:SetTooltipNameOnly("aura", true)
flushTimers()
equal(Addon:GetTooltipCoverage("spell"), "full", "aura coverage is independent from spells")
equal(spec.tip:GetText(), "Fireball", "name-only aura still translates the spell name")
equal(#spec.tip.lines, 0, "name-only aura clears companion details")
equal(GameTooltip:GetLeftLine(2):GetText(), "Native aura details", "name-only aura preserves native details")
C_UnitAuras.GetAuraDataByAuraInstanceID = function() return nil end
Addon:RefreshNameTooltips()
flushTimers()
equal(Addon.nameTooltips[GameTooltip].id, nil, "an expired aura cannot reuse its previously resolved identity")
GameTooltip:Hide()
GameTooltip.GetPrimaryTooltipInfo = previousPrimary
GameTooltip.GetProcessingTooltipInfo = previousProcessing
GameTooltip.processingInfo = nil
C_UnitAuras, Enum.TooltipDataType.UnitAura, InCombatLockdown = previousAuras, previousType, previousCombat
Addon:SetTargetLocale(oldLocale)
Addon:SetTooltipMode(oldMode)
Addon:SetTooltipNameOnly("aura", oldCoverage)
return checks
