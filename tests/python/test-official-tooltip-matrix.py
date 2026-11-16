"""Check all official directions are accounted for with native and derived provenance."""
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/source-scan'))
from official_tooltip_matrix import fingerprint, observations, run
from triage_official_tooltip_matrix import triage


class OfficialTooltipMatrixTests(unittest.TestCase):
    def test_selected_directions_keep_native_captures_from_another_locale(self):
        original = next(o for o in observations(ROOT / 'tests/fixtures/tooltip-campaign') if o['locale'] == 'frFR')
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
            report = run(ROOT / 'tests/fixtures/tooltip-campaign', Path(directory) / 'report',
                         case_keys={fingerprint(original)}, locales=('deDE', 'enUS'))
        self.assertEqual(report['cases'][0]['locale'], 'frFR')
        self.assertEqual(sum(report['counts'].values()), 2)
        self.assertEqual(set(report['byDirection']), {'deDE>enUS', 'enUS>deDE'})

    def test_real_french_english_pair_counts_both_directions_without_other_targets(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
            report = run(ROOT / 'tests/fixtures/tooltip-campaign', Path(directory) / 'report',
                         limit=1, locales=('frFR', 'enUS'))
        self.assertEqual(report['officialLocales'], ['enUS', 'frFR'])
        self.assertEqual(report['directionsPerCase'], 2)
        self.assertEqual(sum(report['counts'].values()), 2)
        self.assertEqual(set(report['byDirection']), {'enUS>frFR', 'frFR>enUS'})
        self.assertEqual(sum(report['byPath']['native_to_target'].values()), 1)
        self.assertEqual(sum(report['byPath']['return_to_native'].values()), 1)
        self.assertNotIn('cross_target', report['byPath'])

    def test_focused_real_capture_accounts_only_for_the_eighteen_locale_directions(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
            report = run(ROOT / 'tests/fixtures/tooltip-campaign', Path(directory) / 'report', limit=1, focus_locale='ptBR')
            self.assertEqual(report['directionsPerCase'], 18)
            self.assertEqual(sum(report['counts'].values()), 18)
            self.assertEqual(len(report['byDirection']), 18)
            self.assertTrue(all('ptBR' in direction.split('>') for direction in report['byDirection']))
            self.assertTrue(all('ptBR' in (event['source'], event['target']) for event in report['failures']))

    def test_bounded_real_capture_has_ninety_explicit_direction_results(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
            report = run(ROOT / 'tests/fixtures/tooltip-campaign', Path(directory) / 'report', limit=1)
            self.assertEqual(len(report['officialLocales']), 10)
            self.assertEqual(report['directionsPerCase'], 90)
            self.assertEqual(sum(report['counts'].values()), 90)
            self.assertEqual(len(report['byDirection']), 90)
            self.assertEqual(report['nativeStatus'], {'replayed': 1})
            self.assertTrue(report['cases'][0]['sources'])
            self.assertEqual(json.loads((Path(directory) / 'report/report.json').read_text()), report)
            failed = sum(count for status, count in report['counts'].items()
                         if status not in ('passed', 'text_difference_values_preserved'))
            self.assertEqual(len(report['failures']), failed)
            classified = triage(report, ROOT / 'tests/fixtures/tooltip-campaign')
            self.assertEqual(sum(classified['directionEventCounts'].values()), failed)
            for event in classified['events']:
                self.assertTrue(event['reference']['sha256'])
                if event['category'] == 'missing_owned_translation':
                    self.assertTrue(event['missingOwnedFields'])


if __name__ == '__main__':
    unittest.main()
