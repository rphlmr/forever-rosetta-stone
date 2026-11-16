"""Verify NPC subnames through the production runtime API and tooltip translator."""

import sys

from lupa.lua51 import LuaRuntime

from database_harness import ROOT, install_metadata, load_database, read_metadata

sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import load_catalog


lua = LuaRuntime(encoding=None)
install_metadata(lua, read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc'))
api = load_database(lua)
lua.execute(b'''
    addon = {RegisterNameTooltipComponent = function() end}
    canaccessallvalues = function() return true end
    sourceLocale = 'enUS'
    GetLocale = function() return sourceLocale end
    assert(loadfile('ForeverRosettaStone/database/npc-tooltip-data.lua'))('addon', addon)
    assert(loadfile('ForeverRosettaStone/tooltips/components/npc-tooltip.lua'))('addon', addon)
''')
addon = lua.globals().addon

shipped = 0
for identifier, npc in load_catalog(ROOT, 'npcs')['catalogs']['npcs'].items():
    english = npc['locales'].get('enUS', {}).get('subName')
    for locale, record in npc['locales'].items():
        expected = record.get('subName') if english else None
        actual = api.GetNpcSubName(api, int(identifier), locale.encode())
        assert actual == (expected.encode() if expected else None), (identifier, locale, expected, actual)
        shipped += bool(expected)

# The visible client line uses ordinary spaces where Questie keeps no-break spaces.
lua.globals().sourceLocale = b'frFR'
assert addon.TranslateNpcTooltipText(addon, 'Maître des démonistes'.encode(), b'enUS', 459) == b'Warlock Trainer'
assert addon.TranslateNpcTooltipText(addon, 'Maître des démonistes'.encode(), b'deDE', 459) == \
    'Hexenmeisterlehrerin'.encode()
assert addon.TranslateNpcTooltipText(addon, 'Maître des démonistes'.encode(), b'enUS', 999999999) is None
assert addon.TranslateNpcTooltipText(addon, 'Maître des démonistes'.encode(), b'enUS') is None
lua.globals().sourceLocale = b'enUS'
assert addon.TranslateNpcTooltipText(addon, b'Warlock Trainer', b'frFR', 459) == api.GetNpcSubName(api, 459, b'frFR')
assert api.GetNpcSubName(api, 459, b'csCZ') is None, 'Missing additional-language subnames stay absent'

# Owner title lines resolve through the shipped client GlobalStrings, keeping the owner name verbatim.
lua.globals().sourceLocale = b'frFR'
assert addon.TranslateNpcTooltipText(addon, b'Familier de Dane Winslow', b'enUS', 416) == b"Dane Winslow's Pet"
assert addon.TranslateNpcTooltipText(addon, b'Totem de Dane', b'enUS', 416) == b"Dane's Totem"
lua.globals().sourceLocale = b'enUS'
assert addon.TranslateNpcTooltipText(addon, b"Arthas's Pet", b'frFR', 416) == b"Familier d'Arthas"
assert addon.TranslateNpcTooltipText(addon, b"Arthas's Pet", b'deDE', 416) == b'Begleiter von Arthas'
lua.globals().sourceLocale = b'koKR'
assert addon.TranslateNpcTooltipText(addon, 'Dane의 소환수'.encode(), b'enUS', 416) is None
print(f'PASS: {shipped} NPC subnames shipped; owned subnames and owner titles translate, unknown rows stay native')
