"""Unverified expectations remain failures and never conceal real runtime errors."""

import unittest
import runpy
import copy
import tempfile
from pathlib import Path

from id_only_matrix_harness import CaseReporter
from matrix_classification import classify_failure, summarize_failures, summarize_report, write_summary_markdown


class MatrixClassificationTests(unittest.TestCase):
    def test_stage_status_separates_coverage_from_execution_failure(self):
        driver = runpy.run_path(str(Path(__file__).with_name('test-translation-matrix.py')))
        diagnostic = summarize_failures('spells', [{'reason': 'missing target translation'}])
        stage = {'passed': False, 'reports': [{'diagnostics': diagnostic, 'gaps': {}}]}
        self.assertEqual(driver['stage_status'](stage), 'coverage_incomplete')
        stage['reports'][0]['integrityErrors'] = ['Missing entity IDs']
        self.assertEqual(driver['stage_status'](stage), 'stage_error')
        stage['reports'] = []
        self.assertEqual(driver['stage_status'](stage), 'stage_error')

    def test_missing_data_and_checker_limits_are_distinct(self):
        for reason, category in (
            ('missing target translation', 'missing_data'),
            ('missing linked spell source description', 'missing_data'),
            ('missing verified client objective index', 'missing_data'),
            ('unverified structured row identity', 'test_limitation'),
            ('unsupported item trigger type', 'test_limitation'),
            ('offered objective amounts unavailable in test context', 'test_limitation'),
        ):
            with self.subTest(reason=reason):
                self.assertEqual(classify_failure('items', {'reason': reason})['category'], category)

    def test_unknown_reasons_require_investigation(self):
        self.assertEqual(classify_failure('spells', {'reason': 'oracle limitation: new reason'})['category'],
                         'unclassified')

    def test_runtime_errors_cannot_be_masked_by_missing_expectations(self):
        reporter = CaseReporter('spells', ['enUS'], ['baseline'])
        reporter.record({'id': 7, 'field': 'description', 'locale': 'enUS', 'profile': 'baseline'},
                        None, None, error='attempt to index nil', reason='oracle limitation: missing effect')
        row = reporter.failures[0]
        self.assertEqual(row['reason'], 'runtimeError')
        self.assertEqual(row['category'], 'addon_bug')
        self.assertEqual(row['expectationReason'], 'oracle limitation: missing effect')

    def test_invalid_fixture_identity_is_not_a_proven_addon_bug(self):
        case = {'id': 7, 'field': 'setName', 'locale': 'enUS', 'profile': 'baseline',
                'inputLimitation': 'unverified structured row identity'}
        reporter = CaseReporter('items', ['enUS'], ['baseline'])
        self.assertFalse(reporter.record(case, 'Target', None))
        self.assertEqual(reporter.failures[0]['category'], 'test_limitation')
        self.assertEqual(reporter.counts['failed'], 1)

    def test_proven_mismatch_and_forbidden_calls_remain_bugs(self):
        for reason in ('mismatch', 'runtimeError', 'forbiddenDependency'):
            with self.subTest(reason=reason):
                self.assertEqual(classify_failure('spells', {'reason': reason})['category'], 'addon_bug')

    def test_oracle_diagnostics_preserve_specific_dependency_evidence(self):
        row = {'reason': 'oracle limitation: missing scaling levels', 'expectationDiagnostic': {
            'category': 'missing_data', 'code': 'missing_scaling_metadata',
            'evidence': {'record': '7', 'fields': ['baseLevel']}}}
        classified = classify_failure('spells', row)
        self.assertEqual(classified['category'], 'missing_data')
        self.assertEqual(classified['code'], 'missing_scaling_metadata')
        row['expectationDiagnostic']['category'] = 'test_limitation'
        self.assertEqual(classify_failure('spells', row)['category'], 'test_limitation')

    def test_counts_and_unique_targets_do_not_double_count_profiles(self):
        rows = [{'id': 7, 'field': 'description', 'locale': 'enUS', 'profile': profile,
                 'reason': 'missing target translation'} for profile in ('baseline', 'modified')]
        summary = summarize_failures('spells', rows)
        self.assertEqual(summary['unverifiedCases'], 2)
        self.assertEqual(summary['buckets']['missing_data']['cases'], 2)
        self.assertEqual(summary['buckets']['missing_data']['affectedTargets'], 1)
        self.assertEqual(sum(x['cases'] for x in summary['buckets'].values()), 2)

    def test_report_retains_completeness_gate_and_rejects_lost_cases(self):
        rows = [{'id': 7, 'field': 'description', 'locale': 'enUS', 'profile': 'baseline',
                 'reason': 'missing target translation'}]
        report = {'kind': 'spells', 'counts': {'cases': 3, 'passed': 2, 'failed': 1}, 'failures': rows}
        summary = summarize_report(report)
        self.assertEqual(summary['verifiedCases'], 2)
        self.assertFalse(summary['coverageComplete'])
        report['counts']['failed'] = 2
        with self.assertRaises(ValueError):
            summarize_report(report)

    def test_entity_namespaces_and_stale_annotations_are_preserved(self):
        rows = [{'id': 7, 'entityKind': kind, 'field': 'name', 'locale': 'frFR',
                 'reason': 'missing target translation'} for kind in ('items', 'spells')]
        self.assertEqual(summarize_failures('catalogs', rows)['buckets']['missing_data']['affectedTargets'], 2)
        rows[0]['category'] = 'addon_bug'
        with self.assertRaises(ValueError):
            summarize_failures('catalogs', rows)

    def test_markdown_explains_unverified_row_without_changing_evidence(self):
        rows = [{'id': 7, 'field': 'setBonus', 'locale': 'frFR', 'profile': 'baseline',
                 'reason': 'untranslated', 'inputLimitation': 'unverified structured row identity'},
                {'id': 8, 'field': 'effect', 'locale': 'frFR', 'profile': 'baseline',
                 'reason': 'missing linked spell source description'}]
        summary = summarize_failures('items', rows)
        classification = {'caseReports': [{'kind': 'items', 'diagnostics': summary}]}
        before = copy.deepcopy(classification)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'report.md'
            write_summary_markdown(path, classification)
            text = path.read_text()
        self.assertIn('| items | unverified native row identity | 1 |', text)
        self.assertNotIn('| items | untranslated |', text)
        self.assertIn('execution link alone', text)
        self.assertIn('remain failed', text)
        self.assertEqual(classification, before)
        self.assertEqual(summary['unverifiedCases'], 2)
        self.assertEqual(next(group for group in summary['groups']
                              if group['code'] == 'unverified_row_identity')['reason'], 'untranslated')


if __name__ == '__main__':
    unittest.main()
