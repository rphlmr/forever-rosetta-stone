"""Verify catalog faction names and NPC relationships through the production runtime API."""

import json
import sys

from lupa.lua51 import LuaRuntime

from database_harness import ROOT, install_metadata, load_database, read_metadata

sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import load_catalog


fixture = json.loads((ROOT / 'tests/fixtures/npc-factions-70862.json').read_text())
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
names = 0
targets_by_id = load_catalog(ROOT, 'factions')['catalogs']['factions']
for identifier, faction in targets_by_id.items():
    for locale, record in faction['locales'].items():
        expected = record['name']
        actual = api.GetFactionName(api, int(identifier), locale.encode())
        assert actual == expected.encode(), (identifier, locale, expected, actual)
        names += 1

npcs = load_catalog(ROOT, 'npcs')['catalogs']['npcs']
representatives = {}
relationships = 0
for identifier, npc in npcs.items():
    expected = npc.get('factionId')
    assert api.GetNpcFactionID(api, int(identifier)) == expected, identifier
    if expected:
        representatives.setdefault(str(expected), int(identifier))
        relationships += 1

cases = 0
for source, records in fixture['sources'].items():
    lua.globals().sourceLocale = source.encode()
    for identifier, npc_id in representatives.items():
        native = records.get(identifier)
        if not native:
            continue
        metadata = targets_by_id[identifier]['locales'].get(source, {}).get(
            'translationMetadata', {}
        ).get('fields', {}).get('name', {})
        if metadata.get('origin') == 'ai' or metadata.get('sourceLocale') != source:
            continue
        available = api.GetFactionName(api, int(identifier), source.encode())
        if available is None:
            continue
        assert available == native.encode(), (identifier, source, available, native)
        target = b'deDE' if source == 'frFR' else b'frFR'
        assert addon.TranslateNpcTooltipText(addon, native.encode(), target, npc_id) == api.GetFactionName(
            api, int(identifier), target), (identifier, source)
        cases += 1

lua.globals().sourceLocale = b'enUS'
assert api.GetNpcFactionID(api, 823) == 72
assert api.GetFactionName(api, 72, b'frFR') == b'Stormwind', 'The official French faction is not the city name Hurlevent'
assert api.GetFactionName(api, 47, b'frFR') == b'Forgefer'
assert addon.TranslateNpcTooltipText(addon, b'Stormwind', b'frFR', 823) == api.GetFactionName(api, 72, b'frFR')
assert addon.TranslateNpcTooltipText(addon, b'Stormwind', b'frFR', 999999999) is None
assert addon.TranslateNpcTooltipText(addon, b'Ironforge', b'frFR', 823) is None
assert api.GetNpcFactionID(api, 0) is None
assert api.GetFactionName(api, 999999999, b'frFR') is None
print(f'PASS: {names} faction names, {relationships} NPC relationships, {cases} native fixture rows; '
      'owned faction identities translate and unknown IDs stay unresolved')
