"""Matrix regressions replay native fixtures; reverse inputs are explicitly derived."""
import copy
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/source-scan'))
import official_tooltip_matrix as matrix
import report_tooltip_gaps as gaps
from roundtrip_tooltip_campaign import quantities
from triage_official_tooltip_matrix import numeric_context


class CapturedMatrixRegressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.observations = {}
        item_ids = (13524, 280404, 16688, 17353, 10555, 20136, 21189, 22195, 22197, 22198, 249470)
        for observation in matrix.observations(ROOT / 'tests/fixtures/tooltip-campaign'):
            if observation['locale'] == 'frFR' and observation['id'] in (13524, 280404, 1243, 1225906, 16688, 1079, 17353, 10094, 1247434, 10614,
                                                                     10555, 20136, 21189, 22195, 22197, 22198, 249470) \
                    and observation['kind'] == ('item' if observation['id'] in item_ids else 'spell'):
                cls.observations.setdefault(observation['id'], observation)
            elif observation['locale'] == 'enUS' and observation['id'] in (9513, 4637, 16190, 17877, 459619) \
                    and observation['kind'] == ('item' if observation['id'] == 4637 else 'spell'):
                cls.observations.setdefault(observation['id'], observation)
            if len(cls.observations) == 22:
                break

    def replay(self, observation, target, source=None, data=None):
        replay = gaps.Replay(source or observation['locale'], {
            key: value for key, value in observation['globals'].items() if value != '<nil>'
        } if not source else {}, tooltip_types=observation.get('types'))
        replay.install_calls(observation['calls'], observation.get('unit'))
        missing, error, _ = replay.run(observation['kind'], observation['id'],
            data or gaps.clean(observation['data']), target, gaps.clean(observation.get('processing')),
            observation.get('visible') if not source else None, observation.get('unit'))
        self.assertIsNone(error)
        self.assertEqual(missing, [])
        rendered, error = matrix.read_rendered(replay)
        self.assertIsNone(error)
        return rendered

    def test_shadow_resistance_uses_stat_school_context(self):
        rows = self.replay(self.observations[13524], 'zhTW')
        self.assertIn('+10 暗影抗性', [row['left'] for row in rows])

    def test_owned_cosmetic_subclass_resolves_ambiguous_korean_and_chinese_labels(self):
        observation = self.observations[280404]
        self.check_derived_roundtrips(observation, ('koKR', 'zhTW'), ('enUS', 'frFR', 'deDE'),
            {'enUS': 'Cosmetic', 'frFR': 'Ornemental', 'deDE': 'Kosmetisch'})

    def check_derived_roundtrips(self, observation, sources, targets, expected=None, compare_quantities=False):
        original = copy.deepcopy(observation)
        for source in sources:
            translated = self.replay(observation, source)
            derived = copy.deepcopy(gaps.clean(observation['data']))
            self.assertEqual(len(derived['lines']), len(translated))
            for line, row in zip(derived['lines'], translated):
                for field, side in (('leftText', 'left'), ('rightText', 'right')):
                    if row[side] is None:
                        line.pop(field, None)
                    else:
                        line[field] = row[side]
            for target in targets:
                with self.subTest(derivedSource=source, target=target):
                    returned = self.replay(observation, target, source, derived)
                    if expected:
                        self.assertIn(expected[target], [row['left'] for row in returned])
                    if compare_quantities:
                        direct = self.replay(observation, target)
                        self.assertNotRegex(str(translated), r'%\d+[ \t]*\$')
                        self.assertNotRegex(str(returned), r'%\d+[ \t]*\$')
                        self.assertEqual(quantities(direct, ',', '.'), quantities(returned, ',', '.'))
        self.assertEqual(observation, original)

    def test_real_combo_cost_and_item_duration_reverse_from_owned_format_keys(self):
        for entity in (1079, 17353):
            self.check_derived_roundtrips(self.observations[entity], ('enUS', 'deDE', 'koKR', 'zhTW'), ('frFR',))

    def test_real_russian_plural_lists_and_nouns_before_counts(self):
        for entity in (10094, 1247434):
            with self.subTest(entity=entity):
                self.check_derived_roundtrips(self.observations[entity], ('ruRU',), ('frFR', 'enUS'))

    def test_real_portuguese_stats_keep_values_through_malformed_positional_formats(self):
        for entity in (10555, 20136, 21189, 22195, 22197, 22198, 249470):
            with self.subTest(entity=entity):
                self.check_derived_roundtrips(self.observations[entity], ('ptBR',), ('deDE',), compare_quantities=True)

    def test_real_native_plural_control_is_not_a_displayed_four(self):
        observation = self.observations[1243]
        native = [{'left': row.get('leftText'), 'right': row.get('rightText')}
                  for row in gaps.clean(observation['data'])['lines']]
        self.assertEqual(quantities(native, ',', ' ')[-1], ['4', '1'])

    def test_real_grouped_feast_quantity_is_one_number(self):
        rows = self.replay(self.observations[1225906], 'frFR')
        self.assertIn('2451', quantities(rows, ',', '\u202f')[-1])
        self.assertNotIn('451', quantities(rows, ',', '\u202f')[-1])

    def test_real_compact_magnitude_compares_using_owned_client_units(self):
        observation = self.observations[459619]
        native = [{'left': row.get('leftText'), 'right': row.get('rightText')}
                  for row in gaps.clean(observation['data'])['lines']]
        replay = gaps.Replay('enUS', {})
        decimal, grouping, magnitudes = numeric_context(replay, 'enUS')
        self.assertIn('million', magnitudes)
        target_decimal, target_grouping, target_magnitudes = numeric_context(replay, 'frFR')
        self.assertEqual(quantities(native, decimal, grouping, magnitudes),
                         quantities(self.replay(observation, 'frFR'), target_decimal, target_grouping, target_magnitudes))

    def test_real_diagnostics_resolve_owned_reagent_tool_and_locked_labels(self):
        for entity in (9513, 4637, 16190, 17877):
            with self.subTest(entity=entity):
                self.replay(self.observations[entity], 'frFR')

    def test_real_tool_section_reverses_full_width_colon_headers(self):
        self.check_derived_roundtrips(self.observations[10614], ('zhCN', 'zhTW'), ('frFR', 'enUS'))

    def test_real_magister_set_name_uses_source_backed_official_fields(self):
        for locale in matrix.OFFICIAL_LOCALES:
            if locale != 'frFR':
                with self.subTest(locale=locale):
                    rows = self.replay(self.observations[16688], locale)
                    self.assertTrue(any(quantities([row], '.', ',') == [['0', '3']] for row in rows))


if __name__ == '__main__':
    unittest.main()
