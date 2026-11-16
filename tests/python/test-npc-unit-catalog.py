"""Check source IDs and all available unit-label translations through the built database."""

import sys

from lupa.lua51 import LuaRuntime

from database_harness import ROOT, install_metadata, load_database, read_metadata

sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import load_catalog


lua = LuaRuntime(encoding=None)
install_metadata(lua, read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc'))
api = load_database(lua)
checked = 0
for kind, method in (('creaturetypes', api.GetCreatureTypeName), ('classes', api.GetClassName), ('races', api.GetRaceName)):
    records = load_catalog(ROOT, kind)['catalogs'][kind]
    for identifier, entity in records.items():
        assert 'sourceNames' not in entity
        for locale, record in entity['locales'].items():
            actual = method(api, int(identifier), locale.encode())
            expected = record.get('name')
            assert actual == (expected.encode() if expected else None), (kind, identifier, locale, actual)
            if kind == 'races':
                female = method(api, int(identifier), locale.encode(), 3)
                expected_female = record.get('nameFemale')
                assert female == (expected_female.encode() if expected_female else None)
            checked += 1
    assert method(api, 999999999, b'frFR') is None
    assert method(api, 0, b'frFR') is None
    assert method(api, -1, b'frFR') is None

assert api.GetCreatureTypeName(api, 14, b'enUS') == b'Wild Pet'
assert api.GetCreatureTypeName(api, 1, b'enUS') == b'Beast'
assert api.GetClassName(api, 1, b'enUS') == b'Warrior'
assert api.GetCreatureTypeName(api, 13, b'enUS') is None
assert api.GetClassName(api, 8, b'enUS') == b'Mage'
assert api.GetClassName(api, 6, b'enUS') is None
lua.execute(b'''
    addon = { RegisterNameTooltipComponent = function() end, GetTargetLocale = function() return 'frFR' end }
    canaccessallvalues = function() return true end
    GetLocale = function() return 'enUS' end
    Enum = { TooltipDataLineType = { UnitName = 2, UnitType = 48 } }
    UnitGUID = function() return 'Creature-0-0-0-0-823-test' end
    UnitCreatureType = function() return 'Ignored native type', 7 end
    UnitClass = function() return 'Deputy Willem', 'WARRIOR', 1 end
    UnitIsPlayer = function() return false end
    assert(loadfile('ForeverRosettaStone/database/npc-tooltip-data.lua'))('addon', addon)
    assert(loadfile('ForeverRosettaStone/tooltips/components/npc-tooltip.lua'))('addon', addon)
    local font = { GetFont = function() return 'native', 12, '' end,
        GetTextScale = function() return 1 end, GetTextColor = function() return 1, 1, 1 end }
    local source = { GetUnit = function() return 'Deputy Willem', 'nameplate1' end,
        GetLeftLine = function() return font end }
    rows = {}
    local tip = { AddLine = function(_, text) rows[#rows + 1] = text end,
        NumLines = function() return #rows end,
        GetLeftLine = function() return { SetFont = function() end, SetTextScale = function() end } end }
    addon:FillNpcTooltip({ source = source, tip = tip, id = 823, name = 'Adjoint Willem', data = {
        guid = UnitGUID(), lines = {
            { type = 2, leftText = 'Deputy Willem' },
            { type = 0, leftText = 'Level 1' },
            { type = 0, leftText = 'Stormwind' },
        },
    } })
    assert(#rows == 3, 'The owned faction must render without an incomplete warning')
    assert(rows[2] == 'Niveau 1' and rows[3] == 'Stormwind', 'Preserve the official French faction shown in-game')
''')
print(f'PASS: {checked} unit labels across all target locales, non-contiguous IDs and missing-record fallback')
