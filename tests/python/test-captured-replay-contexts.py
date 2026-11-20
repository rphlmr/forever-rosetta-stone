"""Keep real row provenance and exercise decoder fixes without fabricated game payloads."""
import copy
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/source-scan'))
import official_tooltip_matrix as matrix
import report_tooltip_gaps as gaps
from audit_tooltip_hovers import restore
from derived_tooltip_rows import derive
from roundtrip_tooltip_campaign import quantities
from triage_official_tooltip_matrix import triage
from import_item_interactions import proposals


class CapturedReplayContextTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cases = {}
        cls.without_sex = {}
        cls.with_sex = {}
        for observation in matrix.observations(ROOT / 'tests/fixtures/tooltip-campaign'):
            key = observation['kind'], observation['id']
            if observation['locale'] == 'frFR' and key in (('item', 2683), ('item', 240028), ('item', 273930),
                                                          ('spell', 1219548), ('spell', 1223352),
                                                          ('spell', 10138), ('spell', 10140), ('spell', 1225906), ('spell', 459611),
                                                          ('spell', 414689), ('spell', 415292), ('spell', 1245154), ('spell', 16873),
                                                          ('spell', 20925)):
                cls.cases.setdefault(key, observation)
            if observation['kind'] == 'player':
                apis = (observation.get('unit') or {}).get('apis', {})
                if (apis.get('UnitRace', {}).get('values', {}).get(3) == 1
                        and apis.get('UnitLevel', {}).get('values', {}).get(1) == 7
                        and 'UnitSex' not in apis):
                    cls.player = observation
            if observation['kind'] == 'spell' and observation['locale'] == 'frFR' \
                    and observation['id'] in (10138, 10140, 1225906) and 'UnitSex' not in observation['calls']:
                cls.without_sex.setdefault(observation['id'], observation)
            if observation['kind'] == 'spell' and observation['locale'] == 'frFR' \
                    and observation['id'] in (10138, 1225906) and 'UnitSex' in observation['calls']:
                cls.with_sex.setdefault(observation['id'], observation)
            if observation['kind'] == 'spell' and observation['id'] == 10614 and observation['locale'] == 'frFR' \
                    and 'une attaque' in str(gaps.clean(observation['data'])) and not hasattr(cls, 'windfury'):
                cls.windfury = observation
            if observation['kind'] == 'item' and observation['id'] in (12700, 276539, 7951, 280404, 19951, 6182, 13724, 5863):
                cls.cases.setdefault(('item', observation['id']), observation)
            if observation['kind'] == 'spell' and observation['id'] == 15275 and observation['locale'] == 'frFR' \
                    and len(gaps.clean(observation['data'])['lines']) == 3 and len(observation.get('visible') or []) == 8:
                cls.preview = observation

        cls.outcomes = None

    @classmethod
    def load_matrix_results(cls):
        if cls.outcomes is not None:
            return
        fixtures = ROOT / 'tests/fixtures/tooltip-campaign'
        captures = (cls.windfury, cls.player, cls.cases['spell', 459611], cls.cases['item', 5863])
        keys = {matrix.fingerprint(observation) for observation in captures}
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
            report = matrix.run(fixtures, Path(directory) / 'report', case_keys=keys)
            cls.events = triage(report, fixtures)['events']
        cls.outcomes = {case['key']: case for case in report['cases']}
        cls.failures = report['failures']

    def matrix_case(self, observation):
        self.load_matrix_results()
        key = matrix.fingerprint(observation)
        paths = self.outcomes[key]['byPath']
        self.assertEqual(sum(sum(statuses.values()) for statuses in paths.values()), 90)
        return paths, [failure for failure in self.failures if failure['case'] == key]

    def load(self, name):
        capture = restore(json.loads((ROOT / 'tests/fixtures/tooltip-campaign' / name).read_text()))
        return dict(locale=capture['source']['locale'], data=gaps.clean(capture['data']),
                    visible=matrix.visible(capture.get('visible', {})), processing=capture.get('processingInfo'),
                    globals={}, calls={}, kind='spell', id=capture['data']['id'])

    def render(self, observation, target, source=None, data=None, visible=None):
        replay = gaps.Replay(source or observation['locale'],
            {key: value for key, value in observation['globals'].items() if value != '<nil>'} if not source else {},
            tooltip_types=observation.get('types'))
        replay.install_calls(observation['calls'], observation.get('unit'))
        kind = 'spell' if observation['kind'] == 'aura' else observation['kind']
        missing, error, _ = replay.run(kind, observation['id'], data or gaps.clean(observation['data']), target,
            gaps.clean(observation.get('processing')), observation.get('visible') if visible is None else visible,
            observation.get('unit'))
        self.assertIsNone(error)
        self.assertEqual(missing, [])
        rows, error = matrix.read_rendered(replay)
        self.assertIsNone(error)
        return replay, rows

    def derived(self, replay, observation, rows):
        data, issue = derive(gaps.clean(observation['data']), rows,
            matrix.copied_rows(replay.lua.globals().ReplayOutputBindings),
            matrix.copied_rows(replay.lua.globals().ReplaySuppressions),
            visible_surface=(observation.get('processing') or {}).get('getterName') in ('GetTraitEntry', 'GetTalent'))
        self.assertIsNone(issue)
        visible = [{'left': {'status': 'ok', 'values': {1: row['left'] or '<nil>'}},
                    'right': {'status': 'ok', 'values': {1: row['right'] or '<nil>'}}} for row in rows]
        return data, visible

    def test_actual_partial_talent_data_does_not_acquire_invented_header_metadata(self):
        observation = self.load('talent-16190-enUS.json')
        original = copy.deepcopy(observation)
        replay, rows = self.render(observation, 'frFR')
        self.assertGreater(len(rows), len(observation['data']['lines']))
        derived, visible = self.derived(replay, observation, rows)
        self.assertEqual(len(derived['lines']), len(observation['data']['lines']))
        for before, after in zip(observation['data']['lines'], derived['lines']):
            self.assertEqual({k: v for k, v in before.items() if k not in ('leftText', 'rightText')},
                             {k: v for k, v in after.items() if k not in ('leftText', 'rightText')})
        self.render(observation, 'enUS', 'frFR', derived, visible)
        self.assertEqual(original, observation)

    def test_actual_set_bonus_percent_escapes_reverse_without_becoming_extra_literals(self):
        for entity, source in ((12700, 'deDE'), (276539, 'deDE'), (7951, 'esES')):
            observation = self.cases['item', entity]
            with self.subTest(entity=entity, derivedSource=source):
                original = copy.deepcopy(observation)
                replay, rows = self.render(observation, source)
                self.assertNotIn('%%', str(rows))
                data, visible = self.derived(replay, observation, rows)
                _, returned = self.render(observation, 'frFR', source, data, visible)
                _, expected = self.render(observation, 'frFR')
                self.assertEqual(quantities(expected, ',', ' '), quantities(returned, ',', ' '))
                self.assertEqual(original, observation)

    def test_actual_talent_heading_reverses_ambiguous_ui_wording_with_talent_context(self):
        observation = self.preview
        original = copy.deepcopy(observation)
        for source in ('deDE', 'esMX', 'koKR'):
            with self.subTest(derivedSource=source):
                replay, rows = self.render(observation, source)
                data, visible = self.derived(replay, observation, rows)
                _, returned = self.render(observation, 'frFR', source, data, visible)
                self.assertTrue(any('Rang suivant' in (row['left'] or '') for row in returned))
        self.assertEqual(original, observation)

    def test_actual_duration_boundaries_ignore_only_outer_template_whitespace(self):
        for entity in (414689, 415292, 1245154):
            observation = self.cases['spell', entity]
            with self.subTest(entity=entity):
                original = copy.deepcopy(observation)
                replay, rows = self.render(observation, 'deDE')
                data, visible = self.derived(replay, observation, rows)
                _, returned = self.render(observation, 'enUS', 'deDE', data, visible)
                _, expected = self.render(observation, 'enUS')
                self.assertEqual(quantities(expected, '.', ','), quantities(returned, '.', ','))
                self.assertEqual(original, observation)

    def test_actual_legacy_scalar_magnitude_case_reverses_without_signed_amount_assumptions(self):
        observation = self.cases['item', 19951]
        original = copy.deepcopy(observation)
        replay, rows = self.render(observation, 'zhTW')
        data, visible = self.derived(replay, observation, rows)
        for target in sorted(matrix.OFFICIAL_LOCALES - {'zhTW'}):
            with self.subTest(target=target):
                self.render(observation, target, 'zhTW', data, visible)
        self.assertEqual(original, observation)

    def test_actual_zero_variance_stat_endpoints_keep_the_captured_amount(self):
        for kind, entity in (('item', 6182), ('spell', 16873)):
            observation = self.cases[kind, entity]
            original = copy.deepcopy(observation)
            with self.subTest(kind=kind, entity=entity):
                replay, rows = self.render(observation, 'zhTW')
                data, visible = self.derived(replay, observation, rows)
                _, returned = self.render(observation, 'enUS', 'zhTW', data, visible)
                _, expected = self.render(observation, 'enUS')
                self.assertEqual(quantities(expected, '.', ','), quantities(returned, '.', ','))
                self.assertEqual(original, observation)

    def test_actual_conditional_with_leading_source_space_reverses_from_spanish(self):
        observation = self.cases['item', 13724]
        original = copy.deepcopy(observation)
        replay, rows = self.render(observation, 'esES')
        data, visible = self.derived(replay, observation, rows)
        _, returned = self.render(observation, 'deDE', 'esES', data, visible)
        _, expected = self.render(observation, 'deDE')
        self.assertEqual(quantities(expected, ',', '.'), quantities(returned, ',', '.'))
        self.assertEqual(original, observation)

    def test_actual_cosmetic_known_requirement_uses_owned_item_class_in_every_direction(self):
        observation = self.cases['item', 280404]
        original = copy.deepcopy(observation)
        for source in sorted(matrix.OFFICIAL_LOCALES - {observation['locale']}):
            with self.subTest(derivedSource=source):
                replay, rows = self.render(observation, source)
                data, visible = self.derived(replay, observation, rows)
                for target in sorted(matrix.OFFICIAL_LOCALES - {source}):
                    self.render(observation, target, source, data, visible)
        self.assertEqual(original, observation)

    def test_actual_windfury_capture_round_trips_with_the_fixed_extra_attack(self):
        paths, _ = self.matrix_case(self.windfury)
        for statuses in paths.values():
            self.assertEqual(set(statuses), {'passed'})
        key = matrix.fingerprint(self.windfury)
        self.assertFalse(any(event['case'] == key for event in self.events))

    def test_actual_rank_preview_repeated_passive_row_keeps_its_captured_origin(self):
        observation = self.preview
        original = copy.deepcopy(observation)
        replay, rows = self.render(observation, 'enUS')
        derived, visible = self.derived(replay, observation, rows)
        self.assertEqual(len(derived['lines']), 3)
        _, returned = self.render(observation, 'frFR', 'enUS', derived, visible)
        expected = [{'left': row['left']['values'].get(1),
                     'right': row['right']['values'].get(1)} for row in observation['visible']]
        self.assertEqual(quantities(expected, ',', ' '), quantities(returned, ',', ' '))
        self.assertEqual(original, observation)

    def test_actual_scaled_trait_tokens_keep_one_second_and_fifteen_percent_in_every_target(self):
        observation = self.load('talent-1310315-frFR.json')
        for target in sorted(matrix.OFFICIAL_LOCALES - {'frFR'}):
            with self.subTest(target=target):
                replay, rows = self.render(observation, target)
                self.assertEqual(quantities(rows[-1:], '.', ','), [['1', '15']])
                data, visible = self.derived(replay, observation, rows)
                self.render(observation, 'frFR', target, data, visible)

    def test_actual_scalar_formula_without_leading_sigil_binds_the_same_live_values(self):
        for entity in (1219548, 1223352):
            observation = self.cases['spell', entity]
            replay, rows = self.render(observation, 'zhTW')
            data, visible = self.derived(replay, observation, rows)
            _, returned = self.render(observation, 'frFR', 'zhTW', data, visible)
            _, expected = self.render(observation, 'frFR')
            self.assertEqual(quantities(expected, ',', ' '), quantities(returned, ',', ' '))

    def test_actual_food_duration_amount_boundary_reverses_without_swapping_values(self):
        observation = self.cases['item', 2683]
        replay, rows = self.render(observation, 'deDE')
        data, visible = self.derived(replay, observation, rows)
        _, returned = self.render(observation, 'enUS', 'deDE', data, visible)
        _, expected = self.render(observation, 'enUS')
        self.assertEqual(quantities(expected, '.', ','), quantities(returned, '.', ','))

    def test_actual_player_race_api_and_personal_name_are_replayed(self):
        observation = self.player
        original = copy.deepcopy(observation)
        replay, rows = self.render(observation, 'enUS')
        self.assertEqual(rows[0]['left'], gaps.clean(observation['data'])['lines'][0]['leftText'])
        self.assertTrue(any('Level 7 Human' in (row['left'] or '') for row in rows))
        self.assertNotIn('UnitSex', replay.unit_evidence['apis'])
        self.assertEqual(original, observation)

    def test_actual_player_level_race_returns_from_every_successfully_generated_locale(self):
        original = copy.deepcopy(self.player)
        paths, failures = self.matrix_case(self.player)
        self.assertFalse(any(event['status'] in ('derived_incomplete', 'derived_error') for event in failures))
        returns = paths['return_to_native']
        forwards = paths['native_to_target']
        self.assertEqual(returns.get('passed', 0) + returns.get('text_difference_values_preserved', 0),
                         forwards.get('passed', 0) + forwards.get('text_difference_values_preserved', 0))
        self.assertFalse(any(event['path'] == 'return_to_native' and event['status'] != 'blocked_source_generation'
                             for event in failures))
        self.assertEqual(sum(returns.values()), 9)
        self.assertEqual(self.player, original)

    def test_generated_counter_proves_the_native_value_was_already_unresolved(self):
        observation = self.cases['spell', 459611]
        original = copy.deepcopy(observation)
        self.matrix_case(observation)
        key = matrix.fingerprint(observation)
        unresolved = [event for event in self.events if event['case'] == key
                      and event['category'] == 'inherited_unresolved_client_value']
        self.assertTrue(unresolved)
        for event in unresolved:
            self.assertEqual(event['path'], 'return_to_native')
            for proof in event['contextLossEvidence']:
                self.assertIn(proof['slot']['unresolved'], proof['nativeText'])
                self.assertNotIn('amount', proof['slot'])
        self.assertEqual(observation, original)

    def test_generated_literal_keeps_its_captured_interaction_identity(self):
        observation = self.cases['item', 5863]
        original = copy.deepcopy(observation)
        _, failures = self.matrix_case(observation)
        self.assertEqual(failures, [])
        replay = gaps.Replay('frFR', {})
        db = replay.database
        source, owner = db.GetGlobalStringByKey(db, b'ITEM_SIGNABLE', b'frFR')
        self.assertEqual(db.GetItemRules(db, observation['id'])[b'interactionLabelID'], owner)
        self.assertEqual(db.GetGlobalStringByKey(db, b'ITEM_READABLE', b'koKR')[0],
                         db.GetGlobalStringByKey(db, b'ITEM_SIGNABLE', b'koKR')[0])
        self.assertNotEqual(db.GetGlobalStringByKey(db, b'ITEM_READABLE', b'frFR')[0], source)
        self.assertEqual(observation, original)

    def test_interaction_import_proposes_only_the_native_owned_label_without_catalog_writes(self):
        path = ROOT / 'catalogs/items/5863.json'
        before = path.read_bytes()
        result = proposals(ROOT / 'tests/fixtures/tooltip-campaign', {5863})
        self.assertTrue(result[5863])
        self.assertTrue(all(fact['key'] == 'ITEM_SIGNABLE' for fact in result[5863]))
        self.assertTrue(all(fact['source']['sha256'] and fact['source']['sampleKind'] == 'api'
                            for fact in result[5863]))
        self.assertEqual(path.read_bytes(), before)

    def test_actual_item_tags_and_set_name_use_verified_official_source_fields(self):
        for entity in (240028, 273930):
            observation = self.cases['item', entity]
            for target in sorted(matrix.OFFICIAL_LOCALES - {'frFR'}):
                with self.subTest(entity=entity, target=target):
                    replay, rows = self.render(observation, target)
                    details = replay.database.GetItemDetails(replay.database, entity, target.encode())
                    tag, set_name = details[b'nameDescription'].decode(), details[b'set'][b'name'].decode()
                    self.assertTrue(any(tag in (row['left'] or '') for row in rows))
                    self.assertTrue(any(set_name in (row['left'] or '') for row in rows))

    def test_missing_gender_context_requires_actual_decoder_ambiguity_including_nested_templates(self):
        for entity, target, required in ((10138, 'enUS', True), (1225906, 'esES', True), (10140, 'koKR', False)):
            observation = self.without_sex[entity]
            replay = gaps.Replay('frFR', {key: value for key, value in observation['globals'].items() if value != '<nil>'})
            replay.install_calls(observation['calls'])
            data = gaps.clean(observation['data'])
            rows, error, _ = replay.run('spell', entity, data, target,
                gaps.clean(observation.get('processing')), observation.get('visible'))
            self.assertIsNone(error)
            self.assertEqual(bool(rows), required)
            rendered, render_error = matrix.read_rendered(replay)
            self.assertIsNone(render_error)
            self.assertTrue(rendered)
            context = gaps.missing_player_context(replay, 'spell', entity, data, observation['calls'], target, rows)
            self.assertEqual(bool(context), required)
            if required:
                self.assertEqual(context[0]['requiredApis'], ['UnitSex'])
                self.assertIn('player', context[0]['unitArguments'])

    def test_actual_context_sex_is_reused_only_for_the_recorded_player_argument(self):
        for entity, target in ((10138, 'enUS'), (1225906, 'esES')):
            observation = self.with_sex[entity]
            reference = observation['source']
            fixture = restore(json.loads((ROOT / reference['fixture']).read_text()))
            run = next(run for run in fixture['runs'] if run['run'] == reference['run'])
            sample = next(sample for sample in run['samples'] if sample['sample'] == reference['sample'])
            self.assertEqual(observation['calls']['UnitSex']['"player"'], sample['context']['sex'])
            self.assertNotIn('"mouseover"', observation['calls']['UnitSex'])
            self.render(observation, target)
            original = copy.deepcopy(sample['context'])
            explicit = {'UnitSex': {'"player"': sample['context']['sex']}}
            self.assertEqual(gaps.context_calls(explicit, sample['context'])['UnitSex'], explicit['UnitSex'])
            self.assertEqual(gaps.context_calls({}, sample['context'])['UnitSex'],
                             {'"player"': sample['context']['sex']})
            self.assertEqual(sample['context'], original)

    def test_actual_shield_requirement_uses_equipment_subclass_instead_of_absorb_labels(self):
        observation = self.cases['spell', 20925]
        replay, rows = self.render(observation, 'ruRU')
        data, visible = self.derived(replay, observation, rows)
        _, returned = self.render(observation, 'deDE', 'ruRU', data, visible)
        self.assertTrue(any('Schilde' in (row['left'] or '') for row in returned))
        self.assertFalse(any('Absorbiert' in (row['left'] or '') for row in returned))


if __name__ == '__main__':
    unittest.main()
