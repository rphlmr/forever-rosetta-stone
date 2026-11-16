"""Unsupported English fields cannot enter catalogs or the shipping projection."""

import runpy
import copy
import unittest
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.catalogs.english_scope import prune_unbacked_text
from tools.build.runtime_catalog import project_localized_record, project_tooltip_details


class EnglishCatalogScopeTests(unittest.TestCase):
    def entity(self):
        return {'locales': {'enUS': {'name': 'Item'}, 'frFR': {'name': 'Objet', 'description': 'Sans source',
            'translationMetadata': {'fields': {'name': {'origin': 'original'}, 'description': {'origin': 'ai'}}}}}}

    def test_removes_only_unsupported_field_and_its_metadata(self):
        before = self.entity()
        after = prune_unbacked_text('items', before)
        self.assertEqual(after['locales']['frFR']['name'], 'Objet')
        self.assertNotIn('description', after['locales']['frFR'])
        self.assertNotIn('description', after['locales']['frFR']['translationMetadata']['fields'])
        self.assertIn('description', before['locales']['frFR'])

    def test_entity_without_english_identity_is_excluded(self):
        entity = self.entity()
        del entity['locales']['enUS']['name']
        self.assertIsNone(prune_unbacked_text('items', entity))
        self.assertIsNone(project_localized_record('items', '1', entity, 'frFR', {}))

    def test_builder_does_not_export_foreign_only_description(self):
        entity = self.entity()
        details = project_tooltip_details(entity, entity['locales']['frFR'], 'frFR')
        self.assertNotIn('description', details)
        entity['locales']['enUS']['description'] = 'English description'
        details = project_tooltip_details(entity, entity['locales']['frFR'], 'frFR')
        self.assertEqual(details['description'], 'Sans source')

    def test_official_structural_whitespace_is_not_a_missing_source(self):
        entity = self.entity()
        entity['locales']['enUS']['description'] = '\r\n\r\n'
        entity['locales']['frFR']['description'] = '\r\n\r\n'
        details = project_tooltip_details(entity, entity['locales']['frFR'], 'frFR')
        self.assertEqual(details['description'], '\r\n\r\n')

    def test_official_import_cannot_reintroduce_foreign_only_fields(self):
        fill = runpy.run_path(str(ROOT / 'tools/catalogs/fill-official-text.py'))
        after, counts = fill['update_entity'](self.entity(), [{'locale': 'deDE', 'field': 'description',
            'text': 'Beschreibung', 'english': None, 'origin': 'original',
            'provenance': '{"source":"wago","sourceLocale":"deDE"}'}])
        self.assertNotIn('description', after['locales'].get('deDE', {}))
        self.assertEqual(counts['excludedWithoutEnglishSource'], 1)

    def test_previously_prepared_foreign_queue_cannot_reintroduce_english(self):
        work = runpy.run_path(str(ROOT / 'tools/catalogs/translation-work.py'))
        source = 'Sans source'
        import json
        job_id = work['get_digest'](json.dumps(['enUS', 'items.tooltip.description', source],
                                              ensure_ascii=False, separators=(',', ':')))
        job = {'jobId': job_id, 'locale': 'enUS', 'context': 'items.tooltip.description',
               'source': source, 'sourceHash': work['get_digest'](source), 'tokens': [],
               'pointers': [{'catalog': 'items', 'kind': 'items', 'id': '1',
                             'field': 'tooltip.description', 'sourceLocale': 'frFR'}]}
        result = {'jobId': job_id, 'sourceHash': job['sourceHash'], 'translation': 'Invented English'}
        with self.assertRaisesRegex(ValueError, 'outside catalog scope'):
            work['validate_results']({'jobs': [job]}, [result], {'items': {'catalogs': {'items': {'1': self.entity()}}}})

    def test_batch_cannot_invent_english_to_retain_a_foreign_field(self):
        batch = runpy.run_path(str(ROOT / 'tools/catalogs/catalog-batch.py'))
        before = self.entity()
        before['locales']['enUS']['translationMetadata'] = {'fields': {'name': {'origin': 'original'}}}
        after = copy.deepcopy(before)
        after['locales']['enUS']['description'] = 'Invented English'
        after['locales']['enUS']['translationMetadata']['fields']['description'] = {
            'origin': 'ai', 'source': 'ForeverRosettaStoneAI', 'sourceLocale': 'frFR'}
        with self.assertRaisesRegex(ValueError, 'must not be invented'):
            batch['validate_record']('items', '1', before, after, ['enUS', 'frFR'])


if __name__ == '__main__':
    unittest.main()
