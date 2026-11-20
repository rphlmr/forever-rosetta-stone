"""Decode native percentage literals without replacing the client's displayed value."""
import contextlib
import io
from pathlib import Path
import sys
import tempfile
import unittest

from live_value_harness import LiveValueHarness, ROOT

sys.path.insert(0, str(ROOT / 'tools/source-scan'))
import official_tooltip_matrix as matrix


class CapturedLiteralPercentageTests(LiveValueHarness, unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        observations = list(matrix.observations(ROOT / 'tests/fixtures/tooltip-campaign'))
        cls.observations = [o for o in observations
                            if o['kind'] == 'spell' and o['id'] == 451439]
        keys = {matrix.fingerprint(o) for o in cls.observations}
        (ROOT / 'datasources/imports').mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / 'datasources/imports') as directory:
            with contextlib.redirect_stdout(io.StringIO()):
                cls.report = matrix.run_observations(observations, Path(directory) / 'report', case_keys=keys)

    def native(self, locale):
        observation = next(o for o in self.observations if o['locale'] == locale)
        return next(row['leftText'] for row in observation['data']['lines'] if row['type'] == 34)

    def test_native_cases_pass_all_official_directions(self):
        self.assertEqual(self.report['selectedCases'], 8)
        self.assertEqual(self.report['counts'], {'passed': 720})
        self.assertFalse(self.report['failures'])

    def test_each_native_percentage_survives_both_directions(self):
        german, english = self.native('deDE'), self.native('enUS')
        self.assertIn('1%', german)
        self.assertIn('20%', english)
        for native, source, target, percentage in ((german, 'deDE', 'enUS', b'1%'),
                                                   (english, 'enUS', 'deDE', b'20%')):
            with self.subTest(source=source):
                translated = self.capture(451439, native, source, target)
                self.assertIsNotNone(translated)
                self.assertIn(percentage, translated)
                restored = self.capture(451439, translated.decode(), target, source)
                self.assertEqual(restored, native.encode())

    def test_missing_or_symbolic_percentage_cannot_supply_a_number(self):
        # Fault-injected derivatives of the native capture, never native fixtures.
        native = self.native('deDE')
        for value in ('', '$b1', 'unknown'):
            with self.subTest(value=value):
                self.assertIsNone(self.capture(451439, native.replace('1%', value + '%'), 'deDE', 'enUS'))
        self.assertIsNone(self.capture(451439, native.replace('10 Energie', 'unknown Energie'), 'deDE', 'enUS'))

    def test_two_literal_percentages_do_not_create_an_implicit_binding(self):
        # Mutate the owned template and its matching capture together to exercise
        # ambiguity rejection; no new game wording is claimed by this derivative.
        self.lua.execute(b'''
            local original = ForeverRosettaStoneDB.GetSpellDetails
            ForeverRosettaStoneDB.GetSpellDetails = function(self, id, locale)
                local details = original(self, id, locale)
                if id ~= 451439 or locale ~= 'deDE' then return details end
                local changed = {}
                for key, value in pairs(details) do changed[key] = value end
                changed.description = details.description:gsub('1%%', '1%% 2%%')
                return changed
            end
        ''')
        derived = self.native('deDE').replace('1%', '1% 2%')
        self.assertIsNone(self.capture(451439, derived, 'deDE', 'enUS'))


if __name__ == '__main__':
    unittest.main()
