"""Render shipped items whose localized text records are absent."""

import json
from lupa.lua51 import LuaRuntime
from database_harness import ROOT, install_metadata, load_database, read_metadata


lua = LuaRuntime(encoding=None)
install_metadata(lua, read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc'))
database = load_database(lua)
fixture = json.loads((ROOT / 'tests/fixtures/tooltip-client-strings.json').read_text())
source_strings = {key: value['frFR'] for key, value in fixture['strings'].items() if value.get('frFR')}

for key, value in source_strings.items():
    lua.globals()[key.encode()] = value.encode()

lua.execute(b'''
canaccessallvalues = function() return true end
GetLocale = function() return "frFR" end
Enum = { TooltipDataLineType = { ItemName = 22, EquipSlot = 21, SellPrice = 11 } }
GameTooltipMoneyFormat = {}
MoneyFormatterUtil = { FormatMoney = function(amount) return amount .. "|Tcoin|t" end }
HIGHLIGHT_FONT_COLOR = { r = 1, g = 1, b = 1 }
local addon = {}
for _, path in ipairs({ "database/item-data.lua", "tooltips/english-tooltip-formats.lua", "tooltips/localized-tooltip-formats.lua",
    "database/localized-item-data.lua", "tooltips/spell-live-values.lua", "tooltips/tooltip-descriptions.lua" }) do
    assert(loadfile("ForeverRosettaStone/" .. path))("ForeverRosettaStone", addon)
end
AddonUnderTest = addon
''')
addon = lua.globals().AddonUnderTest

for path in sorted((ROOT / 'ForeverRosettaStone/locales/tooltips').glob('*.lua')):
    lua.execute(path.read_bytes(), b'ForeverRosettaStone', addon)

lua.execute(b'''
local addon = AddonUnderTest
local font = {
    GetFont = function() return "native", 12, "" end,
    GetTextScale = function() return 1 end,
    GetTextColor = function() return 0.7, 0.6, 0.5 end,
}
local target
addon.GetTargetLocale = function() return target end
local function render(id, subclass, price)
    local lines = {}
    local function add(left, right, red, green, blue)
        lines[#lines + 1] = { left = left, right = right, color = { red, green, blue },
            SetFont = function() end, SetTextScale = function() end }
    end
    local tip = {
        AddLine = function(_, left, red, green, blue) add(left, nil, red, green, blue) end,
        AddDoubleLine = function(_, left, right, red, green, blue) add(left, right, red, green, blue) end,
        NumLines = function() return #lines end,
        GetLeftLine = function(_, index) return lines[index] end,
    }
    local bodyFont = setmetatable({ GetTextColor = function() return 0.25, 0.5, 0.75 end }, { __index = font })
    addon:FillEnglishTooltip({ tip = tip, source = {
        GetLeftLine = function(_, index) return index == 2 and bodyFont or font end,
    },
        kind = "item", id = id, name = "Target title", data = { lines = {
            { type = 22, lineIndex = 1 },
            { type = 21, lineIndex = 2, leftText = INVTYPE_LEGS, rightText = subclass,
                leftColor = { r = 0.25, g = 0.5, b = 0.75 } },
            { type = 11, lineIndex = 2, price = price },
        } } })
    return lines
end
CheckItem = function(locale, id, sourceSubclass, expectedSubclass, expectedLegs)
    target = locale
    local lines = render(id, sourceSubclass, 17)
    local expectedCount = 3
    assert(#lines == expectedCount, locale .. " item " .. id .. ": expected " .. expectedCount .. " lines, got " .. #lines)
    assert(lines[1].left == "Target title")
    assert(lines[2].left == expectedLegs and lines[2].right == expectedSubclass,
        locale .. " item " .. id .. ": " .. tostring(lines[2].left) .. " / " .. tostring(lines[2].right))
    assert(lines[2].color[1] == 0.25 and lines[2].color[2] == 0.5 and lines[2].color[3] == 0.75)
    assert(lines[3].left:find("17|Tcoin|t", 1, true), "Preserve live sell price")
    assert(lines[3].color[1] == 1 and lines[3].color[2] == 1 and lines[3].color[3] == 1)
end
CheckCollision = function()
    local getSpellDetails = ForeverRosettaStoneDB.GetSpellDetails
    ForeverRosettaStoneDB.GetSpellDetails = function() return { classID = 4, subclassID = 1 } end
    target = "esMX"
    local lines = render(987654321, "Tissu", 17)
    ForeverRosettaStoneDB.GetSpellDetails = getSpellDetails
    assert(lines[2].right == "Tissu" and #lines == 4, "Missing items must not use same-ID spell structure")
end
''')

locales = sorted(database.GetLocales(database))

for item_id, subclass_id, native in [(147, 1, 'Tissu'), (2654, 3, 'Mailles')]:
    details = database.GetItemDetails(database, item_id, b'enUS')
    assert details[b'classID'] == 4 and details[b'subclassID'] == subclass_id
    assert database.GetItemDetails(database, item_id, b'esMX') is None

    for locale in locales:
        expected_subclass = addon.itemSubclassesByLocale[locale][4][subclass_id]
        if locale == b'esMX':
            assert expected_subclass == (b'Tela' if subclass_id == 1 else b'Malla')
        expected_legs = addon.tooltipFormatsByLocale[locale][b'INVTYPE_LEGS']
        lua.globals().CheckItem(locale, item_id, native.encode(), expected_subclass, expected_legs)

lua.globals().CheckCollision()
lua.execute(b'GetLocale = function() return "enUS" end')
native = database.GetItemDetails(database, 273530, b'enUS')[b'nameDescription']
target = database.GetItemDetails(database, 273530, b'frFR')[b'nameDescription']
line = lua.table_from({b'leftText': native})
translated = addon.GetLocalizedTooltipLine(addon, line, b'item', 273530, b'frFR')
translated = translated[0] if isinstance(translated, tuple) else translated
assert target and translated is None, f'Untyped item name description should not be inferred: {translated!r}'
assert line[b'leftText'] == native, 'Native item name description changed'
english = addon.GetEnglishTooltipLine(addon, None, line, b'item', 273530)
english = english[0] if isinstance(english, tuple) else english
assert english == native, 'English target should retain the native enUS description'
print(f'PASS: {len(locales) * 2} real-item whole tooltips and missing-item/spell-ID collision')
