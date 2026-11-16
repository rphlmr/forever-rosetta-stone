local Addon = {}
local ClientApi = assert(loadfile("tests/lua/support/client-api-fixture.lua"))()
local records = {
    [2973] = {
        description = "A strong attack that deals melee weapon damage plus $s1.",
        sourceDescriptions = { frFR = "Une attaque puissante qui inflige les dégâts de l’arme de mêlée plus $s1." },
        effects = { { index = 0, basePoints = 5 } },
    },
    [10] = {
        description = "Ice shards pelt the target area doing ${$1279976m1*$d*$<frostdamage>} Frost damage over $d.",
        sourceDescriptions = { frFR = "Des éclats infligent ${$1279976m1*$d*$<frostdamage>} points de dégâts en $d." },
        durationMs = 8000,
    },
    [133] = {
        description = "Deals $s1 damage and $o2 over $d.",
        sourceDescriptions = { frFR = "Inflige $s1 dégâts et $o2 en $d." },
        effects = { { index = 0, basePoints = 18, variance = 0.44 } }, durationMs = 4000,
    },
    [14824] = { description = "Increases ranged attack speed by $s1%.",
        sourceDescriptions = { frFR = "Augmente la vitesse des attaques à distance de $s1%." },
        effects = { { index = 0, basePoints = 10 } } },
}
local items = { [2102] = { classID = 11, subclassID = 3, containerSlots = 6,
    effects = { { spellID = 14824, triggerType = 1 } } } }
local locale = "frFR"
GetLocale = function() return locale end
canaccessallvalues = function(...)
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if type(value) == "table" and value.secret then return false end
    end
    return true
end
ForeverRosettaStoneDB = {
    GetSpellDetails = function(_, id, targetLocale)
        local record = records[id]
        if targetLocale == "frFR" and record and record.sourceDescriptions then
            return { description = record.sourceDescriptions.frFR, originalFields = { description = true } }
        end
        return record
    end,
    GetSpellRules = function(_, id)
        local record = records[id]
        return record and { effects = record.effects, durationMs = record.durationMs, variables = record.variables }
    end,
    GetSpellName = function(_, id) return "Spell " .. id end,
    GetItemDetails = function(_, id) return items[id] end,
    GetItemRules = function(_, id) return items[id] end,
}
ForeverRosettaStoneDB.GetSpellSourceDetails = function() error("Source spell text must not be accessed") end
ForeverRosettaStoneDB.GetSourceSpellName = function() error("Source spell names must not be accessed") end
assert(loadfile("ForeverRosettaStone/tooltips/spell-live-values.lua"))("ForeverRosettaStone", Addon)
assert(loadfile("ForeverRosettaStone/tooltips/tooltip-descriptions.lua"))("ForeverRosettaStone", Addon)
assert(loadfile("ForeverRosettaStone/tooltips/english-tooltip-formats.lua"))("ForeverRosettaStone", Addon)
local text
C_Spell = {}
ClientApi.InstallGlobals("frFR", {"ARMOR_TEMPLATE", "SHIELD_BLOCK_TEMPLATE", "DURABILITY_TEMPLATE"})
Addon.itemTooltipLabels = { INVTYPE_SHIELD = "Off Hand" }
assert(Addon:TranslateLiveTooltipLine("Armure : 12") == "12 Armor")
assert(Addon:TranslateLiveTooltipLine("Bloquer : 1") == "1 Block")
assert(Addon:TranslateLiveTooltipLine("Durabilité 19 / 25") == "Durability 19 / 25")
assert(Addon:TranslateLiveTooltipLine({ secret = true }) == nil)
ClientApi.InstallGlobals("frFR", {"SPELL_ON_NEXT_SWING"})
assert(Addon:TranslateLiveTooltipLine(SPELL_ON_NEXT_SWING) == "Next melee")
ClientApi.InstallGlobals("frFR", {"SPELL_RANGE", "SPELL_RANGE_DUAL"})
assert(Addon:TranslateLiveTooltipLine("portée de 8-35 m.") == "8-35 yd range",
    "Translate minimum-to-maximum range without losing either live endpoint")
