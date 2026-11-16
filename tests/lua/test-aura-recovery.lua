local Addon, callbacks, flushTimers = ...
local checks = 0
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    checks = checks + 1
end
local previousAuras, previousType, previousCombat = C_UnitAuras, Enum.TooltipDataType.UnitAura, InCombatLockdown
local previousPrimary = GameTooltip.GetPrimaryTooltipInfo
local previousProcessing = GameTooltip.GetProcessingTooltipInfo
local oldLocale, oldMode, oldCoverage = Addon:GetTargetLocale(), Addon.preferences.tooltipMode, Addon.preferences.tooltipCoverage
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
Addon:SetTooltipCoverage("full")
GameTooltip:Hide()
GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
GameTooltip:ClearLines()
GameTooltip:AddLine("Boule de feu")
local data = { type = 7, id = 41, lines = { { type = 13, leftText = "Boule de feu", lineIndex = 1 } } }
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
Addon:SetTooltipCoverage(oldCoverage)
return checks
