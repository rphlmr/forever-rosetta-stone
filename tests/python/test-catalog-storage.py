"""Verify independent entity access with inline field metadata."""

import json
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import dump_json, get_entity_path, load_catalog, load_entity, read_json


class CatalogStorageTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        metadata = {'origin': 'ai', 'source': 'ForeverRosettaStoneAI', 'sourceLocale': 'frFR'}
        self.document = {
            'schemaVersion': 1,
            'locales': ['enUS', 'frFR'],
            'catalogs': {'items': {
                '1': {'locales': {
                    'enUS': {'name': 'Sword $s1', 'translationMetadata': {'fields': {'name': metadata}}},
                    'frFR': {'name': 'Épée $s1', 'translationMetadata': {'fields': {'name': metadata}}},
                }, 'tooltipData': {'sourceNames': {'frFR': 'Épée native'}}},
                '2': {'locales': {'enUS': {
                    'name': 'Shield', 'translationMetadata': {'fields': {'name': metadata}},
                }}},
            }},
        }
        self.write_catalog('items', self.document)

    def write_catalog(self, catalog, document):
        directory = self.root / 'catalogs' / catalog
        directory.mkdir(parents=True)
        manifest = {'storageVersion': 2, 'kinds': sorted(document['catalogs']),
                    'document': {key: value for key, value in document.items() if key != 'catalogs'}}
        (directory / 'metadata.json').write_text(dump_json(manifest), encoding='utf-8')

        for kind, rows in document['catalogs'].items():
            (self.root / 'catalogs' / kind).mkdir(exist_ok=True)

            for entity_id, entity in rows.items():
                get_entity_path(self.root, kind, entity_id).write_text(dump_json(entity), encoding='utf-8')

    def test_inline_records_roundtrip_without_shared_profiles(self):
        self.assertEqual(load_catalog(self.root, 'items'), self.document)
        entity = load_entity(self.root, 'items', '1')
        stored = json.loads(get_entity_path(self.root, 'items', '1').read_bytes())
        self.assertEqual(entity, stored)
        self.assertIsInstance(stored['locales']['frFR']['translationMetadata']['fields']['name'], dict)
        entity['locales']['frFR']['translationMetadata']['fields']['name']['origin'] = 'original'
        self.assertEqual(load_entity(self.root, 'items', '1'), stored)

    def test_duplicate_entity_fields_are_rejected_in_selected_and_full_reads(self):
        path = get_entity_path(self.root, 'items', '1')
        path.write_text('{"locales":{"frFR":{"description":"Cast", "description":"Aura"}}}', encoding='utf-8')

        with self.assertRaisesRegex(ValueError, "Duplicate JSON key 'description'"):
            load_entity(self.root, 'items', '1')

        with self.assertRaisesRegex(ValueError, "Duplicate JSON key 'description'"):
            load_catalog(self.root, 'items')

    def test_duplicate_metadata_is_not_silently_overwritten(self):
        path = self.root / 'submission.json'
        path.write_text('{"metadata":{"origin":"original", "origin":"ai"}}', encoding='utf-8')

        with self.assertRaisesRegex(ValueError, "Duplicate JSON key 'origin'"):
            read_json(path)

    def test_selected_reads_do_not_read_other_entities_and_metadata_reads_no_entities(self):
        original_read = Path.read_bytes
        reads = []

        def read_selected(path):
            reads.append(path)
            self.assertNotEqual(path.name, '2.json', 'Selected read opened an unrelated entity')

            return original_read(path)

        with patch.object(Path, 'read_bytes', read_selected):
            selected = load_catalog(self.root, 'items', ids={'items': ['1', '999']})

        self.assertEqual(selected['catalogs']['items'], {'1': self.document['catalogs']['items']['1']})
        self.assertIn(get_entity_path(self.root, 'items', '1'), reads)
        reads.clear()

        with patch.object(Path, 'read_bytes', read_selected):
            metadata_only = load_catalog(self.root, 'items', ids={})

        self.assertEqual(metadata_only['catalogs'], {'items': {}})
        self.assertEqual(metadata_only['locales'], self.document['locales'])
        self.assertEqual([path.name for path in reads], ['metadata.json'])
        self.assertIsNone(load_entity(self.root, 'items', '999'))

    def test_ids_and_kinds_cannot_escape_catalog_paths(self):
        for entity_id in ('../1', '0', '-1', '01', '1/2', 'metadata', ''):
            with self.subTest(entity_id=entity_id), self.assertRaises(ValueError):
                get_entity_path(self.root, 'items', entity_id)

        for kind in ('../items', 'unknown', ''):
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                get_entity_path(self.root, kind, '1')

        with self.assertRaises(ValueError):
            load_catalog(self.root, '../items')

    def test_area_and_map_ids_remain_distinct(self):
        document = {
            'schemaVersion': 1,
            'localeAliases': {'enGB': 'enUS'},
            'catalogs': {
                'areas': {'1': {'locales': {'enUS': {'name': 'Area one'}}}},
                'maps': {'1': {'locales': {'enUS': {'name': 'Map one'}}}},
            },
        }
        self.write_catalog('areas', document)
        self.assertEqual(load_catalog(self.root, 'areas'), document)
        self.assertEqual(load_entity(self.root, 'areas', '1')['locales']['enUS']['name'], 'Area one')
        self.assertEqual(load_entity(self.root, 'maps', '1')['locales']['enUS']['name'], 'Map one')
        selected = load_catalog(self.root, 'areas', ids={'maps': ['1']})
        self.assertEqual(selected['catalogs']['areas'], {})
        self.assertEqual(selected['catalogs']['maps'], document['catalogs']['maps'])


if __name__ == '__main__':
    unittest.main()
