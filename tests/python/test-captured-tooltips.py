"""Render sanitized native client captures into every Rosetta target language."""

import json
import re

from lupa.lua51 import LuaRuntime

from database_harness import ROOT, install_metadata, load_database, read_metadata
from matrix_classification import summarize_report


lua = LuaRuntime(encoding=None)
install_metadata(lua, read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc'))
database = load_database(lua)
fixture = json.loads((ROOT / 'tests/fixtures/captured-tooltip-70862.json').read_text())
inventory = json.loads((ROOT / 'tests/fixtures/tooltip-inventory-70862.json').read_text())
globals_fixture = json.loads((ROOT / 'tests/fixtures/tooltip-client-strings.json').read_text())

for key, values in globals_fixture['strings'].items():
    if values.get('frFR'):
        lua.globals()[key.encode()] = values['frFR'].encode()

enum = lua.table_from({name.encode(): index for index, name in enumerate(inventory['line_types'])})
lua.globals().Enum = lua.table_from({b'TooltipDataLineType': enum})
lua.execute(b'''
canaccessallvalues = function() return true end
GetLocale = function() return "frFR" end
InRepairMode = function() return false end
GameTooltipMoneyFormat = {}
MoneyFormatterUtil = { FormatMoney = function(amount) return amount .. "|Tcoin|t" end }
HIGHLIGHT_FONT_COLOR = { r = 1, g = 1, b = 1 }
local addon = { RegisterNameTooltipComponent = function() end }
for _, path in ipairs({ "database/item-data.lua", "tooltips/english-tooltip-formats.lua", "tooltips/localized-tooltip-formats.lua",
    "database/localized-item-data.lua",
    "database/npc-tooltip-data.lua", "tooltips/components/npc-tooltip.lua", "tooltips/spell-live-values.lua", "tooltips/spell-live-values.lua", "tooltips/tooltip-descriptions.lua" }) do
    assert(loadfile("ForeverRosettaStone/" .. path))("ForeverRosettaStone", addon)
end
AddonUnderTest = addon
C_Item = { GetItemSubClassInfo = function(classID, subclassID)
    return addon.itemSubclassesByLocale.frFR[classID][subclassID]
end }
local font = {
    GetFont = function() return "native", 12, "" end,
    GetTextScale = function() return 1 end,
    GetTextColor = function() return 1, 1, 1 end,
}
RenderCapture = function(kind, id, name, target, data)
    local rendered = {}
    local function add(left, right)
        rendered[#rendered + 1] = { left = left, right = right,
            SetFont = function() end, SetTextScale = function() end }
    end
    local tip = {
        AddLine = function(_, left) add(left) end,
        AddDoubleLine = function(_, left, right) add(left, right) end,
        NumLines = function() return #rendered end,
        GetLeftLine = function(_, index) return rendered[index] end,
    }
    addon.GetTargetLocale = function() return target end
    addon:FillEnglishTooltip({ tip = tip, source = { GetLeftLine = function() return font end },
        kind = kind, id = id, name = name, data = data })
    return rendered
end
''')
addon = lua.globals().AddonUnderTest

for path in sorted((ROOT / 'ForeverRosettaStone/locales/tooltips').glob('*.lua')):
    lua.execute(path.read_bytes(), b'ForeverRosettaStone', addon)

# Target overrides must follow custom locale modules, matching the addon manifest.
for name in ('tooltips/appearance-tooltip-formats.lua', 'tooltips/tooltip-extra-formats.lua'):
    lua.execute((ROOT / 'ForeverRosettaStone' / name).read_bytes(), b'ForeverRosettaStone', addon)


def to_lua(value):
    if isinstance(value, dict):
        return lua.table_from({key.encode(): to_lua(child) for key, child in value.items()})

    if isinstance(value, list):
        return lua.table_from([to_lua(child) for child in value])

    return value.encode() if isinstance(value, str) else value


getters = {'item': database.GetItemName, 'spell': database.GetSpellName, 'npc': database.GetNpcName}


def label(locale, key, *values):
    template = addon.tooltipFormatsByLocale[locale][key.encode()].decode()
    index = 0

    def replace(match):
        nonlocal index
        index += 1
        return str(values[int(match[1] or index) - 1])

    return re.sub(r'%(?:(\d+)\$)?[\d.]*[dsgf]', replace, template).encode()


passed = 0
failures = []
cases = 0

for capture_index, case in enumerate(fixture['cases'], 1):
    for locale in sorted(database.GetLocales(database)):
        title = getters[case['kind']](database, case['id'], locale)
        assert title, (case['kind'], case['id'], locale, 'Missing target name')
        lines = lua.globals().RenderCapture(case['kind'].encode(), case['id'], title, locale, to_lua(case['data']))
        context = (case['kind'], case['id'], locale.decode())
        cases += 1
        assert lines[1][b'left'] == title, context

        native_count = len(case['data']['lines'])
        warning = any(line[b'left'] == 'Certaines lignes ne sont pas encore traduites.'.encode() for line in lines.values())
        assert len(lines) == native_count + int(warning), context
        if warning:
            failures.append({'entityKind': case['kind'], 'id': case['id'], 'locale': locale.decode(),
                             'field': 'wholeTooltip', 'surface': 'capture.' + str(capture_index),
                             'reason': 'nativeFallback',
                             'expectationDiagnostic': {'category': 'test_limitation',
                                                       'code': 'captured_tooltip_incomplete'},
                             'expectedPreview': 'Complete translation without a missing-translation warning',
                             'actualPreview': 'Some lines are not translated yet.'})

        if case['kind'] == 'npc':
            assert b'55' in lines[2][b'left'], context
            faction_id = database.GetNpcFactionID(database, case['id'])
            expected_faction = database.GetFactionName(database, faction_id, locale)
            assert lines[3][b'left'] == expected_faction, context
            assert lines[4][b'left'] == addon.npcTooltipData[locale][b'pvp'], context
        elif case['kind'] == 'item':
            details = database.GetItemDetails(database, case['id'], b'enUS')
            expected = addon.itemSubclassesByLocale[locale][details[b'classID']][details[b'subclassID']]
            assert lines[2][b'right'] == expected, context
            assert lines[2][b'left'] == label(locale, 'INVTYPE_LEGS'), context
            armor = re.search(r'\d+', case['data']['lines'][2]['leftText'])[0]
            assert lines[3][b'left'] == label(locale, 'ARMOR_TEMPLATE', armor), context
            durability = re.findall(r'\d+', case['data']['lines'][3]['leftText'])
            assert lines[4][b'left'] == label(locale, 'DURABILITY_TEMPLATE', *durability), context
        else:
            assert b'8-35' in lines[2][b'left'], context
            assert lines[2][b'left'] == label(locale, 'SPELL_RANGE', '8-35'), context
            assert lines[3][b'left'] in (label(locale, 'SPELL_CAST_TIME_INSTANT'),
                                        label(locale, 'SPELL_CAST_TIME_INSTANT_NO_MANA')), context
            cooldown = lines[3][b'right']
            assert b'1.6' in cooldown or b'1,6' in cooldown, context
            target = database.GetSpellDetails(database, case['id'], locale)
            assert target and lines[4][b'left'] == target[b'description'], context

        passed += int(not warning)

assert cases == len(fixture['cases']) * len(list(database.GetLocales(database)))
report = {'kind': 'captured_tooltips', 'counts': {'cases': cases, 'passed': passed, 'failed': len(failures)},
          'failures': failures}
report['diagnostics'] = summarize_report(report)
output = ROOT / 'datasources/imports/translation-matrix/captured-tooltips.json'
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'Captured tooltip completeness: {passed}/{cases}; {len(failures)} incomplete; report: {output}')
assert not failures, 'Captured in-game tooltips still contain missing translations; see ' + str(output)