assert(Addon:TranslateLiveTooltipLine("portée de 35 m.") == "35 yd range")
assert(Addon:TranslateLiveTooltipLine("portée de 8,5-35,5 m.") == "8.5-35.5 yd range")
assert(Addon:TranslateLiveTooltipLine("Prochaine attaque en mêlée : 8-35 m. de portée")
    == "Next melee: 8-35 yd range", "Dual range labels must also accept numeric intervals")
assert(Addon:TranslateLiveTooltipLine("portée de inconnue-35 m.") == nil,
    "Do not accept arbitrary text as a numeric interval")
for _, key in ipairs({ "PROFESSIONS_USED_IN_COOKING", "PROFESSIONS_MODIFIED_CRAFTING_REAGENT_BASIC",
    "PROFESSIONS_MODIFIED_CRAFTING_REAGENT_MODIFYING_REQUIRED" }) do
    _G[key] = "Composant d’artisanat"
    assert(Addon:TranslateLiveTooltipLine(_G[key]) == "Crafting Reagent", key .. " must translate reagent labels")
    _G[key] = nil
end
ClientApi.InstallGlobals("frFR", {"PROFESSIONS_USED_IN_COOKING"})
Enum = { TooltipDataLineType = { SellPrice = 11, SpellDescription = 34, SpellName = 13,
    EquipSlot = 21, ItemName = 22 } }
ClientApi.InstallGlobals("frFR", {"ITEM_SPELL_TRIGGER_ONEQUIP"})
Addon.itemSubclasses = { [11] = { [3] = "Ammo Pouch" } }
Addon.GetTargetLocale = function() return "enUS" end
Addon.IsTooltipBlocked = function() return false end
Addon.IsFeatureEnabled = function() return true end
local function row(line, kind, id) return Addon:GetEnglishTooltipLine({}, line, kind or "item", id or 2102) end
Addon.GetClientLabel = function(_, key, target)
    if target ~= "enUS" then return end
    if key == "ITEM_RESIST_SINGLE" then return "%c%d %s Resistance" end
    if key == "ITEM_RESIST_ALL" then return "%c%d to All Resistances" end
end
ClientApi.InstallGlobals("frFR", {"ITEM_RESIST_SINGLE", "ITEM_RESIST_ALL", "SPELL_SCHOOL2_CAP", "SPELL_SCHOOL3_CAP"})
assert(row({ leftText = "+8 à la résistance Feu" }) == "+8 Fire Resistance",
    "Item resistance rows translate their school and retain the live value")
assert(row({ leftText = "+9 à la résistance Nature" }) == "+9 Nature Resistance",
    "Nature resistance uses the same generic item format")
assert(row({ leftText = "-12 à toutes les résistances" }) == "-12 to All Resistances",
    "All-school resistance preserves the sign and live amount")
records[1293657] = {
    description = "You are fluent in the following languages:$?s668[\n$@spellname668][]$?s669[\n$@spellname669][]",
    sourceDescriptions = { frFR = "Vous parlez couramment les langues suivantes :$?s668[\n$@spellname668][]$?s669[\n$@spellname669][]" },
}
records[1293712] = {
    description = "You are proficient in the use of the following armor types:$?s9078[\n$@spellname9078][]$?s9077[\n$@spellname9077][]$?s750[\n$@spellname750][]",
}
C_SpellBook = { IsSpellKnown = function(id) return id ~= 750 end }
text = row({ type = 34, leftText = "Vous maîtrisez l’utilisation des types d’armure suivants :\nTissu\nCuir" }, "spell", 1293712)
assert(text == nil, "A multiline spell description without structured row context stays native")
C_SpellBook = nil
GameTooltipMoneyFormat = {}
MoneyFormatterUtil = { FormatMoney = function(amount, format)
    assert(format == GameTooltipMoneyFormat, "Use the native tooltip money format")
    return amount .. "|Tcoin|t"
end }
assert(row({ type = 11, price = 3 }) == "Sell Price: 3|Tcoin|t", "Use native coins and actual instance sale price")
assert(row({ leftText = "Equipé : Augmente la vitesse des attaques à distance de 12%." }) == nil,
    "An untyped item effect stays native")
