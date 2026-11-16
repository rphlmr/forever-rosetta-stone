"""Decode byte-exact native cache entries, never hand-authored game templates."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/source-scan'))
from client_hotfix import spell_records, sparse_item_records, table_hash


class ClientHotfixTests(unittest.TestCase):
    def test_native_sparse_item_names_and_numeric_fields_use_the_exact_schema(self):
        capture = json.loads((ROOT / 'tests/fixtures/tooltip-campaign/native-item-hotfixes-70938.json').read_text())
        self.definition.write_text(capture['definition'])
        for locale, source in capture['caches'].items():
            with self.subTest(locale=locale):
                data = bytes.fromhex(source['byteExactSelectedEntriesHex'])
                self.cache.write_bytes(data)
                row = sparse_item_records(self.cache, self.definition, capture['build'])[286569]['fields']
                self.assertEqual(row['Display_lang'], source['expectedName'])
                self.assertEqual(row['RequiredLevel'], source['expectedLevel'])
                self.assertEqual(row['InventoryType'], source['expectedSlot'])
                self.cache.write_bytes(data[:-1])
                with self.assertRaises(ValueError):
                    sparse_item_records(self.cache, self.definition, capture['build'])

    def setUp(self):
        self.capture = json.loads((ROOT / 'tests/fixtures/tooltip-campaign/native-spell-hotfixes-70938.json').read_text())
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.cache = Path(self.temp.name) / 'cache.bin'
        self.definition = Path(self.temp.name) / 'Spell.dbd'
        self.definition.write_text(self.capture['definition'])

    def test_both_native_locales_retain_raw_formulas_and_owned_ids(self):
        self.assertEqual(table_hash('Spell'), 0xE111669E)
        for locale, capture in self.capture['caches'].items():
            with self.subTest(locale=locale):
                self.cache.write_bytes(bytes.fromhex(capture['byteExactSelectedEntriesHex']))
                rows = spell_records(self.cache, self.definition, self.capture['build'])
                self.assertEqual({str(id): r['description'] for id, r in rows.items()}, capture['expected'])
                self.assertTrue(all('${' in r['description'] for r in rows.values()))

    def test_wrong_build_schema_version_and_truncated_cache_are_rejected(self):
        data = bytes.fromhex(self.capture['caches']['enUS']['byteExactSelectedEntriesHex'])
        for altered in (data[:20], data[:-1], data[:4] + b'\0' * 4 + data[8:],
                        data[:8] + b'\0' * 4 + data[12:]):
            self.cache.write_bytes(altered)
            with self.assertRaises(ValueError):
                spell_records(self.cache, self.definition, self.capture['build'])
        self.cache.write_bytes(data)
        self.definition.write_text(self.capture['definition'].replace('Description_lang\n', 'Unknown\n'))
        with self.assertRaises(ValueError):
            spell_records(self.cache, self.definition, self.capture['build'])
