"""Guard the pilot's enumeration and detect corrupted production renderers."""

import copy
import runpy
import unittest
from pathlib import Path
from unittest.mock import patch

from id_only_matrix_harness import IdOnlyHarness
from template_pilot_common import PilotCases, pilot_locales
import template_pilot_labels as labels
import template_pilot_npcs as npcs
import template_pilot_spells as spells

DRIVER = runpy.run_path(str(Path(__file__).with_name('test-template-pilot.py')))


class PilotHarnessTests(unittest.TestCase):
    def test_source_inventory_matches_official_locales_not_additional_targets(self):
        sources, targets = pilot_locales()
        self.assertEqual(len(sources), 10)
        self.assertEqual(len(targets), 18)
        self.assertNotIn('itIT', sources)
        self.assertIn('itIT', targets)

    def test_missing_duplicate_and_invalid_passing_cases_are_rejected(self):
        report = labels.run_matrix(['enUS'], ['frFR'], ['baseline', 'modified'])
        validate = lambda report: DRIVER['validate_report'](report, ['enUS'], ['frFR'], ['baseline', 'modified'])
        self.assertEqual(validate(report), [])
        for mutation in ('omit', 'duplicate', 'corrupt'):
            changed = copy.deepcopy(report)
            if mutation == 'omit':
                changed['cases'].pop()
            elif mutation == 'duplicate':
                changed['cases'].append(changed['cases'][0])
            else:
                changed['cases'][0]['actual'] = 'Corrupt output accepted as a pass'
            with self.subTest(mutation=mutation):
                self.assertTrue(validate(changed))

    def test_reporter_never_accepts_missing_expectations_or_runtime_errors(self):
        cases = PilotCases('test')
        self.assertFalse(cases.check({}, None, None))
        self.assertFalse(cases.check({}, 'Expected', 'Expected', error='runtime failure'))
        self.assertFalse(cases.check({}, 'Expected', 'Expected', reason='incomplete', category='addon_bug'))
        self.assertEqual(cases.finish({})['counts']['failed'], 3)

    def test_rank_omissions_cannot_hide_behind_the_same_spell_id(self):
        report = spells.run_matrices(['enUS'], ['frFR'], ['baseline'])[2]
        self.assertEqual(DRIVER['validate_report'](report, ['enUS'], ['frFR'], ['baseline']), [])
        report['cases'][1]['rank'] = report['cases'][0]['rank']
        self.assertTrue(DRIVER['validate_report'](report, ['enUS'], ['frFR'], ['baseline']))

    def test_globalstring_corruption_is_detected(self):
        class CorruptedHarness(IdOnlyHarness):
            def __init__(self):
                super().__init__()
                self.lua.execute(b"addon.FillEnglishTooltip=function(_,spec) spec.tip:AddLine('Corrupted') end")

        with patch.object(labels, 'IdOnlyHarness', CorruptedHarness):
            report = labels.run_matrix(['enUS'], ['frFR'], ['baseline'])
        self.assertEqual(report['counts']['failed'], 1)
        self.assertEqual(report['counts']['passed'], 1)

    def test_npc_rows_and_footer_are_checked(self):
        report = npcs.run_matrix(['enUS', 'frFR'], ['enUS', 'frFR'], ['baseline', 'modified'])
        self.assertEqual(report['counts'], {'cases': 32, 'passed': 32, 'failed': 0})
        self.assertEqual(DRIVER['validate_report'](report, ['enUS', 'frFR'], ['enUS', 'frFR'],
                                                  ['baseline', 'modified']), [])
        class CorruptedHarness(IdOnlyHarness):
            def _load(self, path, addon):
                super()._load(path, addon)
                if path.name == 'npc-tooltip.lua':
                    self.lua.execute(b"addon.FillNpcTooltip=function(_,spec) spec.tip:AddLine('Corrupted') end")

        with patch.object(npcs, 'IdOnlyHarness', CorruptedHarness):
            report = npcs.run_matrix(['enUS'], ['frFR'], ['baseline'])
        self.assertEqual(report['counts']['failed'], 4)


if __name__ == '__main__':
    unittest.main()
