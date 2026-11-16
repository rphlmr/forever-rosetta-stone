"""Exercise isolated assignments, optimistic conflicts, and validated agent submissions."""

import copy
import json
import runpy
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
work = runpy.run_path(str(ROOT / 'tools/catalogs/catalog-batch.py'))


def create_item(name='Sword $s1'):
    return {'locales': {
        'enUS': {'name': name, 'translationMetadata': {'fields': {'name': {
            'origin': 'original', 'source': 'fixture', 'sourceLocale': 'enUS'}}}},
        'frFR': {'name': 'Épée $s1', 'translationMetadata': {'fields': {'name': {
            'origin': 'ai', 'source': 'fixture', 'sourceLocale': 'enUS'}}}},
    }}


class CatalogBatchTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.records = {'items': {'1': create_item(), '2': create_item(), '3': create_item()}}
        self.config = {'locales': ['enUS', 'frFR']}
        self.globals = work['prepare_batches'].__globals__
        self.patches = patch.dict(self.globals, {
            'load_catalog': self.load_catalog,
            'get_entity_path': lambda root, kind, entity_id: root / 'catalogs' / kind / (entity_id + '.json'),
            'dump_json': lambda value: json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + '\n',
        })
        self.patches.start()
        self.addCleanup(self.patches.stop)

    def load_catalog(self, root, catalog, ids=None):
        document = copy.deepcopy(self.config)
        document['catalogs'] = {
            kind: {entity_id: copy.deepcopy(self.records.get(kind, {}).get(entity_id))
                   for entity_id in entity_ids if entity_id in self.records.get(kind, {})}
            for kind, entity_ids in (ids or {}).items()
        }

        return document

    def prepare(self, scope=None):
        return work['prepare_batches'](self.root, scope or {'items': ['1']}, 1)

    def test_batches_are_disjoint_deterministic_and_include_all_locales(self):
        batches = self.prepare({'items': ['3', '1', '2']})
        self.assertEqual(batches, self.prepare({'items': ['1', '2', '3']}))
        self.assertEqual([list(batch['records']['items']) for batch in batches], [['1'], ['2'], ['3']])
        self.assertEqual(set(batches[0]['records']['items']['1']['locales']), {'enUS', 'frFR'})

    def test_cli_rejects_duplicate_result_fields_before_validation(self):
        batch = self.prepare()[0]
        batch_path = self.root / 'batch.json'
        results_path = self.root / 'results.json'
        batch_path.write_text(json.dumps(batch, ensure_ascii=False), encoding='utf-8')
        results = json.dumps(batch['records'], ensure_ascii=False)
        marker = '"name": "Épée $s1"'
        self.assertIn(marker, results)
        results_path.write_text(results.replace(marker, '"name": "Wrong $s1", ' + marker), encoding='utf-8')
        command = ['catalog-batch.py', '--root', str(self.root), 'check',
                   '--batch', str(batch_path), '--results', str(results_path)]

        with patch.object(sys, 'argv', command), self.assertRaisesRegex(ValueError, "Duplicate JSON key 'name'"):
            work['main']()

    def test_ai_sources_can_use_owned_native_templates_without_copying_source_fields(self):
        self.config['locales'].append('deDE')
        for field, source_map in (('description', 'sourceDescriptions'),
                                  ('auraDescription', 'sourceAuraDescriptions')):
            with self.subTest(field=field):
                before = create_item()
                before['locales']['enUS'][field] = 'Reduces speed by $s1%.'
                before['locales']['enUS']['translationMetadata']['fields'][field] = {
                    'origin': 'original', 'source': 'wowClient', 'sourceLocale': 'enUS'}
                before['locales']['deDE'] = {field: 'Verringert das Tempo um $s1%.',
                    'translationMetadata': {'fields': {field: {
                        'origin': 'original', 'source': 'wowClient', 'sourceLocale': 'deDE',
                    }}}}
                after = copy.deepcopy(before)
                after['locales']['frFR'][field] = 'Réduit la vitesse de $s1%.'
                after['locales']['frFR']['translationMetadata']['fields'][field] = {
                    'origin': 'ai', 'source': 'ForeverRosettaStoneAI', 'sourceLocale': 'deDE'}
                original = copy.deepcopy(before)
                work['validate_record']('spells', '1', before, after, self.config['locales'])
                self.assertEqual(before, original)
                self.assertEqual(after['locales']['deDE'], before['locales']['deDE'])

                after['locales']['frFR'][field] = 'Réduit la vitesse de $s2%.'
                with self.assertRaisesRegex(ValueError, 'Placeholder mismatch'):
                    work['validate_record']('spells', '1', before, after, self.config['locales'])

                after['locales']['frFR'][field] = 'Réduit la vitesse de $s1%.'
                after['locales']['deDE'].pop(field)
                with self.assertRaisesRegex(ValueError, 'preserve existing text fields'):
                    work['validate_record']('spells', '1', before, after, self.config['locales'])

    def test_rejects_invalid_scope_duplicate_ids_and_nonpositive_batch_size(self):
        for scope in ({'unknown': ['1']}, {'items': ['../1']}, {'items': ['0']}, {'items': [1]},
                      {'items': ['1', '1']}, {'items': []}, {}):
            with self.subTest(scope=scope), self.assertRaises(ValueError):
                work['prepare_batches'](self.root, scope, 1)

        with self.assertRaisesRegex(ValueError, 'positive'):
            work['prepare_batches'](self.root, {'items': ['1']}, 0)

    def test_rejects_extra_or_missing_results(self):
        batch = self.prepare()[0]

        for results in ({}, {'items': {}}, {'items': {'1': create_item(), '2': create_item()}},
                        {'items': {'1': create_item()}, 'spells': {}}):
            with self.subTest(results=results), self.assertRaises(ValueError):
                work['validate_batch'](self.root, batch, results)

    def test_rejects_stale_entity_but_accepts_unrelated_record_changes(self):
        batch = self.prepare()[0]
        results = copy.deepcopy(batch['records'])
        self.records['items']['2']['locales']['enUS']['name'] = 'Unrelated change'
        work['validate_batch'](self.root, batch, results)
        self.records['items']['1']['locales']['enUS']['name'] = 'Concurrent change'

        with self.assertRaisesRegex(ValueError, 'record changed'):
            work['validate_batch'](self.root, batch, results)

    def test_rejects_modified_snapshot_and_locale_configuration(self):
        batch = self.prepare()[0]
        results = copy.deepcopy(batch['records'])
        modified = copy.deepcopy(batch)
        modified['records']['items']['1']['locales']['enUS']['name'] = 'Changed assignment'

        with self.assertRaisesRegex(ValueError, 'snapshot changed'):
            work['validate_batch'](self.root, modified, results)

        self.config['locales'].append('deDE')

        with self.assertRaisesRegex(ValueError, 'locale configuration changed'):
            work['validate_batch'](self.root, batch, results)

    def test_checks_changed_ai_placeholders_and_field_origin(self):
        batch = self.prepare()[0]
        results = copy.deepcopy(batch['records'])
        translated = results['items']['1']['locales']['frFR']
        translated['name'] = 'Nouvelle épée $s2'

        with self.assertRaisesRegex(ValueError, 'Placeholder mismatch'):
            work['validate_batch'](self.root, batch, results)

        translated['name'] = 'Nouvelle épée $s1'
        work['validate_batch'](self.root, batch, results)
        del translated['translationMetadata']

        with self.assertRaises(ValueError):
            work['validate_batch'](self.root, batch, results)

    def test_quest_literal_gender_controls_preserve_value_tokens(self):
        original = {'locales': {'enUS': {'summary': 'Hello {name}', 'translationMetadata': {'fields': {'summary': {'origin': 'original', 'source': 'fixture'}}}},
                                'frFR': {'summary': 'Bonjour {name}', 'translationMetadata': {'fields': {'summary': {'origin': 'ai', 'source': 'ForeverRosettaStoneAI', 'sourceLocale': 'enUS'}}}}}}
        updated = copy.deepcopy(original)
        field = updated['locales']['frFR']
        field['translationMetadata']['fields']['summary'] = {'origin': 'ai', 'source': 'ForeverRosettaStoneAI', 'sourceLocale': 'enUS'}
        field['summary'] = 'Bonjour $gami:amie; {name}'
        work['validate_record']('quests', '1', original, updated, ['enUS', 'frFR'])
        for text in ('Bonjour $gami:amie;', 'Bonjour $gami$s1:amie; {name}', 'Bonjour $gami:amie {name}'):
            field['summary'] = text
            with self.subTest(text=text), self.assertRaises(ValueError):
                work['validate_record']('quests', '1', original, updated, ['enUS', 'frFR'])

    def test_new_records_require_coverage_and_detect_concurrent_addition(self):
        batch = self.prepare({'items': ['4']})[0]
        self.assertIsNone(batch['records']['items']['4'])
        results = {'items': {'4': create_item()}}
        patch_text = work['create_patch'](self.root, batch, results)
        self.assertIn('*** Add File: ' + str(self.root / 'catalogs/items/4.json'), patch_text)
        self.assertNotIn('metadata.json', patch_text)
        incomplete = copy.deepcopy(results)
        del incomplete['items']['4']['locales']['frFR']

        with self.assertRaisesRegex(ValueError, 'locale coverage'):
            work['validate_batch'](self.root, batch, incomplete)

        self.records['items']['4'] = create_item()

        with self.assertRaisesRegex(ValueError, 'record changed'):
            work['validate_batch'](self.root, batch, results)

    def test_target_correction_requires_english_and_cannot_delete_text(self):
        self.records['items']['1']['locales'].pop('enUS')
        self.records['items']['1']['locales']['frFR']['translationMetadata']['fields']['name']['origin'] = 'original'
        batch = self.prepare()[0]
        results = copy.deepcopy(batch['records'])
        results['items']['1']['locales']['frFR']['name'] = 'Correction native'
        with self.assertRaisesRegex(ValueError, 'outside catalog scope'):
            work['validate_batch'](self.root, batch, results)
        del results['items']['1']['locales']['frFR']['name']

        with self.assertRaisesRegex(ValueError, 'preserve existing text'):
            work['validate_batch'](self.root, batch, results)

    def test_unchanged_submission_generates_no_file_edits(self):
        batch = self.prepare()[0]
        self.assertEqual(work['create_patch'](self.root, batch, batch['records']),
                         '*** Begin Patch\n*** End Patch\n')

    def test_existing_record_patch_only_replaces_owned_entity(self):
        batch = self.prepare()[0]
        results = copy.deepcopy(batch['records'])
        results['items']['1']['locales']['frFR']['name'] = 'Nouvelle épée $s1'
        path = self.root / 'catalogs/items/1.json'
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps(self.records['items']['1']), encoding='utf-8')
        patch_text = work['create_patch'](self.root, batch, results)
        self.assertIn('*** Update File: ' + str(path), patch_text)
        self.assertIn('Nouvelle épée $s1', patch_text)
        self.assertNotIn('2.json', patch_text)
        self.assertNotIn('metadata.json', patch_text)

    def test_new_non_english_record_also_requires_all_language_coverage(self):
        batch = self.prepare({'items': ['4']})[0]
        record = create_item()
        del record['locales']['enUS']
        record['locales']['frFR']['translationMetadata']['fields']['name']['origin'] = 'original'

        with self.assertRaisesRegex(ValueError, 'outside catalog scope'):
            work['validate_batch'](self.root, batch, {'items': {'4': record}})

    def test_patch_rejects_record_changed_between_validation_and_reading_patch_context(self):
        batch = self.prepare()[0]
        results = copy.deepcopy(batch['records'])
        results['items']['1']['locales']['frFR']['name'] = 'Nouvelle épée $s1'
        path = self.root / 'catalogs/items/1.json'
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps(create_item('Concurrent sword $s1')), encoding='utf-8')

        with self.assertRaisesRegex(ValueError, 'changed during patch generation'):
            work['create_patch'](self.root, batch, results)

    def test_existing_empty_records_and_unchanged_structural_whitespace_remain_editable(self):
        empty = {'locales': {}}
        work['validate_record']('spells', '1', empty, {**empty, 'spellId': 2}, self.config['locales'])

        with self.assertRaisesRegex(ValueError, 'nonempty new'):
            work['validate_record']('spells', '1', None, empty, self.config['locales'])

        record = {'locales': {'enUS': {'description': '\n', 'translationMetadata': {'fields': {
            'description': {'origin': 'original', 'source': 'fixture', 'sourceLocale': 'enUS'},
        }}}}}
        work['validate_record']('spells', '1', record, {**record, 'spellId': 2}, self.config['locales'])
        changed = copy.deepcopy(record)
        changed['locales']['enUS']['description'] = ' '

        with self.assertRaisesRegex(ValueError, 'nonempty text'):
            work['validate_record']('spells', '1', record, changed, self.config['locales'])

    def test_patch_keeps_inline_metadata_and_accepts_new_origins(self):
        batch = self.prepare()[0]
        results = copy.deepcopy(batch['records'])
        metadata = copy.deepcopy(results['items']['1']['locales']['frFR']['translationMetadata']['fields']['name'])
        localized = results['items']['1']['locales']['frFR']
        localized['name'] = 'Nouvelle épée $s1'
        path = self.root / 'catalogs/items/1.json'
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps(self.records['items']['1']), encoding='utf-8')
        patch_text = work['create_patch'](self.root, batch, results)
        replacement = json.loads('\n'.join(line[1:] for line in patch_text.splitlines() if line.startswith('+')))
        self.assertEqual(replacement['locales']['frFR']['translationMetadata']['fields']['name'], metadata)
        self.assertNotIn('provenanceRef', patch_text)
        localized['translationMetadata']['fields']['name'] = {
            'origin': 'community', 'source': 'reviewedSource', 'sourceLocale': 'frFR',
        }
        work['validate_batch'](self.root, batch, results)


if __name__ == '__main__':
    unittest.main()
