"""Small reverse-case generation pilot derived from five real French spell captures."""
import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/source-scan'))
from audit_tooltip_hovers import restore
from roundtrip_tooltip_campaign import roundtrip


class TooltipRoundtripTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        capture = restore(json.loads((ROOT / 'tests/fixtures/tooltip-campaign/1.60.1.70938-frFR.json').read_text()))
        original = copy.deepcopy(capture)
        cls.report = roundtrip(capture, 12, [6074, 970, 2054, 598, 17])
        assert capture == original, 'Derived cases must not rewrite the original capture'

    def test_every_target_translates_the_native_rows_and_reverses_the_derived_output(self):
        self.assertIn('ltLT', self.report['scope']['targets'])
        self.assertEqual(len(self.report['scope']['targets']), 18)
        self.assertEqual(len(self.report['cases']), 90)
        for case in self.report['cases']:
            with self.subTest(spell=case['id'], target=case['target']):
                self.assertIn(case['status'], ('passed', 'text_difference_values_preserved'), case)
                self.assertEqual(case['origin'], 'derived-from-native-capture')
                self.assertTrue(case['translated'] and case['returned'])
                for data, rendered in zip(case['derivedData']['lines'], case['translated']):
                    self.assertEqual(data.get('leftText'), rendered['left'])
                    self.assertEqual(data.get('rightText'), rendered['right'])

    def test_mexican_spanish_uses_its_owned_decimal_separator_and_preserves_cast_time(self):
        case = next(case for case in self.report['cases'] if case['id'] == 598 and case['target'] == 'esMX')
        self.assertEqual(self.report['derivedLocaleContext']['labels']['esMX']['DECIMAL_SEPERATOR'], '.')
        self.assertIn('Lanzamiento de 2.5 s', [row['left'] for row in case['translated']])
        self.assertIn('2,5 s d’incantation', [row['left'] for row in case['returned']])


if __name__ == '__main__':
    unittest.main()
