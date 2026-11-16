local Addon = {}
canaccessallvalues = function() return true end
GetLocale = function() return "frFR" end
Addon.RegisterNameTooltipComponent = function() end
local subNames = {
    [900001] = { frFR = "Maître des démonistes", enUS = "Warlock Trainer" },
    [900002] = { frFR = "Maître des démonistes" },
}
ForeverRosettaStoneDB = {
    GetNpcSubName = function(_, id, locale) return subNames[id] and subNames[id][locale] end,
}
assert(loadfile("ForeverRosettaStone/database/npc-tooltip-data.lua"))("ForeverRosettaStone", Addon)
assert(loadfile("ForeverRosettaStone/tooltips/components/npc-tooltip.lua"))("ForeverRosettaStone", Addon)
assert(Addon:TranslateNpcTooltipText("Maître des démonistes", "enUS", 900001) == "Warlock Trainer")
assert(Addon:TranslateNpcTooltipText("Maître  des démonistes ", "enUS", 900001) == "Warlock Trainer")
assert(Addon:TranslateNpcTooltipText("Maître des démonistes", "enUS", 900002) == nil,
    "A missing target subname stays native")
assert(Addon:TranslateNpcTooltipText("Maître des démonistes", "enUS", 900003) == nil,
    "Do not borrow another NPC's subname by matching text")
assert(Addon:TranslateNpcTooltipText("Maître des démonistes", "enUS") == nil)
assert(Addon:TranslateNpcTooltipText("Autre titre", "enUS", 900001) == nil)
print("PASS: NPC subnames use the NPC-owned record; unrelated and missing subnames remain native")
