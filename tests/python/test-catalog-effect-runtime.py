"""Verify source-confirmed effect links survive the shipped database projection."""

import json
import unittest

from lupa.lua51 import LuaRuntime
from database_harness import ROOT, install_metadata, load_database, read_metadata


class CatalogEffectRuntimeTests(unittest.TestCase):
    def test_repaired_bindings_and_all_target_descriptions_are_exported(self):
        fixture = json.loads((ROOT / 'tests/fixtures/catalog-effect-bindings-70938.json').read_text())
        lua = LuaRuntime(encoding=None)
        install_metadata(lua, read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc'))
        api = load_database(lua)
        for binding in fixture['bindings']:
            with self.subTest(item=binding['item'], spell=binding['spell']):
                rules = api.GetItemRules(api, binding['item'])
                self.assertIsNotNone(rules)
                effects = [effect for _, effect in rules[b'effects'].items()
                           if effect[b'slot'] == binding['slot']]
                self.assertEqual(len(effects), 1)
                self.assertEqual(effects[0][b'spellID'], binding['spell'])
                self.assertEqual(effects[0][b'triggerType'], binding['trigger'])
        for id in sorted({binding['spell'] for binding in fixture['bindings']}):
            for locale in fixture['locales']:
                with self.subTest(spell=id, locale=locale):
                    details = api.GetSpellDetails(api, id, locale.encode())
                    self.assertIsNotNone(details)
                    self.assertTrue(details[b'description'])


if __name__ == '__main__':
    unittest.main()