ClientApi.InstallGlobals("frFR", {"CONTAINER_SLOTS"})
C_Item = { GetItemSubClassInfo = function() return "Giberne" end }
assert(row({ leftText = "Giberne 6 emplacements" }) == nil, "Do not identify an item subclass by its native name")
ClientApi.InstallGlobals("frFR", {"MANA_COST", "SPELL_RECAST_TIME_MIN"})
assert(row({ leftText = "Mana : 14" }, "spell", 2973) == "14 Mana", "Known mana format translates")
local _, right = row({ rightText = "3 min de recharge" }, "spell", 2973)
assert(right == "3 min cooldown", "Known cooldown format translates")
assert(row({ type = 34, leftText = "Inflige 18 à 25 dégâts et 4 en 4 s." }, "spell", 133) == nil,
    "Missing structured formula values keep the native description")
assert(row({ leftText = { secret = true } }) == nil, "Secret text stays unread")
assert(row({ leftText = "Unknown enchantment" }) == nil, "Unknown text stays native")
records[20594] = { rank = "Racial", sourceRanks = { frFR = "Raciale" } }
assert(Addon:GetEnglishTooltipSubtext({ type = 13, rightText = "Raciale" }, "spell", 20594) == "Racial")
ClientApi.InstallGlobals("frFR", {"ITEM_SPELL_CHARGES"})
assert(row({ leftText = "2 charges" }) == "2 Charges", "Known charge format translates")
records[8690] = { description = "Returns you to $z." }
items[6948] = { effects = { { spellID = 8690, triggerType = 0 } } }
local hearthstone = "Utiliser : Vous renvoie à Vallée des Frigères."
assert(row({ leftText = hearthstone }, "item", 6948) == nil, "Untyped item effects remain native")
items[2516] = { classID = 6, subclassID = 3 }
Addon.itemSubclasses[6] = { [3] = "Bullet" }
local ammoLeft, ammoRight = row({ type = 21, leftText = "Projectile", rightText = "Balle" }, "item", 2516)
assert(ammoLeft == nil and ammoRight == "Bullet", "Typed equipment rows use the catalog subclass")
local function font(size, scale, red, green, blue)
    return {
        GetFont = function() return "native", size, "" end,
        GetTextScale = function() return scale end,
        GetTextColor = function() return red, green, blue end,
    }
