"""Check shared-label coverage and formatting for every configured target language.

Expected wording comes from AI-authored locale modules, so this verifies format
contracts and rendering, not linguistic accuracy or entity-description coverage.
"""

import json
import re
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import load_catalog

fixture = json.loads((ROOT / 'tests/fixtures/tooltip-client-strings.json').read_text())
locales = load_catalog(ROOT, 'quests', ids=[])['locales']
lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
lua.execute(b'''
canaccessallvalues = function() return true end
GetLocale = function() return sourceLocale end
Enum = { TooltipDataLineType = {} }
ForeverRosettaStoneDB = {
    GetItemDetails = function() return nil end,
    GetSpellDetails = function() return nil end,
}
local addon = {}
assert(loadfile("tests/fixtures/tooltip-source-api.lua"))()(ForeverRosettaStoneDB)
assert(loadfile("ForeverRosettaStone/database/item-data.lua"))("ForeverRosettaStone", addon)
assert(loadfile("ForeverRosettaStone/tooltips/english-tooltip-formats.lua"))("ForeverRosettaStone", addon)
assert(loadfile("ForeverRosettaStone/tooltips/localized-tooltip-formats.lua"))("ForeverRosettaStone", addon)
assert(loadfile("ForeverRosettaStone/database/localized-item-data.lua"))("ForeverRosettaStone", addon)
assert(loadfile("ForeverRosettaStone/tooltips/spell-live-values.lua"))("ForeverRosettaStone", addon)
assert(loadfile("ForeverRosettaStone/tooltips/tooltip-descriptions.lua"))("ForeverRosettaStone", addon)
TestAddon = addon
''')
addon = lua.globals().TestAddon

for path in sorted((ROOT / 'ForeverRosettaStone/locales/tooltips').glob('*.lua')):
    lua.execute(path.read_bytes(), b'ForeverRosettaStone', addon)

lua.execute((ROOT / 'ForeverRosettaStone/tooltips/appearance-tooltip-formats.lua').read_bytes(), b'ForeverRosettaStone', addon)

canonical = {key.decode(): value.decode() for key, value in addon.tooltipFormatsByLocale[b'enUS'].items()}
target_maps = {}


def get_arguments(template):
    arguments = re.findall(r'%(?:(\d+)\$)?[\d.]*([dscfg])', template.replace('%%', ''))

    return sorted((int(position or index), kind) for index, (position, kind) in enumerate(arguments, 1))


for locale in locales:
    target = addon.tooltipFormatsByLocale[locale.encode()]
    assert target is not None, f'Missing shared-label target map: {locale}'
    target_maps[locale] = {key.decode(): value.decode() for key, value in target.items()}
    missing = sorted(key for key, value in canonical.items() if value and not target_maps[locale].get(key))
    assert not missing, (locale, 'missing shared labels', missing)

    for key, value in canonical.items():
        if value:
            assert get_arguments(value) == get_arguments(target_maps[locale][key]), (locale, key)

    subclasses = addon.itemSubclassesByLocale[locale.encode()]
    assert subclasses is not None, f'Missing item subclass target map: {locale}'

    for class_id, entries in addon.itemSubclasses.items():
        for subclass_id, _ in entries.items():
            assert subclasses[class_id] is not None and subclasses[class_id][subclass_id], (
                locale, class_id, subclass_id)


def select_plural(forms, amount, locale):
    choices = forms.split(':')

    if len(choices) == 1:
        return choices[0]

    if len(choices) == 3:
        last, last_two = amount % 10, amount % 100

        if locale in ('ruRU', 'ukUA', 'hrHR'):
            index = 0 if last == 1 and last_two != 11 else (
                1 if 2 <= last <= 4 and not 12 <= last_two <= 14 else 2)
        elif locale == 'plPL':
            index = 0 if amount == 1 else (1 if 2 <= last <= 4 and not 12 <= last_two <= 14 else 2)
        elif locale == 'csCZ':
            index = 0 if amount == 1 else (1 if 2 <= amount <= 4 else 2)
        else:
            raise AssertionError(('Unsupported three-form target', locale, forms))
    else:
        index = 0 if amount == 1 or (amount == 0 and locale in ('frFR', 'ptBR')) else 1

    return choices[index]


def render(template, locale, amount):
    rendered = re.sub(r'\|4([^;]+);', lambda match: select_plural(match[1], amount, locale), template)
    rendered = re.sub(r'%(?:\d+\$)?[\d.]*c', '+', rendered)
    rendered = re.sub(r'%(?:\d+\$)?[\d.]*[dscfg]', str(amount), rendered)

    return rendered.replace('%%', '%')


passed = 0
empty = 0
failures = []
for source_locale in fixture['locales']:
    lua.globals().sourceLocale = source_locale.encode()
    reference_locale = source_locale

    for target_locale in locales:
        for key, english in canonical.items():
            source = fixture['strings'][key][reference_locale]

            if not source or not english:
                empty += 1
                continue

            source_resistance = fixture['strings']['RESISTANCE2_NAME'][reference_locale]
            target_resistance = target_maps[target_locale]['RESISTANCE2_NAME']
            target = target_maps[target_locale][key]
            amounts = (0, 1, 2, 5, 21) if '|4' in source or '|4' in target else (1,)

            for amount in amounts:
                native = render(source, source_locale, amount)
                expected = render(target, target_locale, amount)

                if key == 'RESISTANCE_TEMPLATE':
                    native = render(re.sub(r'%(?:\d+\$)?s', lambda _: source_resistance, source),
                                    source_locale, amount)
                    expected = render(re.sub(r'%(?:\d+\$)?s', lambda _: target_resistance, target),
                                      target_locale, amount)
                    lua.globals().RESISTANCE2_NAME = source_resistance.encode()

                lua.globals()[key.encode()] = source.encode()
                line = lua.table_from({b'leftText': native.encode()})
                result = addon.GetLocalizedTooltipLine(addon, line, b'item', 0, target_locale.encode())
                actual = result[0] if isinstance(result, tuple) else result
                lua.globals()[key.encode()] = None
                lua.globals().RESISTANCE2_NAME = None

                expected = expected.encode()
                if actual != expected:
                    failures.append((source_locale, target_locale, key, amount, actual, expected))
                else:
                    passed += 1

print(f'Rosetta label matrix: {passed} passed, {empty} empty source labels, {len(failures)} mismatches')
assert not failures, repr(failures[:12])
print(f'PASS: shared labels, argument contracts and item subclasses for {len(locales)} targets')
print('PASS: shared labels render in every target language')
print('LIMIT: AI-authored wording has not had linguistic review; entity text is a separate catalog check')
