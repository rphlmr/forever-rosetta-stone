local Addon = {}
canaccessallvalues = function() return true end
GetLocale = function() return "frFR" end
Addon.RegisterNameTooltipComponent = function() end
local mappings = { [900001] = 10, [900002] = 20, [900003] = 30 }
local sources = { [10] = "Même nom", [20] = "Même nom", [30] = "Sans traduction" }
local targets = { [10] = "First faction", [20] = "Second faction" }
ForeverRosettaStoneDB = {
    GetNpcFactionID = function(_, id) return mappings[id] end,
    GetFactionName = function(_, id, locale) return locale == 'frFR' and sources[id] or targets[id] end,
}
assert(loadfile("ForeverRosettaStone/database/npc-tooltip-data.lua"))("ForeverRosettaStone", Addon)
assert(loadfile("ForeverRosettaStone/tooltips/components/npc-tooltip.lua"))("ForeverRosettaStone", Addon)
assert(Addon:TranslateNpcTooltipText("Même nom", "enUS", 900001) == "First faction")
assert(Addon:TranslateNpcTooltipText("Même nom", "enUS", 900002) == "Second faction")
assert(Addon:TranslateNpcTooltipText("Même nom", "enUS", 900004) == nil,
    "Do not infer an unknown NPC's faction from a matching name")
assert(Addon:TranslateNpcTooltipText("Même nom", "enUS") == nil)
assert(Addon:TranslateNpcTooltipText("Sans traduction", "enUS", 900003) == nil)
assert(Addon:TranslateNpcTooltipText("Faction changed at runtime", "enUS", 900001) == nil)
sources[10] = nil
assert(Addon:TranslateNpcTooltipText("Même nom", "enUS", 900001) == nil)
print("PASS: visible faction names use the NPC-owned faction ID; unrelated and missing names remain native")
