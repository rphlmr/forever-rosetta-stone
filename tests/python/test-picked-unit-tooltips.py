"""Pick unit fields and owned quest blocks from the real Riverpaw Bandit capture."""
import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/source-scan'))
from audit_tooltip_hovers import restore
import report_tooltip_gaps as gaps


class PickedUnitTooltipTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.capture = restore(json.loads((ROOT / 'tests/fixtures/tooltip-campaign/npc-452-frFR.json').read_text()))

    def render(self, capture, locale='enUS'):
        replay = gaps.Replay('frFR', {}, tooltip_types=capture['enumDefinitions']['dataTypes'])
        replay.install_calls({}, capture['unit'])
        rows, error, _ = replay.run('npc', 452, gaps.clean(capture['data']), locale, unit=capture['unit'])
        self.assertIsNone(error)
        return rows, [(row[b'left'] or b'').decode() for row in replay.lua.globals().ReplayLastRendered.values()]

    def test_real_npc_capture_keeps_quest_title_objective_and_counts_without_extra_rows(self):
        original = copy.deepcopy(self.capture)
        missing, lines = self.render(self.capture)
        self.assertEqual(missing, [])
        self.assertEqual(lines, ['Riverpaw Bandit', 'Level 17', 'Humanoid', 'Patrolling Westfall', 'Gnoll Paw: 0/8'])
        self.assertEqual(self.capture, original)

    def test_unowned_quest_objective_stays_visible_and_incomplete(self):
        capture = copy.deepcopy(self.capture)
        title = next(line for line in capture['data']['lines'].values() if line.get('type') == 17)
        title['id'] = -1
        missing, lines = self.render(capture)
        self.assertTrue(missing)
        self.assertTrue(any('0/8' in line for line in lines))

    def test_inconsistent_live_counts_cannot_be_replaced_by_catalog_counts(self):
        capture = copy.deepcopy(self.capture)
        objective = next(line for line in capture['data']['lines'].values() if line.get('type') == 8)
        objective['numFulfilled'] = 1
        missing, lines = self.render(capture)
        self.assertTrue(missing)
        self.assertTrue(any('0/8' in line for line in lines))


if __name__ == '__main__':
    unittest.main()
