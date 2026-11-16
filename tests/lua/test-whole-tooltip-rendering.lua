-- IDs select owned templates; readable native values are captured, never recalculated.
local ClientApi = assert(loadfile("tests/lua/support/client-api-fixture.lua"))()
local Addon = { itemTooltipLabels = {} }
local sourceLocale, targetLocale = "frFR", "enUS"
GetLocale = function() return sourceLocale end
canaccessallvalues = function(...)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if type(value) == "table" and value.secret then return false end
    end
    return true
end
Enum = { TooltipDataLineType = { ItemName = 1, SpellName = 2, EquipSlot = 3, SellPrice = 4,
    SpellDescription = 5, ItemSpellTriggerOnUse = 6, FlavorText = 7 } }
local spellText = {
    [42] = { enUS = { description = "Restores $s1 health.", rank = "Rank 2" },
        frFR = { description = "Rend $s1 points de vie.", rank = "Rang 2" },
        deDE = { description = "Stellt $s1 Gesundheit wieder her." } },
    [43] = { enUS = { description = "Value: $1." } },
    [44] = { enUS = { description = "Languages:$?s668[\n$@spellname668][]$?s672[\n$@spellname672][]" } },
}
spellText[44].frFR = {description = "Langues :$?s668[\n$@spellname668][]$?s672[\n$@spellname672][]"}
spellText[44].enUS.description = "Languages:$?s668[ |cffffffff$@spellname668|r][]$?s672[ |cffffffff$@spellname672|r][]"
for _, record in pairs(spellText) do
    for _, localized in pairs(record) do localized.originalFields = {description = true} end
end
local itemRules = { [1] = { effects = { { triggerType = 0, spellID = 42 } } } }
ForeverRosettaStoneDB = {
    GetSpellRules = function() error("Descriptions must not read static spell rules") end,
    GetSpellDetails = function(_, id, locale) return spellText[id] and spellText[id][locale] end,
    GetSpellName = function(_, id, locale)
        local names = { [668] = { enUS = "Common", frFR = "Commun" }, [672] = { enUS = "Dwarven", frFR = "Nain" } }
        return names[id] and names[id][locale]
    end,
    GetItemRules = function(_, id) return itemRules[id] end,
    GetItemDetails = function(_, id, locale)
        if id == 1 and locale == "enUS" then return { description = "A useful item." } end
    end,
}
ClientApi.InstallGlobals("frFR", {"ITEM_SPELL_TRIGGER_ONUSE"})
C_SpellBook = { IsSpellKnown = function() return true end }
GameTooltipMoneyFormat = {}
MoneyFormatterUtil = { FormatMoney = function(value) return value .. "|Tcoin|t" end }
HIGHLIGHT_FONT_COLOR = { r = 1, g = 1, b = 1 }
assert(loadfile("ForeverRosettaStone/tooltips/spell-live-values.lua"))("ForeverRosettaStone", Addon)
assert(loadfile("ForeverRosettaStone/tooltips/tooltip-descriptions.lua"))("ForeverRosettaStone", Addon)
assert(loadfile("ForeverRosettaStone/tooltips/english-tooltip-formats.lua"))("ForeverRosettaStone", Addon)
assert(loadfile("ForeverRosettaStone/tooltips/localized-tooltip-formats.lua"))("ForeverRosettaStone", Addon)
Addon.GetTargetLocale = function() return targetLocale end
Addon.itemSubclasses = {}
local font = { GetFont = function() return "native", 12, "" end,
    GetTextScale = function() return 1 end, GetTextColor = function() return 1, 1, 1 end }
