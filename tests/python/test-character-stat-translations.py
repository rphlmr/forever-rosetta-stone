"""Replay real French character-stat tooltips through the keyed renderer."""

import json
import re
import sys
from collections import Counter
from decimal import Decimal
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import load_catalog

lua = LuaRuntime(encoding=None)
lua.execute(b'Addon = {}; canaccessallvalues = function() return true end; GetLocale = function() return "frFR" end')
load = lua.eval(b'function(path) assert(loadfile(path))("ForeverRosettaStone", Addon) end')
load(b'ForeverRosettaStone/tooltips/character-stat-formats.lua')
load(b'ForeverRosettaStone/locales/character-stat-locales.lua')
load(b'ForeverRosettaStone/tooltips/spell-live-values.lua')
load(b'ForeverRosettaStone/tooltips/tooltip-descriptions.lua')
addon = lua.globals().Addon
configuration = load_catalog(ROOT, 'quests', ids={})
authored_locales = sorted({*configuration['rosettaLocales'], 'itIT'})
english = dict(addon.characterStatFormats.enUS.items())
formats = re.compile(rb'%(?:\d+\$)?[0-9.+-]*[dscfFg]')
colors = re.compile(rb'\|[cC][0-9a-fA-F]{8}|\|[rR]')


def literal_numbers(text):
    plain = colors.sub(b'', formats.sub(b'', text)).replace(b'%%', b'')
    return Counter(Decimal(number.decode().replace(',', '.'))
                   for number in re.findall(rb'\d+(?:[.,]\d+)?', plain))


for locale in authored_locales:
    targets = dict(addon.characterStatFormats[locale.encode()].items())
    assert set(targets) == set(english), f'Incomplete stat targets: {locale}'
    for key, source in english.items():
        target = targets[key]
        assert formats.findall(source) == formats.findall(target), (locale, key, 'format arguments')
        assert colors.findall(source) == colors.findall(target), (locale, key, 'color markup')
        assert literal_numbers(source) == literal_numbers(target), (locale, key, 'literal values')

strings = {key.decode(): value.decode() for key, value in addon.characterStatFormats.frFR.items()}

for key, value in strings.items():
    lua.globals()[key.encode()] = value.encode()

fixture = json.loads((ROOT / 'tests/fixtures/character-stat-tooltips-70862.json').read_text())
failures = []
translated = []

for case in fixture['cases']:
    label = (case['label'] or '').replace('\u00a0', ' ').rstrip(': ')
    label_key = next((key for key, value in strings.items()
                      if value == label and addon.characterStatFormats.enUS[key.encode()] is not None), None)
    lines = []

    for row in case['lines']:
        output = {}

        for side in ('left', 'right'):
            if side not in row:
                continue

            result = addon.TranslateCharacterStatText(addon, row[side].encode(), b'enUS', label_key.encode() if label_key else None)

            if result is None:
                failures.append((case['label'], row[side]))
            else:
                output[side] = result.decode()

        lines.append(output)

    translated.append(lines)

assert not failures, f'Untranslated captured stat rows: {failures}'
assert translated[0][0]['left'] == '|cffffffffHealth 103|r'
assert 'Every 1 Stamina adds 10 Health' in translated[0][1]['left']
assert '25' in addon.TranslateCharacterStatText(addon, b'|cffffffffVie 25|r', b'enUS', b'HEALTH').decode()
assert addon.TranslateCharacterStatText(addon, b'Unknown future stat', b'enUS', None) is None
assert addon.TranslateCharacterStatText(addon, b'4 - 7', b'enUS', None) == b'4 - 7'
print(f'PASS: {len(translated)} captured character-stat tooltips, including five resistance schools')

for locale, formats in addon.characterStatFormats.items():
    for case in fixture['cases']:
        for row in case['lines']:
            for side in ('left', 'right'):
                if side in row:
                    result = addon.TranslateCharacterStatText(addon, row[side].encode(), locale, None)
                    assert result is not None, (locale, case['label'], row[side])

loading = LuaRuntime()
loading.execute('''
local component, loader
local hooks = 0
local addon = { TooltipSideRules = {} }
function addon:CreateTooltipPlacementProfiles(value) return value end
function addon:RegisterNameTooltipComponent(value) component = value end
GameTooltip = {}
function hooksecurefunc() hooks = hooks + 1 end
function CreateFrame()
    loader = {
        RegisterEvent = function() end,
        SetScript = function(self, _, callback) self.callback = callback end,
        UnregisterAllEvents = function(self) self.stopped = true end,
    }
    return loader
end
assert(loadfile("ForeverRosettaStone/tooltips/components/character-stat-tooltip.lua"))("ForeverRosettaStone", addon)
component.Install()
assert(hooks == 1 and loader and not loader.stopped)
loader:callback()
assert(hooks == 1 and not loader.stopped, "unrelated addon loads do not install unavailable UI hooks")
PaperDollFrame_SetLabelAndText = function() end
CharacterStatFrameScrollBoxBaseElementMixin = { Init = function() end }
loader:callback()
assert(hooks == 3 and loader.stopped, "late character UI load installs both row hooks and stops listening")
''')
print('PASS: captured stat rows across 19 target locale maps and late-loaded character UI hooks')
