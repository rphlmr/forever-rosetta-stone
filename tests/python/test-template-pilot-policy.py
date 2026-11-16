"""Policy boundaries must not turn expected catalog states into renderer failures."""

import copy
import hashlib
import json
import unittest
import sqlite3
import tempfile
from pathlib import Path

from template_pilot_common import PilotCases, OFFICIAL_LOCALES, load_records
from template_pilot_spells import run_matrices, SPELL_ID
from template_pilot_labels import run_matrix as labels
from datasources.corpus.translation_corpus import SCHEMA


class PilotPolicyTests(unittest.TestCase):
    def setUp(self):
        PilotCases.configure_policy_database()
        self.addCleanup(PilotCases.configure_policy_database)
        self.identity = {'id': 1, 'field': 'description', 'sourceLocale': 'enUS',
                         'targetLocale': 'frFR', 'profile': 'baseline'}
        self.record = {'locales': {locale: {'description': 'Damage $s1.'} for locale in OFFICIAL_LOCALES}}

    def test_real_arctic_reach_english_prose_passes_across_official_languages(self):
        spell = load_records('spells', [SPELL_ID])[str(SPELL_ID)]
        for locale in ('enUS', 'frFR', 'deDE'):
            self.assertEqual(spell['locales'][locale]['description'], spell['locales']['enUS']['description'])
        report = run_matrices(['enUS', 'frFR', 'deDE'], ['enUS', 'frFR', 'deDE'], ['baseline'])[0]
        self.assertEqual(report['counts']['passed'], 9)
        self.assertTrue(all(case['actual'] == case['expected'] for case in report['cases']))

    def test_real_empty_separator_is_a_rendered_value_not_missing_data(self):
        report = labels(['enUS'], ['frFR', 'esES', 'ruRU'], ['baseline'])
        empty = [case for case in report['cases'] if case['key'] == 'LARGE_NUMBER_SEPERATOR']
        self.assertEqual(len(empty), 3)
        self.assertTrue(all(case['status'] == 'passed' and case['expected'] == case['actual']
                            and case['actual']['catalogSeparator'] == '' for case in empty))

    def test_all_explicit_official_empty_is_not_applicable(self):
        cases = PilotCases('spells')
        for record in self.record['locales'].values():
            record['description'] = ''
        self.assertTrue(cases.apply_policy(self.identity, self.record, 'description', 'spells', source_required=True))
        self.assertEqual(cases.cases[0]['status'], 'not_applicable')
        self.assertEqual(cases.finish({})['counts']['passed'], 0)

    def test_official_empty_and_absent_are_distinct_nonblocking_warnings(self):
        for value, reason in (('', 'official_target_empty'), (None, 'official_target_absent')):
            record = copy.deepcopy(self.record)
            if value is None:
                del record['locales']['frFR']['description']
            else:
                record['locales']['frFR']['description'] = value
            cases = PilotCases('spells')
            self.assertTrue(cases.apply_policy(self.identity, record, 'description', 'spells'))
            self.assertEqual(cases.cases[0]['status'], 'warning')
            self.assertEqual(cases.cases[0]['reason'], reason)
        self.identity.update(sourceLocale='frFR', targetLocale='enUS')
        self.assertTrue(cases.apply_policy(self.identity, record, 'description', 'spells', source_required=True))
        self.assertEqual(cases.cases[-1]['reason'], 'official_source_absent')

    def test_policy_absence_uses_verified_sources_and_shared_rule_without_a_queue(self):
        self.identity['targetLocale'] = 'daDK'
        cases = PilotCases('spells')
        self.assertFalse(cases.apply_policy(self.identity, self.record, 'description', 'spells'))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            raw = root / 'snapshot.txt'
            raw.write_text('Pinned snapshot')
            database = root / 'corpus.sqlite'
            db = sqlite3.connect(database)
            self.addCleanup(db.close)
            db.executescript(SCHEMA)
            db.execute('INSERT INTO settings VALUES(?,?)', ('schemaVersion', '1'))
            db.execute('INSERT INTO inputs VALUES(?,?)', ('snapshot.txt', hashlib.sha256(raw.read_bytes()).hexdigest()))
            db.commit()
            PilotCases.configure_policy_database(database, root)
            self.assertTrue(cases.apply_policy(self.identity, self.record, 'description', 'spells'))
            self.assertEqual(cases.cases[0]['status'], 'allowed_absence')
            self.assertEqual(cases.finish({})['counts']['passed'], 0)
            provenance = json.dumps({'source': 'questie', 'sourceLocale': 'frFR', 'sourceRevision': 'pinned'})
            db.execute('INSERT INTO records VALUES(NULL,?,?,?,?,?,?,?,?,?,?,?)',
                       ('spells', '1', 'frFR', 'description', 'Dégâts $s1.', 'Damage $s1.',
                        'community', 'sourceSnapshot', provenance, 'snapshot.txt', '[]'))
            db.commit()
            PilotCases.configure_policy_database(database, root)
            self.assertFalse(cases.apply_policy(self.identity, self.record, 'description', 'spells'))
            self.assertTrue(cases.apply_policy(self.identity, self.record, 'description', 'spells', entity_id=2))
            raw.write_text('Changed source')
            with self.assertRaisesRegex(ValueError, 'Source changed'):
                PilotCases.configure_policy_database(database, root)
            self.assertIsNone(PilotCases.policy_evidence)

    def test_empty_permission_does_not_hide_a_mismatch_or_runtime_error(self):
        cases = PilotCases('globalstrings')
        self.assertFalse(cases.check(self.identity, '', None, allow_empty=True))
        self.assertFalse(cases.check(self.identity, '', 'Unexpected text', allow_empty=True))
        self.assertFalse(cases.check(self.identity, '', '', error='runtime failure', allow_empty=True))
        self.assertEqual(cases.finish({})['counts']['failed'], 3)


if __name__ == '__main__':
    unittest.main()
