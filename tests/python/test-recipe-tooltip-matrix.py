"""Unidentified reagent rows preserve native text; typed descriptions use owned IDs."""

import json
import sys
import unittest
from pathlib import Path

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import load_catalog

FIXTURE = json.loads((ROOT / 'tests/fixtures/tooltip-client-strings.json').read_text())
ITEMS = [json.loads((ROOT / f'catalogs/items/{item_id}.json').read_text()) for item_id in (6218, 247786)]


class RecipeMatrix(unittest.TestCase):
    def test_recipe_rows(self):
        document = load_catalog(ROOT, 'quests', ids=[])
        targets = document['locales']
        sources = [locale for locale in targets if locale not in document['rosettaLocales']]
        lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
        lua.execute(b'''
            canaccessallvalues = function() return true end
            function GetLocale() return sourceLocale end
            Enum = { TooltipDataLineType = { SpellName = 1, SpellDescription = 2 } }
            ForeverRosettaStoneDB = {
                GetSpellDetails = function(_, id, locale)
                    if id == 7418 then return {description = locale == 'frFR' and 'translated' or 'native',
                        originalFields = {description = true}} end
                end,
                GetSpellRules = function() return {} end,
            }
            addon = {}
            function addon:GetTargetLocale() return targetLocale end
            for _, path in ipairs({"database/item-data", "tooltips/english-tooltip-formats",
                "tooltips/localized-tooltip-formats", "database/localized-item-data",
                "tooltips/spell-live-values", "tooltips/tooltip-descriptions"}) do
                assert(loadfile("ForeverRosettaStone/" .. path .. ".lua"))("addon", addon)
            end
            function row(line, id, target)
                return addon:GetLocalizedTooltipLine(line, 'spell', id, target)
            end
        ''')
        g = lua.globals()
        for source in sources:
            g[b'sourceLocale'] = source.encode()
            names = [item['locales'][source]['name'] for item in ITEMS]
            rows = [FIXTURE['strings']['SPELL_TOTEMS'][source] + names[0],
                    FIXTURE['strings']['SPELL_REAGENTS'][source], names[1],
                    f'|cffffffff{names[1]} (2)|r']
            for target in targets:
                for text in rows:
                    result = g[b'row'](lua.table_from({b'leftText': text.encode()}), 7418, target.encode())
                    left = result[0] if isinstance(result, tuple) else result
                    self.assertEqual(left, text.encode() if source == target else None, (source, target, text))
        g[b'sourceLocale'] = b'enUS'
        line = lua.table_from({b'type': 2, b'leftText': b'native'})
        result = g[b'row'](line, 7418, b'frFR')
        self.assertEqual(result[0] if isinstance(result, tuple) else result, b'translated')
        result = g[b'row'](line, 7419, b'frFR')
        self.assertIsNone(result[0] if isinstance(result, tuple) else result)


if __name__ == '__main__':
    unittest.main()
