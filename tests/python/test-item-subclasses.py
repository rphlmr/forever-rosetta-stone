"""Verify shipped item subclass labels against the retained client snapshot."""

import json
from pathlib import Path

from lupa.lua51 import LuaRuntime


root = Path(__file__).resolve().parents[2]
fixture = json.loads((root / 'tests/fixtures/tooltip-item-subclasses.json').read_text(encoding='utf-8'))
lua = LuaRuntime(encoding=None)
lua.execute(b'''
local addon = {}
assert(loadfile("ForeverRosettaStone/database/item-data.lua"))(nil, addon)
assert(loadfile("ForeverRosettaStone/database/localized-item-data.lua"))(nil, addon)
TestAddon = addon
''')
maps = lua.globals().TestAddon[b'itemSubclassesByLocale']

for locale, expected in fixture['labels'].items():
    if locale in fixture['excluded']:
        assert maps[locale.encode()] is None
        assert expected == fixture['labels']['enUS']
        continue

    actual = maps[locale.encode()]
    assert actual is not None, locale
    total = sum(sum(1 for _ in subclasses.items()) for subclasses in actual.values())
    assert total == len(expected), (locale, total, len(expected))

    for key, label in expected.items():
        class_id, subclass_id = map(int, key.split(':'))
        assert actual[class_id][subclass_id].decode() == label, (locale, key)

assert maps[b'enUS'] is not None
assert maps[b'enGB'] is None

for locale in ('csCZ', 'daDK', 'hrHR', 'plPL', 'svSE', 'trTR', 'ukUA'):
    assert maps[locale.encode()] is None, locale

print('PASS: item subclass labels match the retained build 1.60.1.70862 fixture')
