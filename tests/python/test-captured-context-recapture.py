"""Fresh native French scenarios carry their own sex/faction and real unit evidence."""
import contextlib
import hashlib
import io
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/source-scan'))
from audit_tooltip_hovers import restore
import official_tooltip_matrix as matrix


class CapturedContextRecaptureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.path = ROOT / 'tests/fixtures/tooltip-campaign/context-recapture-frFR-70938.json'
        cls.capture = restore(json.loads(cls.path.read_text()))
        cls.scope = json.loads((ROOT / 'tests/fixtures/context-recapture-scope-20261116.json').read_text())
        (ROOT / 'datasources/imports').mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / 'datasources/imports') as directory:
            directory = Path(directory)
            fixtures = directory / 'fixtures'
            fixtures.mkdir()
            shutil.copy2(cls.path, fixtures / cls.path.name)
            cls.observations = list(matrix.observations(fixtures))
            with contextlib.redirect_stdout(io.StringIO()):
                cls.report = matrix.run(fixtures, directory / 'report')

    def test_all_new_applicable_native_cases_pass_every_official_direction(self):
        self.assertEqual(self.report['nativeObservations'], 78)
        self.assertEqual(self.report['nativeStatus'], {'replayed': 50, 'not_applicable': 1})
        self.assertEqual(self.report['directionsPerCase'], 90)
        self.assertLessEqual(set(self.report['counts']), {'passed', 'text_difference_values_preserved'})
        self.assertEqual(sum(self.report['counts'].values()), 4500)
        self.assertFalse(self.report['failures'])

    def test_complete_targeted_inventory_has_its_own_actual_player_context(self):
        self.assertEqual(self.capture['source']['locale'], 'frFR')
        run = next(run for run in self.capture['runs'] if run['profile'] == 'api')
        self.assertEqual(run['stoppedReason'], 'api complete')
        self.assertEqual(run['cases']['api']['sample']['mode'], 'missing-player-context-frFR')
        self.assertEqual(len(run['samples']), 1)
        sample = run['samples'][0]
        self.assertFalse(sample['details']['pendingAtCapture'])
        calls = sample['details']['calls']
        self.assertIn(calls['UnitSex']['"player"']['values'][1], (2, 3))
        self.assertIn(calls['UnitFactionGroup']['"player"']['values'][1], ('Alliance', 'Horde'))
        for kind in ('item', 'spell'):
            observed = {o['id'] for o in self.observations if o['kind'] == kind}
            self.assertEqual(observed, set(self.scope['ids'][kind]))
        self.assertEqual(self.scope['historicalDirectionEvents'], 628)
        self.assertEqual(len(self.scope['historicalCaseKeys']), 48)

    def test_human_portrait_and_female_night_elf_have_actual_unit_specific_sex(self):
        pairs = set()
        for observation in self.observations:
            if observation['kind'] != 'player':
                continue
            apis = observation['unit']['apis']
            pairs.add((apis['UnitRace']['values'][3], apis['UnitSex']['values'][1]))
        self.assertEqual(pairs, {(1, 2), (4, 3)})

    def test_custom_pet_name_is_not_misidentified_as_a_catalog_npc(self):
        excluded = [c for c in self.report['cases'] if c['nativeStatus'] == 'not_applicable']
        self.assertEqual(len(excluded), 1)
        self.assertIsNone(excluded[0]['id'])
        excluded_sources = {(s['run'], s['sample']) for s in excluded[0]['sources']}
        for run in self.capture['runs']:
            for sample in run['samples']:
                if (run['run'], sample['sample']) in excluded_sources:
                    self.assertTrue(sample['details']['data']['guid'].startswith('Pet-'))

    def test_release_scope_uses_complete_replacement_evidence(self):
        self.assertTrue(self.scope['retireCoveredCasesFromReleaseBlockers'])
        self.assertEqual(self.scope['replacementFixture'], str(self.path.relative_to(ROOT)))
        self.assertEqual(self.scope['replacementFixtureSha256'], hashlib.sha256(self.path.read_bytes()).hexdigest())


if __name__ == '__main__':
    unittest.main()
