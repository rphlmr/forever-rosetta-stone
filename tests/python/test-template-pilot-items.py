"""Regression tests for the scoped item template pilot."""

import copy
import unittest
from unittest.mock import patch

import template_pilot_items as pilot


class ItemPilotTests(unittest.TestCase):
    def test_enumerates_pairs_profiles_and_fields(self):
        sources = ['enUS', 'frFR']
        targets = ['enUS', 'frFR']
        profiles = ['baseline', 'modified']
        report = pilot.run_matrix(sources, targets, profiles)
        identities = {(row['sourceLocale'], row['targetLocale'], row['profile'], row['field'])
                      for row in report['cases']}
        expected = {(source, target, profile, field) for source in sources for target in targets
                    for profile in profiles for field in ('name', 'effect')}
        self.assertEqual(identities, expected)
        self.assertEqual(report['expectedCases'], len(expected))
        self.assertEqual(report['counts']['cases'], len(expected))
        self.assertEqual(report['counts']['failed'], 0)

    def test_corrupted_production_effect_fails_against_expected(self):
        with patch.object(pilot, 'render_line', return_value=b'corrupted production text'):
            report = pilot.run_matrix(['enUS'], ['frFR'], ['baseline'])
        effect = next(row for row in report['cases'] if row['field'] == 'effect')
        self.assertEqual(effect['status'], 'failed')
        self.assertEqual(effect['actual'], 'corrupted production text')
        self.assertEqual(effect['expected'], 'Utiliser : Rend 21 points de vie. (2 min de recharge.)')
        self.assertEqual(effect['sourceText'], 'Use: Restores 21 health. (2 Min Cooldown)')

    def test_missing_official_source_text_is_a_warning(self):
        original = pilot.load_referenced_spells
        def missing_source(*args):
            records = copy.deepcopy(original(*args))
            del records[str(pilot.SPELL_ID)]['locales']['frFR']['description']
            return records
        with patch.object(pilot, 'load_referenced_spells', side_effect=missing_source):
            report = pilot.run_matrix(['frFR'], ['enUS'], ['baseline'])
        effect = next(row for row in report['cases'] if row['field'] == 'effect')
        self.assertEqual(effect['status'], 'warning')
        self.assertEqual(effect['reason'], 'official_source_absent')
        self.assertIsNone(effect['sourceText'])


if __name__ == '__main__':
    unittest.main()
