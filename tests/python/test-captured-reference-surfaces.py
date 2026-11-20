"""Partial native effect surfaces carry observed reference presence, never invented values."""
import contextlib
import copy
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/source-scan'))
import official_tooltip_matrix as matrix
import report_tooltip_gaps as gaps


class CapturedReferenceSurfaceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        observations = list(matrix.observations(ROOT / 'tests/fixtures/tooltip-campaign'))
        cls.observations = [o for o in observations
                            if o['kind'] == 'item' and o['id'] in (2683, 4594)]
        keys = {matrix.fingerprint(o) for o in cls.observations}
        (ROOT / 'datasources/imports').mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / 'datasources/imports') as directory:
            with contextlib.redirect_stdout(io.StringIO()):
                cls.report = matrix.run_observations(observations,
                    Path(directory) / 'report', case_keys=keys)

    def test_actual_food_surfaces_have_no_decoder_failures_in_any_official_direction(self):
        self.assertEqual(self.report['directionsPerCase'], 90)
        self.assertEqual(self.report['nativeStatus'], {'replayed': self.report['selectedCases']})
        self.assertEqual(sum(self.report['counts'].values()), self.report['selectedCases'] * 90)
        # Historical uncaptured gender remains unavailable, even when a fresh run
        # for the same owner contains UnitSex. It is not a successful direction.
        self.assertLessEqual(set(self.report['counts']),
            {'passed', 'text_difference_values_preserved',
             'missing_captured_player_context', 'blocked_source_generation'})
        for case in self.report['cases']:
            if case['locale'] in ('deDE', 'esES', 'esMX', 'ruRU'):
                self.assertFalse([event for event in self.report['failures'] if event['case'] == case['key']])

    def test_native_parent_match_carries_absence_without_injecting_the_child(self):
        observation = next(o for o in self.observations if o['locale'] == 'deDE' and o['id'] == 2683)
        original = copy.deepcopy(observation)
        replay = gaps.Replay('deDE', {k: v for k, v in observation['globals'].items() if v != '<nil>'},
                             observation['calls'], observation.get('types'))
        missing, error, _ = replay.run('item', observation['id'], gaps.clean(observation['data']), 'enUS',
                                      gaps.clean(observation.get('processing')))
        self.assertEqual(missing, [])
        self.assertIsNone(error)
        proofs = matrix.copied_rows(replay.lua.globals().ReplayDecoderProofs)
        omitted = [proof for proof in proofs if proof['choices'].get('1248383:visible-spelldesc:434') == 2]
        self.assertTrue(omitted)
        for proof in omitted:
            self.assertFalse([slot for slot in proof['slots'] if slot['key'].startswith('434:')])
            self.assertNotIn('Restores', proof['renderedText'])
            self.assertIsNone(replay.lua.globals().ReplayAddon.TranslateLiveSpellDescription(
                replay.lua.globals().ReplayAddon, 1248383, b'enUS', proof['nativeText'].encode()))
        self.assertEqual(observation, original)

    def test_complete_native_child_keeps_its_real_captured_quantities(self):
        observation = next(o for o in self.observations if o['locale'] == 'frFR' and o['id'] == 2683)
        replay = gaps.Replay('frFR', {k: v for k, v in observation['globals'].items() if v != '<nil>'},
                             observation['calls'], observation.get('types'))
        missing, error, _ = replay.run('item', observation['id'], gaps.clean(observation['data']), 'enUS',
                                      gaps.clean(observation.get('processing')), observation.get('visible'))
        self.assertEqual(missing, [])
        self.assertIsNone(error)
        proofs = matrix.copied_rows(replay.lua.globals().ReplayDecoderProofs)
        child = [slot for proof in proofs for slot in proof['slots'] if slot['key'].startswith('434:')]
        self.assertTrue(child)
        self.assertTrue(all(slot.get('canonical') for slot in child))


if __name__ == '__main__':
    unittest.main()
