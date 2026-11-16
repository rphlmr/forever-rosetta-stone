"""Replay current client talent wording against its owned description template."""
import json
from pathlib import Path
import sys
import unittest

from live_value_harness import LiveValueHarness

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/source-scan'))
import official_tooltip_matrix as matrix
import report_tooltip_gaps as gaps


class TalentDescriptionSourceTests(LiveValueHarness, unittest.TestCase):
    def test_exported_nonbreaking_spaces_match_live_typography(self):
        self.lua.globals().records(900090, b'Bonus $s1\\xa0%.', b'Bonus $s1%.')
        self.assertEqual(self.capture(900090, 'Bonus 4 %.'), b'Bonus 4%.')
        self.assertEqual(self.capture(900090, 'Bonus 4%.', 'enUS', 'frFR'),
                         'Bonus 4 %.'.encode())

    def test_french_soul_siphon_preserves_live_values_in_english(self):
        fixture = json.loads((ROOT / 'tests/fixtures/tooltip-campaign/talent-17804-frFR.json').read_text())
        replay = gaps.Replay('frFR', {})
        missing, error, _ = replay.run('spell', 17804, gaps.clean(fixture['data']), 'enUS',
                                     fixture['processingInfo'], matrix.visible(fixture['visible']))
        self.assertIsNone(error)
        self.assertEqual(missing, [])
        rows, error = matrix.read_rendered(replay)
        self.assertIsNone(error)
        text = '\n'.join(row['left'] or '' for row in rows)
        self.assertIn('Soul Siphon', text)
        self.assertIn('by 4% per each of your Corruption, Siphon Life, and Bane of Agony', text)
        self.assertIn('maximum increase of 12%.', text)
        self.assertNotIn('Augmente', text)


if __name__ == '__main__':
    unittest.main()
