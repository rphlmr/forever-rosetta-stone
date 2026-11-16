"""The spell matrix verifies displayed values rather than reconstructed character values."""
import unittest
from id_only_spell_matrix import run_matrix


class IdOnlySpellMatrixTests(unittest.TestCase):
    def test_casts_and_auras_use_displayed_values_in_both_profiles(self):
        report=run_matrix(locales=['enUS','frFR'],ids=[970,6074,1310703],profiles=['baseline','modified'])
        self.assertFalse(report['mandatoryCoverage']['missingCases'])
        failures=[row for row in report['failures'] if row['field'] in ('description','auraDescription')]
        self.assertFalse(failures,failures[:4])
        self.assertIn('synthetic displayed values',report['inputContract'])

    def test_missing_targets_stay_failed_coverage(self):
        report=run_matrix(locales=['notALocale'],ids=[970],profiles=['baseline'])
        self.assertGreater(report['counts']['failed'],0)
        self.assertTrue(any(row.get('expectationDiagnostic',{}).get('category')=='missing_data'
                            for row in report['failures']))


if __name__=='__main__': unittest.main()
