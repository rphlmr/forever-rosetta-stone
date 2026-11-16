"""Replay the reported Hearthstone; geographical labels never select an inferred area ID."""
import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/source-scan'))
from audit_tooltip_hovers import restore
import official_tooltip_matrix as matrix
import report_tooltip_gaps as gaps


class CapturedBindLocationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.capture = restore(json.loads((ROOT / 'tests/fixtures/tooltip-campaign/item-6948-frFR-bind-location.json').read_text()))

    def test_real_bind_label_translates_in_every_official_target_without_inventing_api_state(self):
        original = copy.deepcopy(self.capture)
        replay = gaps.Replay('frFR', {})
        for target in sorted(matrix.OFFICIAL_LOCALES - {'frFR'}):
            with self.subTest(target=target):
                missing, error, _ = replay.run('item', 6948, gaps.clean(self.capture['data']), target,
                    gaps.clean(self.capture['processingInfo']), matrix.visible(self.capture['visible']))
                self.assertIsNone(error)
                self.assertEqual(missing, [])
                rows, error = matrix.read_rendered(replay)
                self.assertIsNone(error)
                destination = replay.database.TranslateLocationLabel(replay.database,
                    'Comté-de-l’Or'.encode(), b'frFR', target.encode()).decode()
                self.assertTrue(any(destination in (row['left'] or '') for row in rows))
                if target == 'enUS':
                    self.assertEqual(destination, 'Goldshire')
                    self.assertFalse(any('Comté' in (row['left'] or '') for row in rows))
        self.assertEqual(self.capture, original)

    def test_real_ambiguous_area_wording_has_no_guessed_translation(self):
        replay = gaps.Replay('frFR', {})
        self.assertIsNone(replay.database.TranslateLocationLabel(replay.database, 'Gilnéas'.encode(), b'frFR', b'enUS'))
        self.assertIsNone(replay.database.TranslateLocationLabel(replay.database, b'<uncaptured location>', b'frFR', b'enUS'))


if __name__ == '__main__':
    unittest.main()
