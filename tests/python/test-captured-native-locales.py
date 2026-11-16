"""Native locale regressions retain real values and contexts from the completed campaign."""
import contextlib
import io
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/source-scan'))
import official_tooltip_matrix as matrix
import report_tooltip_gaps as gaps
from audit_tooltip_hovers import restore


class CapturedNativeLocaleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.captures = []
        (ROOT / 'datasources/imports').mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / 'datasources/imports') as directory:
            directory = Path(directory)
            fixtures = directory / 'fixtures'
            fixtures.mkdir()
            for path in (ROOT / 'tests/fixtures/tooltip-campaign').glob('remaining-native-*-70938-run-*.json'):
                shutil.copy2(path, fixtures)
                cls.captures.append(restore(json.loads(path.read_text())))
            cls.observations = list(matrix.observations(fixtures))
            keys = {matrix.fingerprint(o) for o in cls.observations
                    if o['kind'] == 'spell' and o['id'] in (424785, 408498)}
            with contextlib.redirect_stdout(io.StringIO()):
                cls.report = matrix.run(fixtures, directory / 'report', case_keys=keys)

    def test_four_completed_native_passes_keep_actual_player_context(self):
        self.assertEqual({capture['source']['locale'] for capture in self.captures},
                         {'deDE', 'esES', 'esMX', 'ruRU'})
        self.assertEqual(len(self.observations), 220)
        for capture in self.captures:
            self.assertEqual(len(capture['source']['captureSha256']), 64)
            run = capture['runs'][0]
            build = run['build']['values']
            self.assertEqual(capture['source']['build'], f'{build[1]}.{build[2]}')
            self.assertEqual(run['stoppedReason'], 'api complete')
            sample = run['samples'][0]
            self.assertFalse(sample['details']['pendingAtCapture'])
            self.assertEqual(sample['context']['sex']['values'][1], 2)
            self.assertEqual(sample['context']['faction']['values'][1], 'Alliance')

    def test_unterminated_plural_without_alternatives_matches_native_literal(self):
        self.assertEqual(self.report['directionsPerCase'], 90)
        self.assertEqual(self.report['selectedCases'], 8)
        saber = [case for case in self.report['cases'] if case['id'] == 424785]
        self.assertEqual(len(saber), 4)
        self.assertFalse([event for event in self.report['failures'] if event['id'] == 424785])
        native = next(o for o in self.observations if o['id'] == 424785 and o['locale'] == 'esMX')
        self.assertIn('Otorga 1 p. de combo.', str(gaps.clean(native['data'])))
        owner = json.loads((ROOT / 'catalogs/spells/424785.json').read_text())
        self.assertIn('$lp. de combo.', owner['locales']['esMX']['description'])

    def test_exact_native_hotfix_templates_preserve_dynamic_proc_chance(self):
        available = {'enUS', 'frFR', 'deDE', 'esES', 'esMX', 'ruRU'}
        maelstrom = [case for case in self.report['cases'] if case['id'] == 408498]
        self.assertEqual(len(maelstrom), 4)
        self.assertFalse([event for event in self.report['failures'] if event['id'] == 408498
                          and event['source'] in available and event['target'] in available])
        for observation in self.observations:
            if observation['id'] == 408498:
                self.assertIn('9%', str(gaps.clean(observation['data'])))
        owner = json.loads((ROOT / 'catalogs/spells/408498.json').read_text())
        for locale in ('deDE', 'esES', 'esMX', 'ruRU'):
            field = owner['locales'][locale]
            self.assertIn('${($mws*$s2/60)*100}', field['description'])
            metadata = field['translationMetadata']['fields']['description']
            self.assertEqual(metadata['source'], 'wowClientCache')
            self.assertEqual(metadata['sourceLocale'], locale)
            self.assertEqual(metadata['origin'], 'original')

    def test_historical_weapon_context_keeps_its_own_captured_proc_chance(self):
        capture = restore(json.loads((ROOT / 'tests/fixtures/tooltip-campaign/talent-408498-enUS.json').read_text()))
        for target in ('deDE', 'esES', 'esMX', 'ruRU'):
            with self.subTest(target=target):
                replay = gaps.Replay('enUS', {})
                missing, error, _ = replay.run('spell', 408498, gaps.clean(capture['data']), target,
                    gaps.clean(capture['processingInfo']), matrix.visible(capture['visible']))
                self.assertIsNone(error)
                self.assertEqual(missing, [])
                rows, error = matrix.read_rendered(replay)
                self.assertIsNone(error)
                text = ' '.join(row['left'] or '' for row in rows)
                self.assertIn('28%', text)
                self.assertNotIn('9%', text)

    def test_native_scalar_damage_ranges_use_owned_client_separators(self):
        targets = {'enUS', 'frFR', 'deDE', 'esES', 'esMX', 'ruRU'}
        checked = 0
        for observation in self.observations:
            if observation['kind'] != 'spell' or observation['id'] != 20694:
                continue
            for target in sorted(targets - {observation['locale']}):
                with self.subTest(source=observation['locale'], target=target):
                    replay = gaps.Replay(observation['locale'],
                        {k: v for k, v in observation['globals'].items() if v != '<nil>'},
                        observation['calls'], observation.get('types'))
                    missing, error, _ = replay.run('spell', observation['id'], gaps.clean(observation['data']),
                        target, gaps.clean(observation.get('processing')))
                    self.assertIsNone(error)
                    self.assertEqual(missing, [])
                    checked += 1
        self.assertEqual(checked, 20)

    def test_compound_power_cost_row_translates_each_owned_label(self):
        checked = 0
        for observation in self.observations:
            if observation['kind'] != 'spell' or observation['id'] != 14903:
                continue
            for target in sorted({'enUS', 'frFR', 'deDE', 'esES', 'esMX', 'ruRU'} - {observation['locale']}):
                with self.subTest(source=observation['locale'], target=target):
                    replay = gaps.Replay(observation['locale'],
                        {k: v for k, v in observation['globals'].items() if v != '<nil>'},
                        observation['calls'], observation.get('types'))
                    missing, error, _ = replay.run('spell', observation['id'], gaps.clean(observation['data']),
                        target, gaps.clean(observation.get('processing')))
                    self.assertIsNone(error)
                    self.assertEqual(missing, [])
                    checked += 1
        self.assertEqual(checked, 20)


if __name__ == '__main__':
    unittest.main()
