local Addon = {}
local definition
Addon.RegisterNameTooltipComponent = function(_, component) definition = component end
canaccessallvalues = function(...)
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if type(value) == "table" and value.secret then return false end
    end
    return true
end
Enum = { TooltipDataType = { Unit = 1 }, TooltipDataLineType = { UnitName = 2, UnitLevel = 47, UnitType = 48 } }
local sourceLocale = "frFR"
GetLocale = function() return sourceLocale end
assert(loadfile("ForeverRosettaStone/database/npc-tooltip-data.lua"))("ForeverRosettaStone", Addon)
local factionID = 47
local factionSources = { frFR = { [47] = "Forgefer" }, zhCN = { [24] = "狼人" } }
local factionTargets = { enUS = { [47] = "Ironforge", [24] = "Worgen" }, esMX = { [47] = "Forjaz" } }
ForeverRosettaStoneDB = {
    GetNpcFactionID = function() return factionID end,
    GetFactionSourceName = function() error("Untyped rows must not look up source faction names") end,
    GetFactionName = function(_, id, locale)
        return factionSources[locale] and factionSources[locale][id]
            or factionTargets[locale] and factionTargets[locale][id]
    end,
}
assert(loadfile("ForeverRosettaStone/tooltips/components/npc-tooltip.lua"))("ForeverRosettaStone", Addon)
assert(loadfile("ForeverRosettaStone/tooltips/spell-live-values.lua"))("ForeverRosettaStone", Addon)
assert(loadfile("ForeverRosettaStone/tooltips/tooltip-descriptions.lua"))("ForeverRosettaStone", Addon)
assert(definition.supportsFullText)
assert(definition.ResolveData(nil, { type = 1, guid = "Creature-0-0-0-0-721-123" }) == 721)
assert(definition.ResolveData(nil, { type = 1, guid = "Player-0-0-0-0-721-123" }) == nil)
assert(definition.ResolveData(nil, { type = 1, guid = { secret = true } }) == nil)

