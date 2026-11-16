"""Regression checks for the bounded live spell, aura, and talent pilots."""
import itertools
import copy
import unittest
from unittest.mock import patch

import template_pilot_spells as pilot


class TemplatePilotSpellTests(unittest.TestCase):
    def test_every_source_target_profile_and_talent_rank_is_retained(self):
        sources, targets, profiles = ['enUS', 'frFR'], ['enUS', 'frFR'], ['baseline', 'modified']
        reports = pilot.run_matrices(sources, targets, profiles)
        combinations = set(itertools.product(sources, targets, profiles))
        for report in reports:
            cases = report['cases']
            self.assertEqual(report['expectedCases'], len(cases))
            for entity in report['selection'].get('ranks', [{'spellId': entity_id, 'rank': None}
                                                            for entity_id in report['selection']['ids']]):
                actual = [(case['sourceLocale'], case['targetLocale'], case['profile'])
                          for case in cases if case['id'] == entity['spellId'] and case.get('rank') == entity['rank']]
                self.assertEqual(len(actual), len(combinations))
                self.assertEqual(set(actual), combinations)
        talent = reports[2]
        self.assertEqual([entry['rank'] for entry in talent['selection']['ranks']], [1, 2, 3])
        self.assertEqual(talent['selection']['ids'], [17783])
        self.assertEqual(talent['counts']['failed'], 0)
        for rank, value in ((1, 23), (2, 47), (3, 70)):
            cases = [case for case in talent['cases'] if case['rank'] == rank]
            self.assertTrue(all(str(value) in case['sourceText'] and str(value) in case['actual'] for case in cases))

    def test_legacy_rank_links_do_not_create_trait_ranks(self):
        talent = {'spellId': 17783, 'spellRankIds': [17783, 17784, 17785, 17786, 17787]}
        contexts = pilot.talent_rank_contexts(talent)
        self.assertEqual([(row['spellId'], row['rank']) for row in contexts],
                         [(17783, 1), (17783, 2), (17783, 3)])
        import json
        evidence = json.loads(pilot.TALENT_FIXTURE.read_text())
        missing = copy.deepcopy(evidence)
        missing['curvePoints'] = [point for point in missing['curvePoints'] if point['rank'] != 2]
        with self.assertRaisesRegex(ValueError, 'verified override value'):
            pilot.talent_rank_contexts(talent, missing)
        with self.assertRaisesRegex(ValueError, 'no verified trait rank'):
            pilot.talent_rank_contexts({'spellId': 999999}, evidence)

    def test_production_output_corruption_fails_independent_expectation(self):
        original = pilot._renderer

        def corrupt(harness):
            render = original(harness)

            def changed(*args):
                actual, incomplete = render(*args)
                return actual + b' corrupted' if actual else actual, incomplete
            return changed

        with patch.object(pilot, '_renderer', side_effect=corrupt):
            reports = pilot.run_matrices(['frFR'], ['enUS'], ['baseline'])
        for report in reports:
            case = report['cases'][0]
            self.assertEqual(case['status'], 'failed')
            self.assertEqual(case['category'], 'addon_bug')
            self.assertNotEqual(case['expected'], case['actual'])


if __name__ == '__main__':
    unittest.main()
