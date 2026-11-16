local Addon = { GetTargetLocale = function() return "frFR" end,
    GetIncompleteTranslationNotice = function() return "Some lines are not translated yet." end }
Addon.RegisterNameTooltipComponent = function() end
canaccessallvalues = function(...)
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if type(value) == "table" and value.secret then return false end
    end
    return true
end
GetLocale = function() return "enUS" end
Enum = { TooltipDataLineType = { UnitName = 2, UnitType = 48 }, TooltipDataType = { Unit = 2 } }
local unit = { guid = "Creature-0-0-0-0-823-test", typeID = 900001, classID = 900002, isPlayer = false }
UnitGUID = function() return unit.guid end
UnitCreatureType = function() return "Unrecognized native type", unit.typeID end
UnitClass = function() return "Unrecognized native class", "UNRECOGNIZED", unit.classID end
UnitIsPlayer = function() return unit.isPlayer end
local typeNames, classNames = { [900001] = "Type selected by ID" }, { [900002] = "Class selected by ID" }
ForeverRosettaStoneDB = {
    GetCreatureTypeName = function(_, id) return typeNames[id] end,
    GetClassName = function(_, id) return classNames[id] end,
    GetNpcFactionID = function() end,
}
assert(loadfile("ForeverRosettaStone/database/npc-tooltip-data.lua"))("addon", Addon)
assert(loadfile("ForeverRosettaStone/tooltips/components/npc-tooltip.lua"))("addon", Addon)
local font = {
    GetFont = function() return "native", 12, "" end,
    GetTextScale = function() return 1 end,
    GetTextColor = function() return 1, 1, 1 end,
}
local source = {
    GetUnit = function() return "Ignored native name", "nameplate1" end,
    GetLeftLine = function() return font end,
}
local function render(lineType, guid, text)
    local rows = {}
    local tip = {
        AddLine = function(_, value) rows[#rows + 1] = value end,
        NumLines = function() return #rows end,
        GetLeftLine = function() return { SetFont = function() end, SetTextScale = function() end } end,
    }
    Addon:FillNpcTooltip({ tip = tip, source = source, id = 823, name = "Translated NPC",
        data = { guid = guid or unit.guid, lines = {
            { type = 2, leftText = "Native NPC" }, { type = lineType, leftText = text or "Opaque native row" },
        } } })
    return rows
end
local rows = render(48)
assert(#rows == 2 and rows[2] == "Type selected by ID", "Do not append extra unit information")
unit.isPlayer = true
rows = render(48)
assert(#rows == 2 and rows[2] == "Class selected by ID")
unit.classID = 900003
rows = render(48)
assert(#rows == 3 and rows[2] == "Opaque native row", "Missing translation keeps the native row")
unit.classID = { secret = true }
rows = render(48)
assert(#rows == 3 and rows[2] == "Opaque native row", "Restricted IDs must not be inspected")
unit.isPlayer, unit.classID = false, 900002
rows = render(48, "Creature-0-0-0-0-999-other")
assert(#rows == 3 and rows[2] == "Opaque native row", "Do not translate a recycled unit token")
-- Forever clients leave the type row untyped (type 0); identify it only by the live API's own text.
rows = render(0, nil, "Unrecognized native type")
assert(#rows == 2 and rows[2] == "Type selected by ID", "An untyped row equal to the live unit type uses its ID")
rows = render(0, nil, "Other native row")
assert(#rows == 1, "Unrecognized untyped extras stay outside the picked translation block")
unit.isPlayer = true
rows = render(0, nil, "Unrecognized native class")
assert(#rows == 2 and rows[2] == "Class selected by ID", "An untyped row equal to the live player class uses its ID")
rows = render(0, nil, "Unrecognized native type")
assert(#rows == 1, "A player never picks the creature type row")
unit.isPlayer = false
unit.typeID = nil
rows = render(48, nil, "Beast")
assert(#rows == 3 and rows[2] == "Beast", "Do not recover a missing ID by matching a known label")
unit.classID = nil
rows = render(48)
assert(#rows == 3 and rows[2] == "Opaque native row", "Missing IDs do not add rows")
source.GetUnit = nil
rows = render(48)
assert(#rows == 3 and rows[2] == "Opaque native row")
assert(Addon:TranslateNpcTooltipText("Humanoid", "frFR") == nil)

-- Dead units: the type row shows the client's CORPSE GlobalString; translate it by key.
source.GetUnit = function() return "Ignored native name", "nameplate1" end
unit.isPlayer, unit.typeID, unit.classID = false, 900001, 900002
CORPSE = "Native corpse"
local globalStrings = { CORPSE = { frFR = "Cadavre" } }
ForeverRosettaStoneDB.GetGlobalStringByKey = function(_, key, locale)
    return globalStrings[key] and globalStrings[key][locale]
end
UnitIsDead = function() return unit.isDead end
unit.isDead = true
rows = render(48, nil, "Native corpse")
assert(#rows == 2 and rows[2] == "Cadavre", "A dead unit's CORPSE row translates by key")
rows = render(0, nil, "Native corpse")
assert(#rows == 2 and rows[2] == "Cadavre", "An untyped CORPSE row of a dead unit translates by key")
rows = render(48, nil, "Opaque native row")
assert(#rows == 2 and rows[2] == "Type selected by ID", "A dead unit without the CORPSE row keeps its type path")
unit.isDead = false
rows = render(48, nil, "Native corpse")
assert(#rows == 2 and rows[2] == "Type selected by ID", "Living units never use the CORPSE label")
unit.isDead = true
globalStrings.CORPSE.frFR = nil
rows = render(48, nil, "Native corpse")
assert(#rows == 2 and rows[2] == "Type selected by ID", "A missing target CORPSE falls back to the type path")
unit.isDead, UnitIsDead, CORPSE = { secret = true }, function() return unit.isDead end, "Native corpse"
globalStrings.CORPSE.frFR = "Cadavre"
rows = render(48, nil, "Native corpse")
assert(rows[2] == "Type selected by ID", "Restricted death state is not inspected")
UnitIsDead, CORPSE = nil, nil
print("PASS: NPC type/class IDs, corpse rows by CORPSE key, arbitrary identifiers, untyped rows, stale units and missing/restricted data")