local target = "enUS"
Addon.GetTargetLocale = function() return target end
local font = {
    GetFont = function() return "native", 12, "" end,
    GetTextScale = function() return 0.9 end,
    GetTextColor = function() return 1, 1, 1 end,
}
local function render(rows)
    local rendered = {}
    local function add(left, right, red, green, blue)
        local line = { left = left, right = right, color = { red, green, blue } }
        line.SetFont = function(_, name, size, flags) line.font = { name, size, flags } end
        line.SetTextScale = function(_, scale) line.scale = scale end
        rendered[#rendered + 1] = line
    end
    local tip = {
        AddLine = function(_, left, red, green, blue) add(left, nil, red, green, blue) end,
        AddDoubleLine = function(_, left, right, red, green, blue) add(left, right, red, green, blue) end,
        NumLines = function() return #rendered end,
        GetLeftLine = function(_, index) return rendered[index] end,
    }
    Addon:FillEnglishTooltip({ tip = tip, source = { GetLeftLine = function() return font end },
        kind = "npc", id = 721, name = "Rabbit", data = { lines = rows } })
    return rendered
end

local rabbit = render({
    { type = 2, leftText = "Lapin" },
    { type = 47, leftText = "Bestiole niveau 1", leftColor = { r = 0.2, g = 0.7, b = 0.3 } },
})
assert(#rabbit == 3 and rabbit[1].left == "Rabbit" and rabbit[2].left == "Bestiole niveau 1")
assert(rabbit[2].color[1] == 0.2 and rabbit[2].color[2] == 0.7 and rabbit[2].scale == 0.9)
local guard = render({
    { type = 2, leftText = "Montagnard" }, { type = 47, leftText = "Niveau 55" },
    { leftText = "Forgefer" }, { leftText = "JcJ" },
})
assert(guard[2].left == "Level 55" and guard[3].left == "Ironforge" and guard[4].left == "PvP")
target = "esMX"
guard = render({
    { type = 2 }, { type = 47, leftText = "Humanoïde élite niveau 55" }, { leftText = "Forgefer" }, { leftText = "JcJ" },
})
assert(guard[2].left == "Humanoïde élite niveau 55" and guard[3].left == "Forjaz" and guard[4].left == "JcJ")
local unknown = render({ { type = 2 }, { leftText = "Rôle inconnu" }, { leftText = { secret = true } } })
assert(#unknown == 3 and unknown[2].left == "Rôle inconnu" and unknown[3].left == Addon:GetIncompleteTranslationNotice())
sourceLocale, target = "zhCN", "enUS"
factionID = 24
local visibleFaction = render({ { type = 2 }, { leftText = "狼人" } })
assert(visibleFaction[2].left == "Worgen")
factionSources.zhCN[900001] = "未审阅的冲突"
factionSources.zhCN[900002] = "未审阅的冲突"
factionTargets.enUS[900001] = "First faction"
factionTargets.enUS[900002] = "Second faction"
factionID = 900001
local ambiguousFaction = render({ { type = 2 }, { leftText = "未审阅的冲突" } })
assert(ambiguousFaction[2].left == "First faction",
    "The NPC-owned faction ID disambiguates factions with identical source names")
factionID = nil
ambiguousFaction = render({ { type = 2 }, { leftText = "未审阅的冲突" } })
assert(#ambiguousFaction == 3 and ambiguousFaction[2].left == "未审阅的冲突")
sourceLocale, target = "frFR", "esMX"
local titleSubtext = render({ { type = 2, rightText = "Sous-titre inconnu" } })
assert(#titleSubtext == 2 and titleSubtext[1].right == "Sous-titre inconnu"
    and titleSubtext[2].left == Addon:GetIncompleteTranslationNotice())
local restrictedColor = render({ { type = 2 }, { type = 47, leftText = "Niveau 55", leftColor = { secret = true } } })
assert(#restrictedColor == 2 and restrictedColor[2].color[1] == 1)
for _, locale in ipairs({ "enUS", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU",
    "zhCN", "zhTW", "csCZ", "daDK", "hrHR", "plPL", "svSE", "trTR", "ukUA" }) do
    target = locale
    local output = render({ { type = 2 }, { type = 47, leftText = "Bestiole niveau 1" }, { type = 47, leftText = "Niveau 55" } })
    assert(output[2].left == "Bestiole niveau 1" and output[3].left:find("55", 1, true), locale)
end
sourceLocale, target = "ptBR", "enUS"
local portuguese = render({ { type = 2 }, { type = 47, leftText = "Bicho Nível 8" } })
assert(#portuguese == 3 and portuguese[2].left == "Bicho Nível 8")
sourceLocale, target = "zhTW", "enUS"
local chinese = render({ { type = 2 }, { type = 47, leftText = "等級55精英人型生物" } })
assert(#chinese == 3 and chinese[2].left == "等級55精英人型生物")
local sources = { "enUS", "frFR", "deDE", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }
local targets = { "enUS", "frFR", "deDE", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW",
    "csCZ", "daDK", "hrHR", "plPL", "svSE", "trTR", "ukUA" }
local function formatType(format, number, name)
    local index = 0
    return (format:gsub("%%(%d*%$?)([ds])", function(position, kind)
        index = index + 1
        local argument = tonumber(position:match("^(%d+)%$")) or index
        return argument == 1 and number or name
    end))
end
for _, source in ipairs(sources) do
    sourceLocale = source
    local sourceInfo = Addon.npcTooltipData[Addon.npcTooltipSourceLocales[source] or source]
    for _, locale in ipairs(targets) do
        target = locale
        local targetInfo = Addon.npcTooltipData[locale]
        local native = formatType(sourceInfo.formats[1], "55")
        local expected = formatType(targetInfo.formats[1], "55")
        assert(Addon:TranslateNpcTooltipText(native, locale) == expected, source .. " -> " .. locale)
    end
end
-- Newer clients append the classification to the level row: "Niveau 61 (Élite)".
sourceLocale = "frFR"
assert(Addon:TranslateNpcTooltipText("Niveau 61 (Élite)", "enUS") == "Level 61 (Elite)")
assert(Addon:TranslateNpcTooltipText("Niveau 61 (Boss)", "enUS") == "Level 61 (Boss)")
assert(Addon:TranslateNpcTooltipText("Niveau 61 (Inconnu)", "enUS") == nil)
print("PASS: NPC whole tooltips and " .. (#sources * #targets) .. " source/target pairs; live levels, categories, faction, PvP and unknown rows")
