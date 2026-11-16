"""Offline update planning preserves evidence and requires explicit review."""

import hashlib
import importlib.util
import json
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('plan_update', ROOT / 'tools/catalogs/plan-update.py')
planner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(planner)


class UpdatePlanTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / 'catalogs/quests').mkdir(parents=True)
        (self.root / 'catalogs/quests/metadata.json').write_text(json.dumps({'document': {'locales': ['enUS', 'frFR', 'svSE']}}))
        self.entity = self.root / 'catalogs/quests/1.json'
        self.entity.write_text(json.dumps({'locales': {'enUS': {'title': 'Old'}, 'frFR': {'title': 'Ancien',
            'translationMetadata': {'fields': {'title': {'origin': 'community', 'source': 'manual'}}}}}}))
        (self.root / 'inputs').mkdir()
        (self.root / 'inputs/old').write_text('old source')
        (self.root / 'inputs/new').write_text('new source')

    def db(self, name, rows, fingerprint='fingerprint'):
        path = self.root / (name + '.sqlite')
        db = sqlite3.connect(path)
        db.executescript('CREATE TABLE settings(key TEXT,value TEXT); CREATE TABLE inputs(path TEXT,sha256 TEXT);'
                         'CREATE TABLE records(kind TEXT,entity_id TEXT,locale TEXT,field TEXT,text TEXT,english TEXT,origin TEXT,'
                         'provenance TEXT,flags TEXT,evidence TEXT);')
        db.executemany('INSERT INTO settings VALUES (?,?)', [('schemaVersion', json.dumps(1)),
                                                              ('fingerprint', json.dumps(fingerprint))])
        raw = (self.root / 'inputs' / name).read_bytes()
        db.execute('INSERT INTO inputs VALUES (?,?)', ('inputs/' + name, hashlib.sha256(raw).hexdigest()))
        # Catalog claims and their stale input hashes are not fresh source evidence.
        db.execute('INSERT INTO inputs VALUES (?,?)', ('catalogs/quests/1.json', 'stale'))
        for locale, field, text, provider, evidence, flags, origin, english in rows:
            db.execute('INSERT INTO records VALUES (?,?,?,?,?,?,?,?,?,?)',
                       ('quests', '1', locale, field, text, english, origin, json.dumps({'source': provider}), json.dumps(flags), evidence))
        db.commit()
        db.close()
        return path

    def row(self, text, provider='blizzard', locale='enUS', field='title', evidence='sourceSnapshot', flags=None,
            origin='original', english=None):
        return locale, field, text, provider, evidence, flags or [], origin, english

    def make(self, old, new):
        return self.db('old', old, 'old-build'), self.db('new', new, 'new-build')

    def test_unchanged_ignores_revision_and_catalog_claim(self):
        old, new = self.make([self.row('Old'), self.row('old claim', evidence='catalogClaim')],
                             [self.row('Old'), self.row('new claim', evidence='catalogClaim')])
        result = planner.plan(self.root, old, new)
        self.assertEqual(result['changes'], [])
        self.assertEqual(result['fillScope'], [])
        planner.verify(result, self.root)

    def test_delta_provider_isolation_and_target_review(self):
        old, new = self.make([self.row('Old'), self.row('Questie old', 'questie', field='summary'),
                              self.row('Removed', field='description')],
                             [self.row('New'), self.row('Questie old', 'questie', field='summary'),
                              self.row('Ajout', locale='frFR', field='eventObjectiveLabel')])
        result = planner.plan(self.root, old, new)
        self.assertEqual({c['status'] for c in result['changes']}, {'changed', 'added', 'removed'})
        self.assertNotIn('questie', {c['provider'] for c in result['changes']})
        self.assertEqual(len(result['fillScope']), 2)
        self.assertEqual(result['translationScope'], {'quests': ['1']})
        title = [r for r in result['fieldReview'] if r['field'] == 'title']
        self.assertEqual({r['locale']: r['targetStatus'] for r in title},
                         {'enUS': 'existing', 'frFR': 'existing', 'svSE': 'missing'})
        self.assertTrue(all(r['requiresReview'] for r in title))
        self.assertEqual(title[1]['targetMetadata']['source'], 'manual')
        self.assertNotIn(['quests', '1', 'enUS', 'description', 'blizzard'], result['fillScope'])

    def test_owned_conflict_and_stale_target(self):
        old, new = self.make([self.row('Prior')], [self.row('New')])
        result = planner.plan(self.root, old, new)
        self.assertTrue(result['changes'][0]['manualOrOwnedConflict'])
        self.entity.write_text('{}')
        with self.assertRaisesRegex(ValueError, 'Owned entity changed'):
            planner.verify(result, self.root)

    def test_external_source_stale_and_database_mutation(self):
        old, new = self.make([self.row('Old')], [self.row('New')])
        result = planner.plan(self.root, old, new)
        (self.root / 'inputs/new').write_text('tampered')
        with self.assertRaisesRegex(ValueError, 'Stale external input'):
            planner.verify(result, self.root)
        with self.assertRaisesRegex(ValueError, 'Stale external input'):
            planner.plan(self.root, old, new)

    def test_changed_corpus_is_rejected(self):
        old, new = self.make([self.row('Old')], [self.row('New')])
        result = planner.plan(self.root, old, new)
        db = sqlite3.connect(new)
        db.execute("UPDATE records SET text='tampered'")
        db.commit()
        db.close()
        with self.assertRaisesRegex(ValueError, 'Stale corpus'):
            planner.verify(result, self.root)

    def test_cli_writes_separate_scopes_and_refuses_existing_output(self):
        old, new = self.make([self.row('Old')], [self.row('New')])
        output = self.root / 'datasources/imports/plan'
        cmd = [sys.executable, str(ROOT / 'tools/catalogs/plan-update.py'), '--root', str(self.root),
               'prepare', '--old', str(old), '--new', str(new), '--output-dir', str(output)]
        subprocess.run(cmd, check=True, capture_output=True, text=True)
        self.assertEqual(json.loads((output / 'fill-scope.json').read_text()),
                         [['quests', '1', 'enUS', 'title', 'blizzard']])
        subprocess.run([sys.executable, str(ROOT / 'tools/catalogs/plan-update.py'), '--root', str(self.root),
                        'verify', '--plan', str(output / 'plan.json')], check=True, capture_output=True)
        self.assertNotEqual(subprocess.run(cmd, capture_output=True).returncode, 0)

    def test_duplicate_and_conflicting_candidates(self):
        old, new = self.make([self.row('Old')], [self.row('New'), self.row('New'), self.row('Other')])
        result = planner.plan(self.root, old, new)
        self.assertEqual(result['changes'][0]['status'], 'conflict')
        self.assertEqual(result['changes'][0]['new'], ['New', 'Other'])
        self.assertEqual(result['fillScope'], [])

    def test_filters_and_flagged_candidates(self):
        old, new = self.make([self.row('Old')], [self.row('New', flags=['fallback']),
                                                self.row('Ajout', locale='frFR')])
        result = planner.plan(self.root, old, new, ['quests'], ['title'], ['enUS'])
        self.assertEqual(len(result['changes']), 1)
        self.assertEqual(result['fillScope'], [])
        self.assertEqual(result['changes'][0]['newFlags'], ['fallback'])

    def test_origin_and_context_changes_are_reported_without_fill(self):
        old, new = self.make([self.row('Texte', locale='frFR', origin='community', english='Old context')],
                             [self.row('Texte', locale='frFR', origin='ai', english='New context')])
        result = planner.plan(self.root, old, new)
        change = result['changes'][0]
        self.assertEqual(change['status'], 'contextChanged')
        self.assertEqual(change['oldOrigins'], ['community'])
        self.assertEqual(change['newOrigins'], ['ai'])
        self.assertEqual(change['newEnglishContext'], ['New context'])
        self.assertEqual(result['fillScope'], [])

    def test_origin_only_and_ai_changed_text(self):
        old, new = self.make([self.row('Old', origin='community')], [self.row('Old', origin='ai')])
        result = planner.plan(self.root, old, new)
        self.assertEqual(result['changes'][0]['status'], 'originChanged')
        self.assertEqual(result['fillScope'], [])
        db = sqlite3.connect(new)
        db.execute("UPDATE records SET text='New'")
        db.commit()
        db.close()
        self.assertEqual(planner.plan(self.root, old, new)['fillScope'], [])

    def test_owned_new_value_and_quest_normalization(self):
        self.entity.write_text(json.dumps({'locales': {'enUS': {'title': 'New {name}\nhero'}}}))
        old, new = self.make([self.row('Old')], [self.row('New $N$Bhero')])
        self.assertFalse(planner.plan(self.root, old, new)['changes'][0]['manualOrOwnedConflict'])
        self.assertNotEqual(planner.comparable('spells', '$n'), planner.comparable('spells', '{name}'))

    def test_new_entity_handoff_and_verify_does_not_scan_rows(self):
        self.entity.unlink()
        old, new = self.make([], [self.row('New')])
        result = planner.plan(self.root, old, new)
        self.assertEqual(result['newEntityCandidates'][0]['id'], '1')
        self.assertEqual(result['fillScope'], [])
        self.assertEqual(result['translationScope'], {})
        with patch.object(planner, 'corpus', side_effect=AssertionError('source scan')):
            planner.verify(result, self.root)

    def test_community_never_supersedes_available_native(self):
        old, new = self.make([], [self.row('Native'), self.row('Community', provider='questie', origin='community')])
        result = planner.plan(self.root, old, new)
        self.assertEqual(result['fillScope'], [['quests', '1', 'enUS', 'title', 'blizzard']])

    def test_non_english_source_reviews_derived_targets(self):
        self.entity.write_text(json.dumps({'locales': {
            'frFR': {'title': 'Ancien'},
            'enUS': {'title': 'Old', 'translationMetadata': {'fields': {'title': {'sourceLocale': 'frFR'}}}},
            'svSE': {'title': 'Gammal', 'translationMetadata': {'fields': {'title': {'sourceLocale': 'frFR'}}}},
        }}))
        old, new = self.make([self.row('Ancien', locale='frFR')], [self.row('Nouveau', locale='frFR')])
        result = planner.plan(self.root, old, new)
        targets = [row['locale'] for row in result['fieldReview']]
        self.assertCountEqual(targets, ['frFR', 'enUS', 'svSE'])
        self.assertEqual(len(targets), len(set(targets)))

    def test_corpus_and_external_hashes_do_not_read_whole_files(self):
        old, new = self.make([self.row('Old')], [self.row('New')])
        original = Path.read_bytes

        def bounded_reads(path):
            if path.suffix == '.sqlite' or path.parent.name == 'inputs':
                raise AssertionError('Whole-file read of corpus or external input')
            return original(path)

        with patch.object(Path, 'read_bytes', bounded_reads):
            result = planner.plan(self.root, old, new)
            planner.verify(result, self.root)
        self.assertEqual(result['oldCorpus']['sha256'], hashlib.sha256(original(old)).hexdigest())
        self.assertEqual(result['newCorpus']['externalInputs']['inputs/new'],
                         hashlib.sha256(original(self.root / 'inputs/new')).hexdigest())


if __name__ == '__main__':
    unittest.main()
