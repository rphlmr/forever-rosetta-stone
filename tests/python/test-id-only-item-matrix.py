"""Focused enumeration and expectation tests for the item ID-only matrix."""

import unittest
from unittest.mock import patch

import id_only_item_matrix as matrix
from id_only_matrix_harness import CaseReporter, NATIVE_TEXT


class FakeReporter:
    def __init__(self, kind, locales, profiles):
        self.cases = []
        self.absent = []

    def record(self, case, expected, actual, error=None, forbidden=None, reason=None):
        self.cases.append((case, expected, actual, error, forbidden, reason))

    def not_applicable(self, case, reason):
        self.absent.append((case, reason))

    def finish(self, entity_ids, exclusions=None, full_scope=True):
        return {'cases': self.cases, 'absent': self.absent, 'ids': list(entity_ids)}


class FakeHarness:
    actual = 'Use: Deals 45 damage.'
    forbidden = []

    def __init__(self, root=None):
        self.db = self
        self.profile = {'level': 1, 'spirit': 20, 'spellPower': 0}

    def set_context(self, locale, entity_id, profile, entity_kind=None):
        pass

    def set_source_locale(self, locale):
        pass

    def GetItemName(self, db, entity_id, locale):
        return 'Item'

    def attempt(self, call):
        try:
            return call(), None, self.forbidden
        except Exception as error:
            return None, str(error), self.forbidden


