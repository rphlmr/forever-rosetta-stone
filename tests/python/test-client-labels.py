"""Guard the readable client-label inventory and translations across client locales."""

import hashlib
import json
import re
import unittest
from pathlib import Path

from lupa.lua51 import LuaRuntime
from database_harness import ROOT, install_metadata, load_database, read_metadata
import sys
sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import load_catalog
from tools.build.runtime_catalog import decode_client_escapes


class ClientLabelTests(unittest.TestCase):
    def test_cold_item_hover_never_scans_or_decodes_the_label_inventory(self):
        lua = LuaRuntime(encoding=None)
        lua.execute(b'''
            sourceLocale = 'frFR'
            GetLocale = function() return sourceLocale end
            canaccessallvalues = function() return true end
            debugprofilestop = function() return os.clock() * 1000 end
            Enum = {TooltipDataLineType = {}}
            addon = {itemTooltipLabels = {}, itemSubclasses = {}}
        ''')
        addon = lua.globals().addon
        for name in ('database/item-data', 'tooltips/english-tooltip-formats',
                     'tooltips/localized-tooltip-formats', 'database/localized-item-data'):
            lua.execute((ROOT / ('ForeverRosettaStone/' + name + '.lua')).read_bytes(), b'addon', addon)
        native = json.loads((ROOT / 'tests/fixtures/tooltip-client-strings.json').read_text())['strings']
        for key, values in native.items():
            if 'frFR' in values:
                lua.globals()[key.encode()] = values['frFR'].encode()
        install_metadata(lua, read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc'))
        api = load_database(lua)
        for name in ('tooltips/client-labels', 'tooltips/tooltip-descriptions'):
            lua.execute((ROOT / ('ForeverRosettaStone/' + name + '.lua')).read_bytes(), b'addon', addon)
        lua.execute(b'''
            ForeverRosettaStoneDB.GetGlobalStrings = function() error('Bulk label load during hover') end
            ForeverRosettaStoneDB.GetGlobalStringKeys = function() error('Full label inventory scan during hover') end
        ''')
        # Literals outside the adapter keys resolve through the per-locale text pages.
        # (Avoid U+00E0 here: macOS Python's UTF-8 ctype makes Lua's %s match its 0xA0 byte.)
        lua.globals()[b'SPELL_FAILED_APPRENTICE_RIDING_REQUIREMENT'] = \
            'Nécessite la compétence Apprenti cavalier.'.encode()
        api.StartProfiling(api)
        for native_text, expected in (
            ('Lié quand ramassé', 'Binds when picked up'), ('Deux mains', 'Two-Hand'),
            ('Dégâts : 36 - 55', '36 - 55 Damage'), ('Vitesse 3,50', 'Speed 3.50'),
            ('+6 Force', '+6 Strength'), ('+1 Endurance', '+1 Stamina'),
            ('Nécessite la compétence Apprenti cavalier.', 'Requires Apprentice Riding skill'),
        ):
            line = lua.table_from({b'type': 0, b'leftText': native_text.encode()})
            result = addon.GetEnglishTooltipLine(addon, lua.table(), line, b'item', 5626)
            actual = result[0] if isinstance(result, tuple) else result
            self.assertEqual(actual, expected.encode())
        profile = api.StopProfiling(api)
        self.assertLess(profile[b'decodes'], 40, 'Only candidate key pages and their target records may decode')
        self.assertLess(profile[b'decodedBytes'], 200_000, 'A cold hover must not expand the complete inventory')
        self.assertIsNone(api.GetGlobalStringByKey(api, b'FRS_NONEXISTENT_LABEL', b'enUS'))

    @classmethod
    def setUpClass(cls):
        cls.fixture = json.loads((ROOT / 'tests/fixtures/client-label-source-inventory.json').read_text())
        # Both inventory assertions can reuse the same read-only source snapshot.
        cls.entities = load_catalog(ROOT, 'globalstrings')['catalogs']['globalstrings']
        cls.lua = LuaRuntime(encoding=None)
        cls.lua.execute(b'''
            canaccessallvalues = function() return true end
            GetLocale = function() return sourceLocale end
            Enum = {TooltipDataLineType = {UsageRequirement = 43}}
            ForeverRosettaStoneDB = {GetItemRules = function() return nil end}
            addon = {itemTooltipLabels = {}, itemSubclasses = {}}
        ''')
        cls.addon = cls.lua.globals().addon
        for name in ('database/item-data', 'tooltips/english-tooltip-formats', 'tooltips/localized-tooltip-formats',
                     'database/localized-item-data'):
            cls.lua.execute((ROOT / ('ForeverRosettaStone/' + name + '.lua')).read_bytes(), b'addon', cls.addon)
        for path in sorted((ROOT / 'ForeverRosettaStone/locales/tooltips').glob('*.lua')):
            cls.lua.execute(path.read_bytes(), b'addon', cls.addon)
        install_metadata(cls.lua, read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc'))
        load_database(cls.lua)
        cls.lua.execute((ROOT / 'ForeverRosettaStone/tooltips/client-labels.lua').read_bytes(), b'addon', cls.addon)
        cls.lua.execute((ROOT / 'ForeverRosettaStone/tooltips/tooltip-descriptions.lua').read_bytes(), b'addon', cls.addon)

    def test_every_official_source_text_is_imported_without_loss(self):
        entities = self.entities
        keys = {r['key'] for r in entities.values()}
        for locale, evidence in self.fixture['official'].items():
            values = self.addon.GetClientLabels(self.addon, locale.encode())
            actual = {key.decode(): value.decode() for key, value in values.items()}
            # Owned text keeps the export's Lua escapes; the shipped label is what the client shows.
            expected = {r['key']: decode_client_escapes(r['locales'][locale]['name']) for r in entities.values()
                        if r['key'] in keys and r['locales'].get('enUS', {}).get('name')
                        and isinstance(r['locales'].get(locale, {}).get('name'), str)}
            self.assertEqual(actual, expected, locale)

    def test_every_owned_globalstring_key_is_exported_from_the_json_catalog(self):
        api = self.lua.globals().ForeverRosettaStoneDB
        keys = sorted(key.decode() for key in api.GetGlobalStringKeys(api).keys())
        self.assertEqual(set(keys), {r['key'] for r in self.entities.values()})
        self.assertIn('WARDROBE_TOOLTIP_TRANSMOGRIFIER', keys)
        self.assertIn('LARGE_NUMBER_SEPERATOR', keys)
        self.assertFalse((ROOT / 'ForeverRosettaStone/locales/client-labels').exists())

    def test_shared_formats_resolve_repeated_captures_once_per_row(self):
        self.lua.globals().sourceLocale = b'frFR'
        self.lua.eval(b'function(values) for key, value in pairs(values) do _G[key] = value end end')(
            self.addon.GetClientLabels(self.addon, b'frFR'))
        original = self.addon.TranslateClientLabel
        counts = {}

        def translate(addon, text, locale, context=None):
            key = (text, context)
            counts[key] = counts.get(key, 0) + 1
            return original(addon, text, locale, context)

        self.addon.TranslateClientLabel = translate
        try:
            for value in ('3,50', '2,80'):
                counts.clear()
                line = self.lua.table_from({b'type': 0, b'leftText': ('Vitesse ' + value).encode()})
                result = self.addon.GetEnglishTooltipLine(self.addon, self.lua.table(), line, b'item', 0)
                actual = result[0] if isinstance(result, tuple) else result
                self.assertEqual(actual, ('Speed ' + value.replace(',', '.')).encode())
                self.assertLessEqual(counts.get((value.encode(), None), 0), 1,
                                 'Competing shared formats must reuse capture resolution within a row')
        finally:
            self.addon.TranslateClientLabel = original

    def test_item_refresh_reuses_shared_text_and_tracks_changed_values(self):
        self.lua.globals().sourceLocale = b'frFR'
        self.lua.eval(b'function(values) for key, value in pairs(values) do _G[key] = value end end')(
            self.addon.GetClientLabels(self.addon, b'frFR'))
        original = self.addon.TranslateClientLabel
        calls = []

        def translate(addon, text, locale, context=None):
            calls.append(text)
            return original(addon, text, locale, context)

        cache = self.lua.table()
        self.addon.TranslateClientLabel = translate
        try:
            def render(text):
                line = self.lua.table_from({b'type': 0, b'leftText': text})
                result = self.addon.GetEnglishTooltipLine(self.addon, self.lua.table(), line, b'item', 0, cache)
                return result[0] if isinstance(result, tuple) else result

            self.assertEqual(render(b'Vitesse 3,50'), b'Speed 3.50')
            calls.clear()
            for _ in range(10):
                self.assertEqual(render(b'Vitesse 3,50'), b'Speed 3.50')
            self.assertEqual(calls, [], 'Unchanged native refreshes must not repeat shared format matching')
            self.assertEqual(render(b'Vitesse 2,80'), b'Speed 2.80')
            self.assertTrue(calls, 'Changed displayed values must be translated again')
            calls.clear()
            self.lua.globals().sourceLocale = b'deDE'
            render(b'Vitesse 2,80')
            self.assertTrue(calls, 'A client locale change invalidates the shared text cache')
        finally:
            self.addon.TranslateClientLabel = original

    def test_profession_requirements_work_from_every_official_client_to_every_target(self):
        item = json.loads((ROOT / 'catalogs/items/279968.json').read_text())
        category_id = item['tooltipData']['requirements']['skillCategoryID']
        category = json.loads((ROOT / f'catalogs/professioncategories/{category_id}.json').read_text())
        targets = ['csCZ', 'daDK', 'deDE', 'enUS', 'esES', 'esMX', 'frFR', 'hrHR', 'itIT',
                   'koKR', 'plPL', 'ptBR', 'ruRU', 'svSE', 'trTR', 'ukUA', 'zhCN', 'zhTW']
        install = self.lua.eval(b'''function(values)
            for key, value in pairs(values) do _G[key] = value end
        end''')
        def formatted(template, label):
            index = 0
            def substitute(match):
                nonlocal index
                index += 1
                position = int(match[1]) if match[1] else index
                return label if position == 1 else '20'
            return re.sub(r'%(?:(\d+)\$)?[sd]', substitute, template)
        for source in self.fixture['official']:
            self.lua.globals().sourceLocale = source.encode()
            install(self.addon.GetClientLabels(self.addon, source.encode()))
            source_text = self.fixture['professionFormats'][source]
            native = formatted(source_text['ITEM_MIN_SKILL'], category['locales'][source]['name'])
            line = self.lua.table_from({b'type': 43, b'leftText': native.encode()})
            for target in targets:
                with self.subTest(source=source, target=target):
                    # Item restrictions use the item's owned profession category, whose
                    # source wording can differ from the general interface label.
                    label = category['locales'][target]['name']
                    template = self.addon.GetClientLabel(self.addon, b'ITEM_MIN_SKILL', target.encode()).decode()
                    expected = formatted(template, label)
                    result = self.addon.GetLocalizedTooltipLine(self.addon, line, b'item', 279968, target.encode())
                    actual = result[0] if isinstance(result, tuple) else result
                    self.assertEqual(actual, expected.encode())


if __name__ == '__main__':
    unittest.main()