local function render(kind, id, rows, repairCost, nativeLines, nativeRightLines)
    local output = {}
    local function add(left, right, r, g, b, rr, rg, rb)
        local line = { left = left, right = right, color = { r, g, b }, rightColor = { rr, rg, rb } }
        line.SetFont = function(_, ...) line.font = { ... } end
        line.SetTextScale = function(_, scale) line.scale = scale end
        output[#output + 1] = line
    end
    local tip = { AddLine = function(_, left, ...) add(left, nil, ...) end,
        AddDoubleLine = function(_, left, right, ...) add(left, right, ...) end,
        NumLines = function() return #output end, GetLeftLine = function(_, i) return output[i] end }
    local source = { GetLeftLine = function(_, i) return nativeLines and nativeLines[i] or font end,
        GetRightLine = function(_, i) return nativeRightLines and nativeRightLines[i] end }
    Addon:FillEnglishTooltip({ tip = tip, source = source,
        kind = kind, id = id, name = "Test", data = { lines = rows, repairCost = repairCost } })
    return output
end
local function expect(label, actual, expected)
    assert(#actual == #expected, label .. ": expected " .. #expected .. " rows, got " .. #actual)
    for i, row in ipairs(expected) do
        assert(actual[i].left == row[1] and actual[i].right == row[2], label .. " row " .. i
            .. ": " .. tostring(actual[i].left) .. " / " .. tostring(actual[i].right))
    end
end

expect("structured spell", render("spell", 42, {
    { type = 2, rightText = "Rang 2" }, { type = 5, leftText = "Rend 17 points de vie." },
}), { { "Test", "Rank 2" }, { "Restores 17 health." } })
expect("structured item effect", render("item", 1, {
    { type = 1 }, { type = 6, spellID = 42, leftText = "Utiliser : Rend 17 points de vie." },
}), { { "Test" }, { "Use: Restores 17 health." } })
expect("item flavor by ID", render("item", 1, {
    { type = 1 }, { type = 7, leftText = "Texte natif" },
}), { { "Test" }, { "A useful item." } })
-- Toy rows carry no trigger type or spell ID: bind through the single owned on-use effect.
expect("untyped on-use row binds to the owned effect", render("item", 1, {
    { type = 1 }, { leftText = "Utiliser : Rend 35 points de vie." },
}), { { "Test" }, { "Use: Restores 35 health." } })
itemRules[2] = { effects = { { triggerType = 0, spellID = 42 }, { triggerType = 0, spellID = 43 } } }
expect("ambiguous untyped on-use row stays native", render("item", 2, {
    { type = 1 }, { leftText = "Utiliser : Rend 35 points de vie." },
}), { { "Test" }, { "Utiliser : Rend 35 points de vie." }, { Addon:GetIncompleteTranslationNotice() } })
local nativeTitle = { GetFont = font.GetFont, GetTextScale = font.GetTextScale, GetTextColor = font.GetTextColor,
    GetText = function() return "Nom natif" end }
expect("untyped native name row is the title", render("spell", 42, {
    { type = 0, leftText = "Nom natif" }, { type = 5, leftText = "Rend 17 points de vie." },
}, nil, { nativeTitle }), { { "Test" }, { "Restores 17 health." } })
expect("toy name row is the title", render("item", 1, {
    { type = 20, leftText = "Nom natif" }, { type = 21, leftText = "Utiliser : Rend 17 points de vie." },
}, nil, { nativeTitle }), { { "Test" }, { "Use: Restores 17 health." } })
expect("missing spell link stays native", render("item", 1, {
    { type = 1 }, { type = 6, spellID = 99, leftText = "Effet inconnu" },
}), { { "Test" }, { "Effet inconnu" }, { Addon:GetIncompleteTranslationNotice() } })
expect("restricted spell link stays native", render("item", 1, {
    { type = 1 }, { type = 6, spellID = { secret = true }, leftText = "Effet restreint" },
}), { { "Test" }, { "Effet restreint" }, { Addon:GetIncompleteTranslationNotice() } })
expect("opaque formula stays native", render("spell", 43, {
    { type = 2 }, { type = 5, leftText = "Valeur : 12,5." },
}), { { "Test" }, { "Valeur : 12,5." }, { Addon:GetIncompleteTranslationNotice() } })
expect("unknown rows produce one warning", render("item", 1, {
    { type = 1 }, { leftText = "Effet inconnu", rightText = "Valeur inconnue" },
    { leftText = "Autre inconnu" }, { leftText = { secret = true } },
}), { { "Test" }, { "Effet inconnu", "Valeur inconnue" }, { "Autre inconnu" },
    { Addon:GetIncompleteTranslationNotice() } })
local function styled(name, scale, r, g, b)
    return { GetFont = function() return name, 14, "OUTLINE" end,
        GetTextScale = function() return scale end, GetTextColor = function() return r, g, b end }
end
local white = styled("title-font", 0.9, 1, 1, 1)
local yellow = styled("body-font", 0.8, 1, 0.82, 0)
local gray = styled("right-font", 0.7, 0.5, 0.5, 0.5)
local styledOutput = render("spell", 42, {
    { type = 2, lineIndex = 1, rightText = "Rang 2", rightColor = { r = 1, g = 0, b = 0 } },
    { type = 5, lineIndex = 2, leftText = "Rend 17 points de vie.", leftColor = { r = 1, g = 0, b = 0 } },
}, nil, { white, yellow }, { gray, gray })
assert(#styledOutput == 2 and styledOutput[2].left == "Restores 17 health.")
assert(styledOutput[1].font[1] == "title-font" and styledOutput[1].scale == 0.9)
assert(styledOutput[1].rightColor[1] == 0.5 and styledOutput[2].color[2] == 0.82,
    "Native title right and body colors take precedence over tooltip metadata")
assert(styledOutput[2].font[1] == "body-font" and styledOutput[2].font[2] == 14
    and styledOutput[2].font[3] == "OUTLINE" and styledOutput[2].scale == 0.8,
    "Translated rows retain native font and scale")
local multiline = render("spell", 44, {
    { type = 2, lineIndex = 1 },
    { type = 5, lineIndex = 2, leftText = "Langues :\r\n|cffffffffCommun|r\r\n|cffffffffNain|r" },
}, nil, { white, yellow })
assert(multiline[2].left == "Languages: |cffffffffCommon|r |cffffffffDwarven|r",
    "Captured multiline lists retain the owned target colors")
expect("unknown title subtext", render("spell", 42, {
    { type = 2, rightText = "Sous-titre inconnu" },
}), { { "Test", "Rank 2" } })
targetLocale = "deDE"
expect("localized structured spell", render("spell", 42, {
    { type = 2 }, { type = 5, leftText = "Rend 17 points de vie." },
}), { { "Test" }, { "Stellt 17 Gesundheit wieder her." } })
targetLocale = "itIT"
expect("missing target stays native", render("spell", 42, {
    { type = 2 }, { type = 5, leftText = "Rend 35 points de vie." },
}), { { "Test" }, { "Rend 35 points de vie." }, { Addon:GetIncompleteTranslationNotice() } })
sourceLocale, targetLocale = "enUS", "enUS"
expect("native source retained", render("item", 1, {
    { type = 1 }, { leftText = "Unrecognized native text" }, { type = 4, price = 5 },
}), { { "Test" }, { "Unrecognized native text" }, { "Sell Price: 5|Tcoin|t" } })
assert(loadfile("ForeverRosettaStone/database/localized-item-data.lua"))("ForeverRosettaStone", Addon)
for _, name in ipairs({ "cs-cz", "da-dk", "hr-hr", "it-it", "pl-pl", "sv-se", "tr-tr", "uk-ua" }) do
    assert(loadfile("ForeverRosettaStone/locales/tooltips/" .. name .. ".lua"))("ForeverRosettaStone", Addon)
end
assert(loadfile("ForeverRosettaStone/tooltips/tooltip-extra-formats.lua"))("ForeverRosettaStone", Addon)
local repairMode = true
InRepairMode = function() return repairMode end
NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 }
sourceLocale = "enUS"
local priceCases = 0
for locale, formats in pairs(Addon.tooltipFormatsByLocale) do
    targetLocale = locale
    local output = render("item", 1, { { type = 1 }, { type = 4, price = 5 } })
    local label = formats.SELL_PRICE:gsub("%s+$", "")
    if label:sub(-1) ~= ":" and label:sub(-3) ~= "：" then label = label .. ":" end
    assert(#output == 2 and output[2].left == label .. " 5|Tcoin|t", locale .. " sale price")
    output = render("item", 1, { { type = 1 }, { type = 4, price = 5, maxPrice = 20 } }, 7)
    assert(#output == 6, locale .. " missing sale range or repair rows")
    assert(output[2].left == label)
    assert(output[3].left == "    " .. formats.MINIMUM .. ": 5|Tcoin|t")
    assert(output[4].left == "    " .. formats.MAXIMUM .. ": 20|Tcoin|t")
    assert(output[5].left == formats.REPAIR_COST and output[6].left == "7|Tcoin|t")
    assert(formats.MAP_TOOLTIP_TIME_LEFT:find("%s", 1, true), locale)
    repairMode = false
    output = render("item", 1, { { type = 1 }, { type = 4, price = 5, maxPrice = 0 } }, 7)
    assert(#output == 2 and output[2].left == label .. " 5|Tcoin|t", locale .. " repair mode off")
    repairMode = true
    priceCases = priceCases + 1
end
assert(priceCases == 18, "Expected supported locales without enGB")
print("PASS: whole tooltip structured rendering and native fallbacks")
