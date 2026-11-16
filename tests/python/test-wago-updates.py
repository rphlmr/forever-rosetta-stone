"""Offline regression checks for build selection, snapshot integrity and diffs."""

import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from urllib.error import URLError

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'datasources'))
from datasources.wago.loader import download_tables
from datasources.wago.loader import audit_dependencies, audit_translations, check_updates, compare_snapshots, load_snapshot


def snapshot(rows, locale='enUS', columns=('ID', 'Description_lang')):
    return {'build': '1.60.1.70862', 'exports': {
        ('Spell', locale): {'columns': list(columns), 'rows': {row['ID']: row for row in rows}},
    }}


class UpdateTests(unittest.TestCase):
    def test_build_selection_is_forever_only_numeric_and_excludes_background(self):
        products = {'wow': [{'version': '99.0.0.1'}], 'wowf': [
            {'product': 'wowf', 'version': version, 'is_bgdl': background}
            for version, background in [('1.60.1.99', False), ('1.60.1.100', False), ('1.60.1.101', True)]
        ]}
        report = check_updates('1.60.1.99', lambda *args, **kwargs: io.BytesIO(json.dumps(products).encode()))
        self.assertEqual(report['latest'], '1.60.1.100')
        self.assertEqual(report['newerBuilds'], ['1.60.1.100'])

    def test_network_failure_and_unknown_schema_cannot_mean_no_updates(self):
        def unavailable(*args, **kwargs):
            raise URLError('offline')

        with self.assertRaises(URLError):
            check_updates('1.60.1.70862', unavailable)

        for response in ({}, {'wowf': []}, {'wowf': [{'version': '1.60.1.70862'}]}):
            with self.subTest(response=response), self.assertRaises(ValueError):
                check_updates('1.60.1.70862', lambda *a, **k: io.BytesIO(json.dumps(response).encode()))

    def test_diff_tracks_ids_fields_and_unchanged_translation(self):
        before = snapshot([{'ID': '1', 'Description_lang': 'Old'}, {'ID': '2', 'Description_lang': 'Removed'}])
        after = snapshot([{'ID': '3', 'Description_lang': 'Added'}, {'ID': '1', 'Description_lang': 'New'}])

        for value in (before, after):
            value['exports'][('Spell', 'frFR')] = snapshot(
                [{'ID': '1', 'Description_lang': 'Ancien'}]
            )['exports'][('Spell', 'enUS')]

        report = compare_snapshots(before, after)
        self.assertEqual(report['differences'][0]['addedIds'], ['3'])
        self.assertEqual(report['differences'][0]['removedIds'], ['2'])
        self.assertEqual(report['differences'][0]['changes'][0]['after'], 'New')
        self.assertEqual(report['unchangedTranslationAfterEnglishEdit'][0]['locale'], 'frFR')

    def test_row_order_does_not_change_diff_and_schema_changes_do(self):
        rows = [{'ID': '1', 'Description_lang': 'a'}, {'ID': '2', 'Description_lang': 'b'}]
        self.assertEqual(compare_snapshots(snapshot(rows), snapshot(rows[::-1]))['differences'], [])
        after = snapshot(rows, columns=('ID', 'Description_lang', 'NewField'))
        self.assertEqual(compare_snapshots(snapshot(rows), after)['differences'][0]['addedFields'], ['NewField'])

    def test_different_profiles_are_rejected(self):
        with self.assertRaises(ValueError):
            compare_snapshots(snapshot([]), snapshot([], locale='frFR'))

    def test_translation_audit_flags_candidates_without_claiming_bad_translation(self):
        source = snapshot([
            {'ID': '1', 'Description_lang': 'Name'}, {'ID': '2', 'Description_lang': 'Damage $s1 over $d'},
            {'ID': '3', 'Description_lang': 'Missing'}, {'ID': '4', 'Description_lang': 'Missing ID'},
            {'ID': '5', 'Description_lang': 'Damage $s1 over $d'},
        ])
        source['exports'].update(snapshot([
            {'ID': '1', 'Description_lang': 'Name'}, {'ID': '2', 'Description_lang': 'Dégâts $s2'},
            {'ID': '3', 'Description_lang': ''},
            {'ID': '5', 'Description_lang': 'Pendant $d inflige $s1'},
        ], locale='frFR')['exports'])
        self.assertEqual(audit_translations(source)['counts'], {
            'possibleEnglishFallback': 1, 'placeholderReview': 1, 'missingText': 1, 'missingId': 1,
        })

    def test_dependency_audit_exposes_missing_target(self):
        source = snapshot([{'ID': '1', 'Description_lang': '$@spelldesc99 and $98s1'}])
        source['exports'][('ItemEffect', 'enUS')] = {
            'columns': ['ID', 'SpellID'], 'rows': {'1': {'ID': '1', 'SpellID': '99'}},
        }
        report = audit_dependencies(source)
        self.assertEqual(report['joins'][0]['missingIds'], ['99'])
        self.assertIn('SpellEffect', report['missingProfileTables'])
        self.assertEqual({reference['targetSpellId'] for reference in report['missingReferencedSpells']}, {'98', '99'})

    def test_trait_curve_dependencies_are_audited(self):
        source = snapshot([])
        source['exports'][('TraitDefinitionEffectPoints', 'enUS')] = {
            'columns': ['ID', 'TraitDefinitionID', 'CurveID'],
            'rows': {'1': {'ID': '1', 'TraitDefinitionID': '11', 'CurveID': '2'}},
        }
        source['exports'][('CurvePoint', 'enUS')] = {'columns': ['ID', 'CurveID'], 'rows': {}}
        joins = audit_dependencies(source)['joins']
        self.assertEqual(joins[-1]['target'], 'CurvePoint.CurveID')
        self.assertEqual(joins[-1]['missingIds'], ['2'])

    def test_snapshot_rejects_missing_exports_corruption_and_incomplete_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)

            with contextlib.redirect_stdout(io.StringIO()):
                download_tables('1.60.1.70862', path, ('Spell',), ('enUS', 'frFR'),
                                lambda *a, **k: io.BytesIO(b'ID,Description_lang\n1,Test\n'))

            self.assertEqual(len(load_snapshot(path)['exports']), 2)
            manifest_path = path / 'manifest.json'
            manifest = json.loads(manifest_path.read_text())
            broken = dict(manifest, complete=False)
            manifest_path.write_text(json.dumps(broken))

            with self.assertRaises(ValueError):
                load_snapshot(path)

            broken = dict(manifest, results=manifest['results'][:1])
            manifest_path.write_text(json.dumps(broken))

            with self.assertRaises(ValueError):
                load_snapshot(path)

            manifest_path.write_text(json.dumps(manifest))
            (path / manifest['results'][0]['file']).write_text('ID,Description_lang\n1,Changed\n')

            with self.assertRaisesRegex(ValueError, 'hash mismatch'):
                load_snapshot(path)

    def test_snapshot_accepts_english_only_tables_with_localized_columns(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            tables = ('GlobalStrings', 'Talent', 'Spell')

            with contextlib.redirect_stdout(io.StringIO()):
                download_tables('1.60.1.70862', path, tables, ('enUS', 'frFR'),
                                lambda *a, **k: io.BytesIO(b'ID,Description_lang\n1,Test\n'))

            exports = load_snapshot(path)['exports']
            self.assertEqual(set(exports), {
                ('GlobalStrings', 'enUS'), ('GlobalStrings', 'frFR'), ('Talent', 'enUS'), ('Spell', 'enUS'),
                ('Spell', 'frFR'),
            })

            manifest_path = path / 'manifest.json'
            manifest = json.loads(manifest_path.read_text())
            manifest['results'] = [entry for entry in manifest['results']
                                   if (entry['table'], entry['locale']) != ('Spell', 'frFR')]
            manifest_path.write_text(json.dumps(manifest))

            with self.assertRaisesRegex(ValueError, 'manifest exports do not match'):
                load_snapshot(path)


if __name__ == '__main__':
    unittest.main()