end
local sourceLines = { font(16, 1, 1, 1, 1), font(14, 1, 0, 1, 0), font(12, 0.9, 1, 1, 1) }
local rendered = {}
local tip = {
    AddLine = function(_, text, r, g, b)
        local line = { text = text, color = { r, g, b } }
        line.SetFont = function(_, name, size, flags) line.font = { name, size, flags } end
        line.SetTextScale = function(_, scale) line.scale = scale end
        rendered[#rendered + 1] = line
    end,
    NumLines = function() return #rendered end,
    GetLeftLine = function(_, index) return rendered[index] end,
}
HIGHLIGHT_FONT_COLOR = { r = 1, g = 1, b = 1 }
Addon:FillEnglishTooltip({ tip = tip, source = {
    GetLeftLine = function(_, index) return sourceLines[index] end,
}, name = "Tough Jerky", kind = "item", id = 2102, data = { lines = {
    { type = 22, lineIndex = 1 },
    { type = 11, price = 4, lineIndex = 2, leftColor = { r = 1, g = 0.82, b = 0 } },
} } })
assert(rendered[2].text == "Sell Price: 4|Tcoin|t")
assert(rendered[2].color[1] == 1 and rendered[2].color[2] == 1 and rendered[2].color[3] == 1,
    "Sell price must use the native white highlight color")
assert(rendered[2].font[2] == 12 and rendered[2].scale == 0.9,
    "Sell price must copy the appended money row's font, not the preceding effect row")
tip.AddDoubleLine = function(self, left, right, r, g, b)
    self:AddLine(left, r, g, b)
    rendered[#rendered].right = right
end
rendered = {}
items[2770] = { classID = 7, subclassID = 7 }
Addon:FillEnglishTooltip({ tip = tip, source = {
    GetLeftLine = function(_, index) return sourceLines[index] end,
}, name = "Copper Ore", kind = "item", id = 2770, data = { lines = {
    { type = 22, lineIndex = 1 },
    { lineIndex = 2, leftText = "Composant d’artisanat" },
    { type = 11, price = 5, lineIndex = 2 },
} } })
assert(#rendered == 3 and rendered[2].text == "Crafting Reagent" and rendered[3].text == "Sell Price: 5|Tcoin|t",
    "Known reagent labels render without a warning")
rendered = {}
Enum.TooltipDataLineType.SpellName = 13
records[75] = {
    description = "Automatically shoots the target until cancelled.",
    sourceDescriptions = { frFR = "Attaque automatiquement la cible jusqu'à annulation." },
}
ClientApi.InstallGlobals("frFR", {"SPELL_CAST_TIME_INSTANT", "SPELL_RECAST_TIME_SEC"})
Addon:FillEnglishTooltip({ tip = tip, source = {
    GetLeftLine = function(_, index) return sourceLines[index] or sourceLines[2] end,
}, name = "Auto Shot", kind = "spell", id = 75, data = { lines = {
    { type = 13, lineIndex = 1 },
    { lineIndex = 2, leftText = "portée de 8-35 m." },
    { lineIndex = 3, leftText = "Instantané", rightText = "1,6 s de recharge" },
    { type = 34, lineIndex = 4, leftText = "Attaque automatiquement la cible jusqu'à annulation." },
} } })
assert(#rendered == 4 and rendered[2].text == "8-35 yd range" and rendered[3].text == "Instant"
    and rendered[3].right == "1.6 sec cooldown"
    and rendered[4].text == "Automatically shoots the target until cancelled.",
    "Known shared formats and typed descriptions render without a warning")
rendered = {}
Addon:FillEnglishTooltip({ tip = tip, source = {
    GetLeftLine = function(_, index) return sourceLines[index] end,
}, name = "Light Shot", kind = "item", id = 2516, data = { lines = {
    { type = 22, lineIndex = 1 },
    { type = 21, lineIndex = 2, leftText = "Projectile", rightText = "Balle" },
    { lineIndex = 3, leftText = "Ajoute 1,5 dégâts par seconde" },
} } })
assert(#rendered == 4 and rendered[2].text == "Projectile" and rendered[2].right == "Bullet"
    and rendered[3].text == "Ajoute 1,5 dégâts par seconde", "Untyped ammunition damage stays native")
rendered = {}
ClientApi.InstallGlobals("frFR", {"ITEM_SOULBOUND", "ITEM_UNIQUE"})
Addon:FillEnglishTooltip({ tip = tip, source = {
    GetLeftLine = function(_, index) return sourceLines[index] or sourceLines[2] end,
}, name = "Hearthstone", kind = "item", id = 6948, data = { lines = {
    { type = 22, lineIndex = 1 },
    { lineIndex = 2, leftText = "Lié" },
    { lineIndex = 3, leftText = "Unique" },
    { lineIndex = 4, leftText = hearthstone },
} } })
assert(#rendered == 5 and rendered[2].text == "Soulbound" and rendered[3].text == "Unique"
    and rendered[4].text == hearthstone, "Untyped item rows stay native")
ClientApi.InstallGlobals("frFR", {"ITEM_UNIQUE_EQUIPPABLE", "ITEM_UNIQUE_MULTIPLE"})
assert(row({ leftText = "Unique - Équipé" }) == "Unique-Equipped")
assert(row({ leftText = "Unique (2)" }) == "Unique (2)")
rendered = {}
Addon:FillEnglishTooltip({ tip = tip, source = {
    GetLeftLine = function(_, index) return sourceLines[index] end,
}, name = "Charged item", kind = "item", id = 2102, data = { lines = {
    { type = 22, lineIndex = 1 },
    { lineIndex = 2, leftText = "2 charges" },
} } })
assert(#rendered == 2 and rendered[2].text == "2 Charges", "Known charge labels render without a warning")
rendered = {}
Addon:FillEnglishTooltip({ tip = tip, source = {
    GetLeftLine = function(_, index) return sourceLines[index] end,
}, name = "Unknown effect", kind = "item", id = 2102, data = { lines = {
    { type = 22, lineIndex = 1 },
    { lineIndex = 2, leftText = "Un effet inconnu" },
} } })
assert(#rendered == 3 and rendered[2].text == "Un effet inconnu"
    and rendered[3].text == Addon:GetIncompleteTranslationNotice(), "Keep the warning for genuinely unknown text")
rendered = {}
Addon:FillEnglishTooltip({ tip = tip, source = {
    GetLeftLine = function(_, index) return sourceLines[index] or sourceLines[2] end,
}, name = "Numeric rows", kind = "item", id = 2102, data = { lines = {
    { type = 22, lineIndex = 1, rightText = "12/20" },
    { lineIndex = 2, leftText = "|Tcoin:16|t 1,5 – 2", rightText = "50%" },
    { lineIndex = 3, leftText = "|A:icon:16:16|a" },
} } })
assert(#rendered == 3 and rendered[1].right == "12/20" and rendered[2].right == "50%",
    "Numbers and decorative markup must not trigger the untranslated warning")
rendered = {}
Addon:FillEnglishTooltip({ tip = tip, source = {
    GetLeftLine = function(_, index) return sourceLines[index] or sourceLines[2] end,
}, name = "Unknown link", kind = "item", id = 2102, data = { lines = {
    { type = 22, lineIndex = 1 },
    { lineIndex = 2, leftText = "|Hspell:1|h[Étrange]|h" },
} } })
assert(#rendered == 3 and rendered[3].text == Addon:GetIncompleteTranslationNotice(),
    "Visible link text must retain the untranslated warning")
print("PASS: typed spell and item rows, native fallback, and secret guards")

-- Exercise recipe requirements through the same full-text renderer as live spell tooltips.
Addon.RegisterNameTooltipComponent = function() end
Addon.IsReadableEntityID = function(_, id)
    return canaccessallvalues(id) and type(id) == "number" and id > 0 and id % 1 == 0
end
assert(loadfile("ForeverRosettaStone/tooltips/components/spell-tooltip.lua"))("ForeverRosettaStone", Addon)
local recipeItems = {
    [6218] = { frFR = "Bâtonnet runique en cuivre", enUS = "Runed Copper Rod" },
    [10940] = { frFR = "Poussière étrange", enUS = "Strange Dust" },
    [800005] = { frFR = "Pioche de mineur", enUS = "Mining Pick" },
}
ForeverRosettaStoneDB.GetItemName = function(_, id, target)
    return recipeItems[id] and recipeItems[id][target]
end
Addon.GetClientLabel = function(_, key, target)
    local labels = { SPELL_TOTEMS = { enUS = "Tools: ", frFR = "Outils : " },
        SPELL_REAGENTS = { enUS = "Reagents: |n", frFR = "Composants : |n" } }
    return labels[key] and labels[key][target]
end
ClientApi.InstallGlobals("frFR", {"SPELL_TOTEMS", "SPELL_REAGENTS"})
C_Item = { GetItemInfoInstant = function(name)
    assert(name == "Bâtonnet runique en cuivre", "Only the client's recipe tool is resolved")
    error("Tool translation must not depend on the item-name cache")
end }
local previousSpellRules = ForeverRosettaStoneDB.GetSpellRules
local recipeRules = {requiredToolCategories = {800002}}
ForeverRosettaStoneDB.GetSpellRules = function(self, id)
    if id == 800001 then return recipeRules end
    return previousSpellRules(self, id)
end
local toolCategories = {
    [800002] = {frFR = "Bâtonnet runique en cuivre", enUS = "Runed Copper Rod"},
    [800004] = {frFR = "Marteau de forgeron"},
}
ForeverRosettaStoneDB.GetTotemCategoryName = function(_, id, target)
    assert(toolCategories[id], "Tool categories stay separate from item IDs")
    return toolCategories[id][target]
end
C_TradeSkillUI = {
    GetRecipeRequirements = function() error("Tool translation uses owned category IDs") end,
    GetRecipeSchematic = function(id, recraft)
        assert(id == 800001 and recraft == false, "Reagents use the displayed recipe ID")
        return {recipeID = id, reagentSlotSchematics = {{reagents = {{itemID = 10940}}}}}
    end,
}
local function recipe(body)
    rendered = {}
    local lines = {{type = 13, lineIndex = 1, leftText = "Enchantement"}}
    for _, line in ipairs(body) do line.lineIndex = #lines + 1; lines[#lines + 1] = line end
    Addon:FillEnglishTooltip({tip = tip, source = {
        GetLeftLine = function(_, index) return sourceLines[index] or sourceLines[2] end,
    }, kind = "spell", id = 800001, name = "Enchantment", data = {lines = lines}})
end
recipe({{leftText = "Outils : |cffff2020Bâtonnet runique en cuivre|r"},
    {leftText = "Composants : |n|cffff2020Poussière étrange|r (7)"}})
assert(rendered[2].text == "Tools: |cffff2020Runed Copper Rod|r", "Tool names and inline colors translate together")
assert(rendered[3].text == "Reagents: |n|cffff2020Strange Dust|r (7)", "Reagent quantity and color remain native")
assert(#rendered == 3, "Translated recipe requirements do not show an incomplete footer")
recipe({{leftText = "Composants :"}, {leftText = "Poussière étrange (3/7)"},
    {type = 34, leftText = "Description inconnue"}})
assert(rendered[2].text == "Reagents:", "Standalone reagent heading translates")
assert(rendered[3].text == "Strange Dust (3/7)", "Separate reagent rows preserve live progress")
assert(rendered[4].text == "Description inconnue", "Requirement matching leaves unknown prose native")
recipe({{leftText = "Composants : Poussière inconnue (7)"}})
assert(rendered[2].text == "Reagents: Poussière inconnue (7)", "Missing reagent names remain native")
assert(rendered[3].text == Addon:GetIncompleteTranslationNotice(), "Partial requirement translations retain the notice")
C_TradeSkillUI.GetRecipeSchematic = function() error("Recipe data unavailable") end
recipe({{leftText = "Composants : Poussière étrange (7)"}})
assert(rendered[2].text == "Reagents: Poussière étrange (7)", "Unavailable recipe data cannot guess reagent identities")
assert(rendered[3].text == Addon:GetIncompleteTranslationNotice(), "Unavailable recipe data stays visibly incomplete")
C_TradeSkillUI.GetRecipeSchematic = function() return nil end
recipeRules = {requiredToolCategories = {800002}, requiredToolItems = {800005}}
recipe({{leftText = "Outils : Bâtonnet runique en cuivre, |cffff2020Pioche de mineur|r"}})
assert(rendered[2].text == "Tools: Runed Copper Rod, |cffff2020Mining Pick|r",
    "Category and direct item tools translate together without the item cache")
assert(#rendered == 2, "Fully translated tool lists do not show an incomplete footer")
recipeRules = {requiredToolCategories = {800002, 800004}}
recipe({{leftText = "Outils : Bâtonnet runique en cuivre, Marteau de forgeron"}})
assert(rendered[2].text == "Tools: Runed Copper Rod, Marteau de forgeron",
    "A tool category without a target name remains native")
assert(rendered[3].text == Addon:GetIncompleteTranslationNotice(), "Missing tool translations stay visibly incomplete")
recipeRules = {requiredToolItems = {800006}}
recipe({{leftText = "Outils : Pioche de mineur"}})
assert(rendered[2].text == "Tools: Pioche de mineur", "Item IDs do not resolve through category names or inventory")
assert(rendered[3].text == Addon:GetIncompleteTranslationNotice(), "Unowned tool items stay visibly incomplete")
recipeRules = nil
recipe({{leftText = "Outils : Bâtonnet runique en cuivre"}})
assert(rendered[2].text == "Tools: Bâtonnet runique en cuivre", "Missing tool relations cannot guess identities by name")
assert(rendered[3].text == Addon:GetIncompleteTranslationNotice(), "Missing tool relations stay visibly incomplete")
print("PASS: recipe requirements, live quantities, inline colors and missing-data fallbacks")

-- Collection usage gates stay in the native block, as talent purchase gates do.
local ridingGate = "Requires Journeyman Riding skill"
local ridingKey = "SPELL_FAILED_JOURNEYMAN_RIDING_REQUIREMENT"
local oldLocale, oldLabel = locale, Addon.GetClientLabel
locale = "enUS"
Addon.GetClientLabel = function(_, key, target)
    if key == ridingKey and target == "enUS" then return ridingGate end
end
ForeverRosettaStoneDB.GetGlobalStringKeysByText = function(_, text, sourceLocale)
    assert(sourceLocale == "enUS", "Usage gates are matched in the client locale")
    if text == ridingGate then return {ridingKey} end
end
local function mountRows(kind, gate, right)
    rendered = {}
    Addon:FillEnglishTooltip({tip = tip, source = {
        GetLeftLine = function(_, index) return sourceLines[index] or sourceLines[2] end,
    }, kind = kind, id = 2973, name = "Translated mount", data = {lines = {
        {type = 13, leftText = "Native mount", lineIndex = 1},
        {leftText = gate, rightText = right, lineIndex = 2},
    }}})
end
mountRows("mount", "|cffff2020" .. ridingGate .. "|r")
assert(#rendered == 1, "Known riding gates are omitted without an incomplete notice")
mountRows("mount", "Requires an unknown skill")
assert(rendered[2].text == "Requires an unknown skill", "Unknown conditions retain native text")
mountRows("spell", ridingGate)
assert(rendered[2].text == ridingGate, "Ordinary spell requirements remain visible")
mountRows("mount", ridingGate, "Additional requirement")
assert(rendered[2].text == ridingGate, "A two-column row must not be consumed as a literal gate")
locale, Addon.GetClientLabel = oldLocale, oldLabel
ForeverRosettaStoneDB.GetGlobalStringKeysByText = nil
print("PASS: collection riding gates and conservative requirement fallbacks")
do
    local previousLabel = Addon.GetClientLabel
    local nativeAbbreviations = { SECONDS_ABBR = "%d s", MINUTES_ABBR = "%d min", HOURS_ABBR = "%d h" }
    local abbreviations = { SECONDS_ABBR = "%d sec", MINUTES_ABBR = "%d min", HOURS_ABBR = "%d hr" }
    Addon.GetClientLabel = function(addon, key, target)
        if target == "enUS" and abbreviations[key] then return abbreviations[key] end
        if target == "frFR" and nativeAbbreviations[key] then return nativeAbbreviations[key] end
        return previousLabel(addon, key, target)
    end
    ClientApi.InstallGlobals("frFR", {"ITEM_COOLDOWN_TIME", "SECONDS_ABBR", "MINUTES_ABBR", "HOURS_ABBR"})
    assert(row({ leftText = "Temps de recharge restant : 34 min 49 s" }) == "Cooldown remaining: 34 min 49 sec",
        "A multi-unit client clock translates each quantity")
    assert(row({ leftText = "Temps de recharge restant : 1 h 2 min 3 s" }) == "Cooldown remaining: 1 hr 2 min 3 sec",
        "Three-unit clocks translate generically")
    assert(row({ leftText = "Temps de recharge restant : 34 min inconnu" }) == nil,
        "A clock with an unknown word stays native")
    Addon.GetClientLabel = previousLabel
    ITEM_COOLDOWN_TIME, SECONDS_ABBR, MINUTES_ABBR, HOURS_ABBR = nil, nil, nil, nil
end
do
    Addon.itemClassesByLocale = { frFR = { [11] = "Carquois" }, enUS = { [11] = "Quiver" } }
    assert(row({ type = Enum.TooltipDataLineType.EquipSlot, leftText = "Carquois" }) == "Quiver",
        "The item's own class name translates through the class table")
    assert(row({ type = Enum.TooltipDataLineType.EquipSlot, leftText = "Autre" }) == nil,
        "Text that is not the item's class name stays native")
    Addon.itemClassesByLocale = nil
end
