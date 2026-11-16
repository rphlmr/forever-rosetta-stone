local Addon = {}
canaccessallvalues = function() return true end
local clientLocale = "frFR"
GetLocale = function() return clientLocale end
Addon.RegisterNameTooltipComponent = function() end
local strings = {
    UNITNAME_TITLE_PET = { frFR = "Familier |2 %s", enUS = "%s's Pet", ruRU = "Питомец |3-1(%s)", koKR = "%s의 소환수" },
    UNITNAME_TITLE_MINION = { frFR = "Serviteur |2 %s", enUS = "%s's Minion", koKR = "%s의 소환수" },
    UNITNAME_TITLE_CHARM = { frFR = "Serviteur |2 %s", enUS = "%s's Minion" },
    UNITNAME_SUMMON_TITLE4 = { frFR = "Totem |2 %s", enUS = "%s's Totem" },
    UNITNAME_SUMMON_TITLE7 = { frFR = "Assemblage |2 %s" },
    UNITNAME_SUMMON_TITLE27 = { frFR = "%s", enUS = "%s" },
}
ForeverRosettaStoneDB = {
    GetGlobalStringByKey = function(_, key, locale) return strings[key] and strings[key][locale] end,
}
assert(loadfile("ForeverRosettaStone/database/npc-tooltip-data.lua"))("ForeverRosettaStone", Addon)
assert(loadfile("ForeverRosettaStone/tooltips/components/npc-tooltip.lua"))("ForeverRosettaStone", Addon)
local function T(text, locale) return Addon:TranslateNpcTooltipText(text, locale, 416) end
assert(T("Familier de Dane Winslow", "enUS") == "Dane Winslow's Pet")
assert(T("Familier d'Arthas", "enUS") == "Arthas's Pet", "French elision before a vowel")
-- Live C_TooltipInfo owner rows (type UnitOwner) keep the raw grammar code unresolved.
assert(T("Familier |2 Dane Winslow", "enUS") == "Dane Winslow's Pet", "Raw |2 code from tooltip data")
assert(T("Familier |2 Arthas", "enUS") == "Arthas's Pet", "Raw |2 code before a vowel")
assert(T("Serviteur de Dane", "enUS") == "Dane's Minion", "Identical titles with one target translate")
assert(T("Totem d’Ilsa", "enUS") == "Ilsa's Totem", "Typographic apostrophe elision")
assert(T("Assemblage de Dane", "enUS") == nil, "A missing target keeps the native line")
assert(T("Dane Winslow", "enUS") == nil, "A bare owner name never matches a placeholder-only title")
assert(T("Familier de Dane", "ruRU") == "Питомец Dane", "Target grammar codes resolve without raw escapes")
clientLocale = "enUS"
assert(T("Arthas's Pet", "frFR") == "Familier d'Arthas")
assert(T("Dane Winslow's Pet", "frFR") == "Familier de Dane Winslow")
clientLocale = "koKR"
assert(T("Dane의 소환수", "enUS") == nil, "Ambiguous native titles with different targets stay native")
print("PASS: owner title lines translate through GlobalStrings; owner names, ambiguity and gaps stay native")