class IdOnlyItemMatrixTests(unittest.TestCase):
    def setUp(self):
        self.item = {'locales': {'enUS': {'name': 'Item'}}, 'tooltipData': {
            'effects': [{'spellID': 7, 'triggerType': 0}],
        }}
        self.spells = {'7': {'locales': {'enUS': {'description': 'Deals $s1 damage.', 'translationMetadata': {'fields': {'description': {'origin': 'original'}}}}},
                             'tooltipData': {'effects': [{'index': 0, 'basePoints': 5}]}}}
        FakeHarness.actual = 'Use: Deals 45 damage.'
        FakeHarness.forbidden = []

    def run_fixture(self):
        self.rendered_rows = []

        def load(root, kind, ids=None):
            return {'catalogs': {kind: {'1': self.item} if kind == 'items' else self.spells}}

        def render(harness, item_id, locale, line):
            self.rendered_rows.append(line)
            return FakeHarness.actual

        with patch.object(matrix, 'load_catalog', side_effect=load), \
                patch.object(matrix, 'IdOnlyHarness', FakeHarness), \
                patch.object(matrix, 'CaseReporter', FakeReporter), \
                patch.object(matrix, 'get_format', return_value='Use:'), \
                patch.object(matrix, 'render_line', side_effect=render):
            return matrix.run_matrix(locales=['enUS'], ids=[1], profiles=['baseline'])

    def test_owned_effect_is_rendered_and_enumerated(self):
        report = self.run_fixture()
        effect = next(row for row in report['cases'] if row[0]['field'] == 'effect')
        self.assertEqual(effect[1:3], ('Use: Deals 45 damage.', 'Use: Deals 45 damage.'))
        self.assertEqual(effect[0]['effectSpellId'], 7)
        self.assertEqual({row[0]['field'] for row in report['absent']},
                         {'description', 'nameDescription', 'setName'})

    def test_wrong_value_is_visible(self):
        FakeHarness.actual = 'Use: Deals 9 damage.'
        effect = self.run_fixture()['cases'][-1]
        self.assertNotEqual(effect[1], effect[2])

    def test_rows_use_verified_client_types_without_inventing_set_bonus_type(self):
        self.item['locales']['enUS']['description'] = 'Flavor'
        self.item['tooltipData']['effects'] += [
            {'spellID': 7, 'triggerType': 1}, {'spellID': 7, 'triggerType': 2},
        ]
        self.item['tooltipData']['set'] = {'bonuses': [{'spellID': 7, 'threshold': 2}]}
        self.run_fixture()
        self.assertEqual([line.get('type') for line in self.rendered_rows], [37, 44, 45, 46, None])

    def test_missing_target_is_not_omitted(self):
        self.item['locales']['enUS']['description'] = None
        self.item['locales']['frFR'] = {'description': 'Description'}
        rows = self.run_fixture()['cases']
        description = next(row for row in rows if row[0]['field'] == 'description')
        self.assertEqual(description[5], 'missing target translation')

    def test_missing_referenced_spell_is_not_omitted(self):
        self.spells = {}
        effect = next(row for row in self.run_fixture()['cases'] if row[0]['field'] == 'effect')
        self.assertEqual(effect[5], 'missing referenced spell')

    def test_missing_linked_translation_and_forbidden_attempt_are_reported(self):
        self.spells['7']['locales']['enUS'].clear()
        FakeHarness.forbidden = ['GetItemSourceDetails']
        effect = self.run_fixture()['cases'][-1]
        self.assertEqual(effect[5], 'missing linked spell source description')
        self.assertEqual(effect[4], ['GetItemSourceDetails'])

    def test_missing_linked_target_with_owned_source_is_distinct(self):
        expected, reason = matrix.get_spell_expectation(self.spells, 7, 'frFR', FakeHarness().profile)
        self.assertIsNone(expected)
        self.assertEqual(reason, 'missing linked spell translation')

    def test_all_links_and_fields_are_enumerated(self):
        self.item['tooltipData']['set'] = {'name': 'Set', 'bonuses': [{'spellID': 7, 'threshold': 2}]}
        self.item['tooltipData']['effects'].append({'spellID': 8, 'triggerType': 2})
        rows = self.run_fixture()['cases']
        self.assertEqual([row[0]['field'] for row in rows], ['name', 'setName', 'effect', 'effect', 'setBonus'])
        self.assertEqual([row[0]['effectSpellId'] for row in rows if 'effectSpellId' in row[0]], [7, 8, 7])

    def test_native_fallback_and_forbidden_access_fail_coverage(self):
        reporter = CaseReporter('items', ['enUS'], ['baseline'])
        case = {'id': 1, 'field': 'description', 'locale': 'enUS', 'profile': 'baseline'}
        reporter.record(case, 'Translated', NATIVE_TEXT)
        reporter.record(case, 'Translated', 'Translated', forbidden=['GetItemSourceDetails'])
        self.assertEqual([failure['reason'] for failure in reporter.failures],
                         ['nativeFallback', 'forbiddenDependency'])

    def test_english_uses_en_us_fields(self):
        self.assertEqual(matrix.get_target(self.item, 'enUS', 'name'), 'Item')
        self.assertEqual(matrix.get_spell_expectation(self.spells, 7, 'enUS', FakeHarness().profile),
                         ('Deals 45 damage.', None))

    def test_scoped_loading_follows_transitive_references(self):
        self.spells['7']['locales']['enUS']['description'] = 'Deals $8s1 damage.'
        self.spells['8'] = {'locales': {'enUS': {'description': '$9s1'}}, 'tooltipData': {}}
        self.spells['9'] = {'locales': {'enUS': {'description': 'Leaf'}}, 'tooltipData': {}}
        selections = []

        def load(root, kind, ids=None):
            selected = ids['spells']
            selections.append(set(selected))
            return {'catalogs': {'spells': {key: self.spells[key] for key in selected if key in self.spells}}}

        with patch.object(matrix, 'load_catalog', side_effect=load):
            spells = matrix.load_referenced_spells(matrix.ROOT, {'7'}, ['enUS'])
        self.assertEqual(selections, [{'7'}, {'8'}, {'9'}])
        self.assertEqual(set(spells), {'7', '8', '9'})

    def test_drink_uses_synthetic_displayed_values(self):
        report = matrix.run_matrix(locales=['frFR'], ids=[159], profiles=['baseline'])
        self.assertFalse([row for row in report['failures'] if row['field'] == 'effect'])
        self.assertGreater(report['counts']['passed'], 1)


if __name__ == '__main__':
    unittest.main()
