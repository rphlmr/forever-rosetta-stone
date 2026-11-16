"""Focused checks for quest pilot enumeration and independent expectations."""

import unittest
from unittest.mock import patch

from id_only_matrix_harness import IdOnlyHarness

from template_pilot_quests import expected_text, run_matrix


class QuestPilotTests(unittest.TestCase):
    def test_pairs_profiles_and_target_only_objectives_are_counted(self):
        report = run_matrix(['enUS', 'frFR'], ['enUS', 'frFR'], ['baseline', 'modified'])
        self.assertEqual(report['expectedCases'], 32)
        self.assertEqual(report['counts']['cases'], 32)
        identities = {(c['sourceLocale'], c['targetLocale'], c['profile'], c['field'])
                      for c in report['cases']}
        self.assertEqual(len(identities), 32)
        objective = [c for c in report['cases'] if c['field'] == 'objectiveLines.1']
        self.assertTrue(all(c['status'] == 'passed' for c in objective))
        self.assertTrue(all(c['actual'] == c['expected'] for c in objective))

    def test_corrupt_formatter_is_detected(self):
        class CorruptedHarness(IdOnlyHarness):
            def __init__(self):
                super().__init__()
                self.lua.execute(b"addon.FormatQuestText = function() return 'CORRUPTED' end")

        with patch('template_pilot_quests.IdOnlyHarness', CorruptedHarness):
            report = run_matrix(['enUS'], ['frFR'], ['baseline'])
        self.assertEqual(report['counts']['failed'], report['expectedCases'])
        self.assertTrue(all(c.get('category') == 'addon_bug' for c in report['cases']))

    def test_expected_values_change_with_context(self):
        template = '{name}: {class}, $1oa'
        self.assertEqual(expected_text(template, 'enUS', 'frFR', 'baseline', 'summary')[0],
                         'Alice: Guerrier, 5')
        self.assertEqual(expected_text(template, 'enUS', 'frFR', 'modified', 'summary')[0],
                         'Bianca: Guerrière, 9')
        self.assertEqual(expected_text(template, 'frFR', 'frFR', 'modified', 'summary')[0],
                         'Bianca: NativeWarrior, 9')
        self.assertIsNotNone(expected_text('$unhandled', 'enUS', 'frFR', 'baseline', 'summary')[1])


if __name__ == '__main__':
    unittest.main()
