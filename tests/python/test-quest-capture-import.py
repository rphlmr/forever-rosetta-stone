"""Verify capture identities, target reuse and strict objective assertions."""

import copy
import json
import runpy
import tempfile
import unittest
from collections import Counter
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.build.runtime_catalog import project_objectives
from tools.catalogs.catalog_storage import get_digest, load_catalog
from id_only_quest_matrix import get_objective_types, format_expected

importer = runpy.run_path(str(ROOT / 'tools/quest-scan/import_capture.py'))
fields = runpy.run_path(str(ROOT / 'tests/python/test-quest-fields-matrix.py'))


def literal(value):
    if value is None:
        return 'nil'
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, dict):
        return '{' + ','.join('[' + literal(key) + ']=' + literal(child) for key, child in value.items()) + '}'
    return json.dumps(value, ensure_ascii=False)


class QuestCaptureImportTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        path = self.root / 'catalogs/quests'
        path.mkdir(parents=True)
        (path / 'metadata.json').write_bytes((ROOT / 'catalogs/quests/metadata.json').read_bytes())
        self.quest = {'locales': {'enUS': {'title': 'Quest'}},
                      'objectiveTargets': {'item': [{'id': 10}], 'npc': [{'id': 20}]}}
        (path / '1.json').write_text(json.dumps(self.quest))
        locales = load_catalog(self.root, 'quests', ids={})['locales']
        self.names = {}
        for kind, identity, name in (('items', 10, 'Pelt'), ('npcs', 20, 'Wolf')):
            record = {'locales': {locale: {'name': name, 'translationMetadata': {
                'fields': {'name': {'origin': 'ai', 'source': 'ForeverRosettaStoneAI', 'sourceLocale': 'enUS'}}}}
                                  for locale in locales}}
            folder = self.root / 'catalogs' / kind
            folder.mkdir()
            (folder / f'{identity}.json').write_text(json.dumps(record))
            self.names[kind] = {str(identity): record}
        fingerprint = get_digest({'1': self.quest})
        self.queue = {'hash': 'queue', 'catalogHash': fingerprint, 'ids': {1: 1}}
        self.data = {'schemaVersion': 1, 'locale': 'enUS', 'build': '70938',
                     'queueHash': 'queue', 'catalogHash': fingerprint, 'nextIndex': 2,
                     'results': {1: {'title': 'Quest', 'status': 'loadedWithObjectives', 'loadSuccess': True,
                                     'rows': {1: {'type': 'item', 'text': '0/5 Pelt',
                                                  'numFulfilled': 0, 'numRequired': 5},
                                              2: {'type': 'monster', 'text': '0/3 Wolf slain',
                                                  'numFulfilled': 0, 'numRequired': 3}}}, 99: None}}

    def prepare(self):
        capture, queue = self.root / 'capture.lua', self.root / 'queue.lua'
        capture.write_text('Capture=' + literal(self.data))
        queue.write_text('RosettaQuestProbeQueue=' + literal(self.queue))
        return importer['prepare'](capture, queue, 'Capture', self.root / 'datasources/imports/output', self.root)

    def test_unique_labeled_targets_reuse_names_without_reordering_or_editing_catalogs(self):
        before = (self.root / 'catalogs/quests/1.json').read_bytes()
        result = self.prepare()
        self.assertEqual(result['changed'], [1])
        self.assertEqual((self.root / 'catalogs/quests/1.json').read_bytes(), before)
        patch = (self.root / 'datasources/imports/output/updates.patch').read_text()
        self.assertIn('"clientObjectiveTargets"', patch)
        self.assertIn('"type": "monster"', patch)
        self.assertNotIn('"numRequired"', patch)
        fixture = json.loads((self.root / 'datasources/imports/output/client-objectives.json').read_text())
        self.assertEqual(fixture['quests']['1']['types'], ['item', 'monster'])

    def test_blank_labels_and_counter_mismatches_never_use_relationship_order(self):
        for text in ('0/5 ', '0/7 Pelt'):
            rows = copy.deepcopy(list(self.data['results'][1]['rows'].values()))
            rows[0]['text'] = text
            result, reason = importer['match_targets'](
                self.quest, rows, lambda kind, identity: self.names['items' if kind == 'item' else 'npcs'][str(identity)],
                ['enUS'])
            self.assertIsNone(result)
            self.assertIsNotNone(reason)

    def test_capture_fingerprints_and_incomplete_results_are_rejected(self):
        self.data['queueHash'] = 'other'
        with self.assertRaisesRegex(ValueError, 'fingerprints'):
            self.prepare()
        self.data['queueHash'] = 'queue'
        self.data['nextIndex'] = 1
        with self.assertRaisesRegex(ValueError, 'Incomplete'):
            self.prepare()

    def test_completed_comparison_supplies_labeled_rows_without_changing_capture(self):
        original = self.data['results'][1]['rows']
        original[1]['text'] = '0/5 '
        self.queue['itemDependencies'] = {1: {1: 10}}
        after = copy.deepcopy(original)
        after[1]['text'] = '0/5 Pelt'
        self.data['comparisons'] = {1: {'questID': 1, 'queueHash': 'queue', 'build': '70938',
            'locale': 'enUS', 'status': 'complete', 'dependencies': {1: {'id': 10, 'status': 'alreadyCached'}},
            'before': {'readSuccess': True, 'rows': copy.deepcopy(after)},
            'after': {'readSuccess': True, 'rows': after}}}
        before = copy.deepcopy(self.data)
        report = self.prepare()
        self.assertEqual(report['comparisonQuests'], [1])
        self.assertEqual(report['changed'], [1])
        self.assertEqual(self.data, before)

    def test_comparison_identity_dependencies_and_conflicts_are_rejected(self):
        rows = copy.deepcopy(self.data['results'][1]['rows'])
        self.queue['itemDependencies'] = {1: {1: 10}}
        comparison = {'questID': 1, 'queueHash': 'queue', 'build': '70938', 'locale': 'enUS',
                      'status': 'complete', 'dependencies': {1: {'id': 10, 'status': 'loaded'}},
                      'before': {'readSuccess': True, 'rows': copy.deepcopy(rows)},
                      'after': {'readSuccess': True, 'rows': copy.deepcopy(rows)}}
        self.data['comparisons'] = {1: comparison}
        for key, wrong in [('build', '1'), ('locale', 'frFR'), ('queueHash', 'other'), ('questID', 2)]:
            with self.subTest(key=key):
                saved = comparison[key]
                comparison[key] = wrong
                with self.assertRaisesRegex(ValueError, 'Comparison identity conflict'):
                    self.prepare()
                comparison[key] = saved
        comparison['dependencies'][1]['id'] = 11
        with self.assertRaisesRegex(ValueError, 'dependency conflict'):
            self.prepare()
        comparison['dependencies'][1]['id'] = 10
        comparison['after']['rows'][1]['text'] = '0/5 Other'
        with self.assertRaisesRegex(ValueError, 'label conflict'):
            self.prepare()
        comparison['after']['rows'][1] = copy.deepcopy(rows[1])
        comparison['after']['rows'][1]['type'] = 'monster'
        with self.assertRaisesRegex(ValueError, 'row conflict'):
            self.prepare()
        comparison['after']['rows'][1] = copy.deepcopy(rows[1])
        self.data['results'][1]['title'] = 'Wrong quest'
        with self.assertRaisesRegex(ValueError, 'Quest identity conflict'):
            self.prepare()

    def test_incomplete_comparison_is_ignored(self):
        self.data['comparisons'] = {1: {'status': 'paused'}}
        self.assertEqual(self.prepare()['comparisonQuests'], [])

    def test_duplicate_names_do_not_establish_entity_identity(self):
        self.quest['objectiveTargets']['item'].append({'id': 11})
        rows = list(self.data['results'][1]['rows'].values())
        result, reason = importer['match_targets'](self.quest, rows, lambda kind, identity:
            self.names['items' if kind == 'item' else 'npcs']['10' if kind == 'item' else '20'], ['enUS'])
        self.assertIsNone(result)
        self.assertIn('unique', reason)

    def test_destroyed_monster_requires_exact_quest_linked_name(self):
        row = {'type': 'monster', 'text': '0/3 Wolf destroyed', 'numFulfilled': 0, 'numRequired': 3}
        lookup = lambda kind, identity: self.names['npcs'][str(identity)]
        targets, reason = importer['match_targets'](self.quest, [row], lookup, ['enUS'])
        self.assertIsNone(reason)
        self.assertEqual(targets, [{'kind': 'npc', 'id': 20, 'type': 'monster'}])
        row['text'] = '0/3 Other destroyed'
        self.assertEqual(importer['match_targets'](self.quest, [row], lookup, ['enUS'])[1],
                         'objective label has no unique quest-linked identity')
        row['text'] = '0/3 Wolf healed'
        self.assertEqual(importer['match_targets'](self.quest, [row], lookup, ['enUS'])[1],
                         'unverified NPC objective wording')

    def test_reputation_requires_standard_ranks_and_unique_linked_faction(self):
        quest = {'objectiveTargets': {'reputation': [{'id': 92}]}}
        row = {'type': 'reputation', 'text': 'Neutral / Friendly Gelkis Clan Centaur',
               'numFulfilled': 0, 'numRequired': 1}
        faction = {'locales': {'enUS': {'name': 'Gelkis Clan Centaur'}}}
        lookup = lambda kind, identity: faction if kind == 'faction' and identity == 92 else None
        target, reason = importer['match_targets'](quest, [row], lookup, ['enUS'])
        self.assertIsNone(reason)
        self.assertEqual(target, [{'kind': 'faction', 'id': 92, 'type': 'reputation'}])
        row['text'] = 'Unknown / Friendly Gelkis Clan Centaur'
        self.assertEqual(importer['match_targets'](quest, [row], lookup, ['enUS'])[1],
                         'unrecognized reputation objective wording')
        row['text'] = 'Neutral / Friendly Other'
        self.assertEqual(importer['match_targets'](quest, [row], lookup, ['enUS'])[1],
                         'reputation label has no unique quest-linked identity')
        row['text'] = 'Neutral / Friendly Gelkis Clan Centaur'
        quest['objectiveTargets']['reputation'].append({'id': 93})
        self.assertEqual(importer['match_targets'](quest, [row], lambda kind, identity: faction, ['enUS'])[1],
                         'reputation label has no unique quest-linked identity')

    def test_reputation_binding_always_has_explicit_client_index(self):
        self.quest['objectiveTargets']['reputation'] = [{'id': 92}]
        folder = self.root / 'catalogs/factions'
        folder.mkdir()
        (folder / '92.json').write_text(json.dumps({'locales': {'enUS': {'name': 'Gelkis Clan Centaur'}}}))
        path = self.root / 'catalogs/quests/1.json'
        path.write_text(json.dumps(self.quest))
        fingerprint = get_digest({'1': self.quest})
        self.queue['catalogHash'] = self.data['catalogHash'] = fingerprint
        self.data['results'][1]['rows'] = {1: {'type': 'reputation', 'text': 'Neutral / Friendly Gelkis Clan Centaur',
                                               'numFulfilled': 0, 'numRequired': 1}}
        self.assertEqual(self.prepare()['rowResults'][0]['verified'], [1])
        patch = (self.root / 'datasources/imports/output/updates.patch').read_text()
        self.assertIn('"index": 1', patch)
        self.assertIn('"kind": "faction"', patch)
        self.assertIn('"type": "reputation"', patch)

    def test_partial_rows_keep_captured_index_and_report_unresolved(self):
        self.data['results'][1]['rows'][1] = {'type': 'event', 'text': 'Event complete',
                                              'numFulfilled': 0, 'numRequired': 1}
        result = self.prepare()
        self.assertEqual(result['rowResults'][0]['verified'], [2])
        self.assertEqual(result['rowResults'][0]['unresolved'][0]['index'], 1)
        patch = (self.root / 'datasources/imports/output/updates.patch').read_text()
        self.assertIn('"index": 2', patch)
        self.assertIn('"id": 20', patch)
        self.assertNotIn('+      "kind": "item",', patch)

    def test_existing_index_conflict_does_not_shift_or_overwrite(self):
        self.quest['clientObjectiveTargets'] = [{'index': 2, 'kind': 'item', 'id': 10}]
        self.quest['clientObjectiveTargetsMetadata'] = {'source': 'original'}
        path = self.root / 'catalogs/quests/1.json'
        path.write_text(json.dumps(self.quest))
        fingerprint = get_digest({'1': self.quest})
        self.queue['catalogHash'] = self.data['catalogHash'] = fingerprint
        result = self.prepare()
        self.assertEqual(result['rowResults'][0]['verified'], [])
        self.assertEqual(result['rowResults'][0]['unresolved'],
                         [{'index': 1, 'reason': 'existing mapping provenance could not be reverified'},
                          {'index': 2, 'reason': 'existing verified target mapping differs'}])
        patch = (self.root / 'datasources/imports/output/updates.patch').read_text()
        self.assertEqual(patch, '*** Begin Patch\n*** End Patch\n')
        self.assertEqual(json.loads(path.read_text()), self.quest)

    def test_existing_explicit_objective_type_must_match_captured_type(self):
        self.quest['locales']['enUS']['objectiveLines'] = [{'index': 2, 'type': 'event', 'text': 'Keep'}]
        path = self.root / 'catalogs/quests/1.json'
        path.write_text(json.dumps(self.quest))
        fingerprint = get_digest({'1': self.quest})
        self.queue['catalogHash'] = self.data['catalogHash'] = fingerprint
        result = self.prepare()
        self.assertEqual(result['rowResults'][0]['verified'], [1])
        self.assertEqual(result['rowResults'][0]['unresolved'],
                         [{'index': 2, 'reason': 'existing objective type differs'}])
        patch = (self.root / 'datasources/imports/output/updates.patch').read_text()
        self.assertNotIn('-          "text": "Keep"', patch)

    def test_duplicate_effective_existing_indices_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            importer['indexed_targets']([{'index': 2, 'kind': 'npc', 'id': 20},
                                          {'kind': 'item', 'id': 10}])

    def test_matching_name_at_another_index_does_not_reverify_existing_mapping(self):
        self.quest['clientObjectiveTargets'] = [{'kind': 'item', 'id': 10}]
        path = self.root / 'catalogs/quests/1.json'
        path.write_text(json.dumps(self.quest))
        fingerprint = get_digest({'1': self.quest})
        self.queue['catalogHash'] = self.data['catalogHash'] = fingerprint
        self.data['results'][1]['rows'] = {
            1: {'type': 'event', 'text': 'Done', 'numFulfilled': 0, 'numRequired': 1},
            2: {'type': 'item', 'text': '0/5 Pelt', 'numFulfilled': 0, 'numRequired': 5}}
        result = self.prepare()
        self.assertEqual(result['changed'], [])
        self.assertEqual(result['rowResults'][0]['verified'], [])
        self.assertEqual(result['rowResults'][0]['unresolved'][1]['reason'],
                         'existing mapping provenance could not be reverified')

    def test_projection_requires_explicit_npc_type_and_preserves_existing_text(self):
        quest = {'clientObjectiveTargets': [{'kind': 'npc', 'id': 20, 'type': 'monster'}]}
        lines, ai = project_objectives(quest, {}, 'enUS', {}, self.names['npcs'])
        self.assertEqual(lines, [{'index': 1, 'type': 'monster', 'text': 'Wolf: {current}/{required}'}])
        self.assertTrue(ai)
        original = {'objectiveLines': [{'index': 1, 'type': 'monster', 'text': 'Preserved'}]}
        self.assertEqual(project_objectives(quest, original, 'enUS', {}, self.names['npcs'])[0],
                         original['objectiveLines'])
        del quest['clientObjectiveTargets'][0]['type']
        self.assertEqual(project_objectives(quest, {}, 'enUS', {}, self.names['npcs'])[0], [])

    def test_observed_indices_verify_amounts_but_do_not_hide_missing_types(self):
        types, missing = get_objective_types({'locales': {}}, ['item', '', 'event'])
        self.assertEqual(types, {1: {'item'}, 2: set(), 3: {'event'}})
        self.assertEqual(missing, {2: 'untyped captured row'})
        with self.assertRaisesRegex(ValueError, 'conflicts'):
            get_objective_types({'locales': {'enUS': {'objectiveLines': [
                {'index': 1, 'type': 'item', 'text': 'Text'}]}}}, ['monster'])

    def test_distinct_objective_amounts_expose_index_mixups(self):
        profile = {'sex': 2, 'current': 0, 'required': 5, 'objectiveRequired': {1: 5, 2: 8}}
        self.assertEqual(format_expected('$1oa then $2oa', profile, {1, 2}, 'enUS'),
                         ('5 then 8', None))

    def test_field_matrix_detects_wrong_variables_and_missing_translations(self):
        expected = {'title': 'Quest', 'description': 'Collect $1oa'}
        report = {'missingTarget': [], 'failures': [], 'notApplicable': []}
        counts = Counter()
        fields['compare_fields'](1, 'enUS', expected,
                                 {'title': 'Quest', 'description': 'Collect $2oa'},
                                 {'title', 'description', 'summary'}, report, counts)
        self.assertEqual((counts['cases'], counts['passed'], counts['failed']), (3, 1, 2))
        self.assertEqual(report['missingTarget'][0]['field'], 'summary')
        self.assertEqual({(row['field'], row['reason']) for row in report['failures']},
                         {('description', 'mismatch'), ('summary', 'missing target translation')})


if __name__ == '__main__':
    unittest.main()
