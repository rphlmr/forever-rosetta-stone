"""Require weapon-speed label translations in every configured target language."""

import json
import sys
import unittest
from pathlib import Path

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import load_catalog
from catalog_placeholder_matrix import signature

FIXTURE = json.loads((ROOT / 'tests/fixtures/tooltip-client-strings.json').read_text())


class ItemSpeedMatrix(unittest.TestCase):
    def test_speed_labels_exist_in_every_language(self):
        locales = load_catalog(ROOT, 'quests', ids={})['locales']
        lua = LuaRuntime(encoding=None)
        lua.execute(b'addon = { itemTooltipLabels = {} }')
        addon = lua.globals().addon
        for path in ('database/item-data.lua', 'tooltips/english-tooltip-formats.lua',
                     'tooltips/localized-tooltip-formats.lua', 'database/localized-item-data.lua'):
            lua.execute((ROOT / 'ForeverRosettaStone' / path).read_bytes(), b'addon', addon)
        for path in sorted((ROOT / 'ForeverRosettaStone/locales/tooltips').glob('*.lua')):
            lua.execute(path.read_bytes(), b'addon', addon)
        for locale in locales:
            translations = addon.tooltipFormatsByLocale[locale.encode()]
            self.assertIsNotNone(translations, f'Missing label map: {locale}')
            for key in ('SPEED', 'WEAPON_SPEED'):
                with self.subTest(locale=locale, key=key):
                    value = translations[key.encode()]
                    self.assertTrue(value and value.strip(), f'Missing {key} label: {locale}')
                    expected = FIXTURE['strings'][key].get(locale)
                    # The pinned Italian client strings are English fallback; authored Italian is checked for presence.
                    if expected and locale != 'itIT':
                        self.assertEqual(value.decode(), expected)
                    self.assertEqual(signature(value.decode(), 'items'),
                                     signature(FIXTURE['strings'][key]['enUS'], 'items'))


if __name__ == '__main__':
    unittest.main()
