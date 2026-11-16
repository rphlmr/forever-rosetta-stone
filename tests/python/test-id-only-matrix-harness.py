"""Prove strict accounting and native matching guards cannot report false coverage success."""

import runpy
import json
import unittest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from id_only_matrix_harness import CaseReporter, IdOnlyHarness, NATIVE_TEXT


driver = runpy.run_path(str(Path(__file__).with_name('test-id-only-matrix.py')))
matrix_driver = runpy.run_path(str(Path(__file__).with_name('test-translation-matrix.py')))


class IdOnlyHarnessTests(unittest.TestCase):
    def test_spell_shards_keep_failures_in_the_merged_report(self):
        reports = [{'shardIndex': index, 'shardCount': 3, 'totalCatalogCount': 3,
                    'spells': 1, 'spellIds': [index + 3], 'clientLocales': ['enUS'],
                    'targetLocales': ['enUS'], 'counts': {'cases': 1, 'passed': 0, 'failed': 1},
                    'unrenderable': [], 'errors': [{'id': index + 3, 'reason': 'mismatch'}]}
                   for index in range(3)]
        merged = matrix_driver['merge_spell_reports'](reports, {3, 4, 5})
        self.assertEqual(merged['counts'], {'cases': 3, 'passed': 0, 'failed': 3})
        self.assertEqual(len(merged['errors']), 3)
        reports[1]['spellIds'] = [3]
        with self.assertRaises(ValueError):
            matrix_driver['merge_spell_reports'](reports, {3, 4, 5})

    @classmethod
    def setUpClass(cls):
        cls.harness = IdOnlyHarness()

    def setUp(self):
        self.harness.set_context('frFR', 744, 'baseline')

    def test_player_level_is_context_while_stat_recalculation_stays_forbidden(self):
        actual, error, forbidden = self.harness.attempt(lambda: self.harness.lua.globals().UnitLevel(b'player'))
        self.assertEqual(actual, 1)
        self.assertIsNone(error)
        self.assertFalse(forbidden)
        _, _, forbidden = self.harness.attempt(lambda: self.harness.lua.globals().UnitStat(b'player', 1))
        self.assertEqual(forbidden, ['recalculation:UnitStat'])

    def test_matching_fields_are_removed_but_numeric_data_is_retained(self):
        record = self.harness.db.GetSpellDetails(self.harness.db, 744, b'enUS')
        self.assertIsNone(record[b'sourceDescriptions'])
        self.assertEqual(record[b'effects'][1][b'periodMs'], 3000)
        self.assertTrue(record[b'description'])

    def test_row_types_match_the_pinned_client_inventory(self):
        inventory = json.loads((Path(__file__).parent.parent / 'fixtures/tooltip-inventory-70862.json').read_text())
        line_types = self.harness.lua.globals().Enum[b'TooltipDataLineType']
        for name, actual in line_types.items():
            self.assertEqual(actual, inventory['line_types'].index(name.decode()))
        self.assertIsNone(line_types[b'ItemSetBonus'])

    def test_source_access_fails_even_if_production_catches_the_exception(self):
        run = self.harness.lua.eval(b'''function()
            pcall(ForeverRosettaStoneDB.GetSpellSourceDetails, ForeverRosettaStoneDB, 744, 'frFR')
            return 'correct'
        end''')
        actual, error, forbidden = self.harness.attempt(run)
        self.assertIsNone(error)
        reporter = CaseReporter('spells', ['frFR'], ['baseline'])
        reporter.record({'id': 744, 'field': 'name', 'locale': 'frFR', 'profile': 'baseline'},
                        'correct', actual, error, forbidden)
        self.assertEqual(reporter.counts['forbiddenDependency'], 1)
        self.assertEqual(reporter.counts['passed'], 0)

    def test_unknown_rows_stay_untranslated_even_if_a_source_getter_is_replaced(self):
        original = self.harness.db.GetSpellSourceDetails

        try:
            self.harness.lua.execute(b'''ForeverRosettaStoneDB.GetSpellSourceDetails = function() return {} end''')
            line = self.harness.to_lua({'leftText': NATIVE_TEXT})
            actual, error, forbidden = self.harness.attempt(lambda: self.harness.addon.GetLocalizedTooltipLine(
                self.harness.addon, line, b'spell', 744, b'frFR'))
            self.assertIsNone(error)
            self.assertFalse(forbidden)
            reporter = CaseReporter('spells', ['frFR'], ['baseline'])
            self.assertFalse(reporter.record(
                {'id': 744, 'field': 'description', 'locale': 'frFR', 'profile': 'baseline'}, 'Translated', actual))
            self.assertEqual(reporter.counts['failed'], 1)
        finally:
            self.harness.db.GetSpellSourceDetails = original

    def test_missing_wrong_native_and_incomplete_values_all_fail(self):
        case = {'id': 1, 'field': 'name', 'locale': 'frFR', 'profile': 'baseline'}
        for actual in (None, '', 'wrong', NATIVE_TEXT, ('correct', None, True)):
            reporter = CaseReporter('spells', ['frFR'], ['baseline'])
            self.assertFalse(reporter.record(case, 'correct', actual))
            self.assertEqual(reporter.counts['failed'], 1)
        reporter = CaseReporter('spells', ['frFR'], ['baseline'])
        self.assertFalse(reporter.record(case, None, 'some output'))
        self.assertEqual(reporter.counts['missingTranslation'], 1)

    def test_complete_render_result_and_missing_enumeration_are_distinct(self):
        case = {'id': 1, 'field': 'name', 'locale': 'frFR', 'profile': 'baseline'}
        reporter = CaseReporter('spells', ['frFR'], ['baseline'])
        self.assertTrue(reporter.record(case, 'correct', (b'correct', None, None)))
        report = reporter.finish([1])
        self.assertFalse(driver['validate_report'](report, 'spells', [1], ['frFR'], ['baseline']))
        report = reporter.finish([1, 2])
        self.assertIn('mandatory name/title cases were omitted',
                      driver['validate_report'](report, 'spells', [1, 2], ['frFR'], ['baseline']))

    def test_duplicate_mandatory_cases_cannot_hide_an_omission(self):
        case = {'id': 1, 'field': 'name', 'locale': 'frFR', 'profile': 'baseline'}
        reporter = CaseReporter('items', ['frFR', 'deDE'], ['baseline'])
        reporter.record(case, 'correct', 'correct')
        reporter.record(case, 'correct', 'correct')
        report = reporter.finish([1])
        self.assertTrue(report['mandatoryCoverage']['missingCases'])
        self.assertTrue(report['interfaceErrors'])

    def test_not_applicable_fields_are_not_counted_as_passes(self):
        reporter = CaseReporter('items', ['enUS', 'frFR'], ['baseline'])
        for locale in ('enUS', 'frFR'):
            reporter.not_applicable({'id': 1, 'field': 'description', 'locale': locale,
                                     'profile': 'baseline'}, 'absent in every locale')
        report = reporter.finish([])
        self.assertEqual(report['counts']['passed'], 0)
        self.assertEqual(report['counts']['notApplicable'], 2)
        self.assertEqual(len(report['notApplicable']), 1)
        self.assertEqual(report['notApplicable'][0]['caseCount'], 2)


if __name__ == '__main__':
    unittest.main()
