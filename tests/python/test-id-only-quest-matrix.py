"""Focused checks for the ID-only quest matrix."""

import unittest
from unittest.mock import patch

import id_only_quest_matrix as matrix
from id_only_matrix_harness import CaseReporter, IdOnlyHarness, NATIVE_TEXT
from id_only_quest_matrix import format_expected, localized_record


class IdOnlyQuestMatrixTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.harness = IdOnlyHarness()

    def setUp(self):
        self.harness.set_context('frFR', 987654, 'baseline')
        self.harness.lua.globals().fixtureQuest = self.harness.to_lua({
            'title': 'Bonjour', 'summary': 'Collecter $1oa',
            'objectiveLines': [{'index': 1, 'type': 'item', 'text': 'Objets: {current}/{required}'}],
        })
        self.harness.lua.execute(b'ForeverRosettaStoneDB.GetQuest = function() return fixtureQuest end')

    def test_real_renderer_uses_indexed_objective_and_blocks_source_matching(self):
        self.harness.set_objectives([{'type': 'item', 'text': NATIVE_TEXT, 'numFulfilled': 0, 'numRequired': 5}])
        actual, error, forbidden = self.harness.attempt(
            lambda: self.harness.addon.GetProgressLines(self.harness.addon, 987654)[1][b'translated'])
        self.assertEqual(actual.decode(), 'Objets: 0/5')
        self.assertIsNone(error)
        self.assertFalse(forbidden)

        self.harness.set_objectives([{'type': 'log', 'text': NATIVE_TEXT}])
        actual, error, forbidden = self.harness.attempt(
            lambda: self.harness.addon.GetProgressLines(self.harness.addon, 987654)[1][b'translated'])
        self.assertEqual(actual.decode(), NATIVE_TEXT)
        self.assertIsNone(error)
        self.assertFalse(forbidden)

    def test_standing_preserves_missing_data_without_matching(self):
        self.harness.lua.globals().fixtureQuest[b'objectiveLines'][1][b'text'] = b'Faction: {standing}'
        self.harness.set_objectives([{'type': 'item', 'text': NATIVE_TEXT, 'numFulfilled': 0, 'numRequired': 5}])
        actual, error, forbidden = self.harness.attempt(
            lambda: self.harness.addon.GetProgressLines(self.harness.addon, 987654)[1][b'translated'])
        self.assertEqual(actual.decode(), NATIVE_TEXT)
        self.assertIsNone(error)
        self.assertFalse(forbidden)

    def test_reporter_counts_fallback_missing_and_unresolved_as_failures(self):
        reporter = CaseReporter('quests', ['frFR'], ['baseline'])
        case = {'id': 1, 'field': 'title', 'locale': 'frFR', 'profile': 'baseline'}
        reporter.record(case, 'Traduit', NATIVE_TEXT)
        reporter.record(case, None, None)
        expected, reason = format_expected('$unknown', {'sex': 2, 'current': 0, 'required': 5}, set(), 'frFR')
        reporter.record(case, expected, '$unknown', reason=reason)
        self.assertEqual(reporter.finish([1])['counts']['failed'], 3)

    def test_denominator_and_exclusions_cover_requested_records(self):
        quest = {'locales': {'frFR': {'title': 'Bonjour', 'summary': 'Collecter $1oa',
                                      'objectiveLines': [{'index': 1, 'type': 'item',
                                                          'text': 'Objets: {current}/{required}'}]}}}
        document = {'catalogs': {'quests': {'987654': quest,
                                            '987655': {'usageStatus': 'test', 'locales': {}}}}}

        def load_fixture(root, kind, ids=None):
            return document if kind == 'quests' else {'catalogs': {'items': {}}}

        with patch.object(matrix, 'load_catalog', side_effect=load_fixture), \
                patch.object(matrix, 'IdOnlyHarness', return_value=self.harness):
            report = matrix.run_matrix(locales=['frFR'], profiles=['baseline'])
        self.assertEqual(report['entityIds'], [987654])
        self.assertEqual(report['excluded'], {'987655': 'test'})
        self.assertFalse(any(case.get('surface') == 'offered' for case in report['failures']))
        self.assertGreater(report['counts']['passed'], 0)

    def test_context_and_verified_amounts_are_formatted_independently(self):
        profile = {'sex': 3, 'current': 2, 'required': 9}
        actual, reason = format_expected('$N, $Gmonsieur:madame; $C: $2oa, {current}/{required}',
                                         profile, {2}, 'frFR')
        self.assertEqual(actual, 'TestName, madame Guerrière: 9, 2/9')
        self.assertIsNone(reason)

    def test_missing_target_and_unverified_amount_are_failures(self):
        profile = {'sex': 2, 'current': 0, 'required': 5}
        self.assertIsNone(format_expected(None, profile, {1}, 'enUS')[0])
        self.assertIsNone(format_expected('Collect $2oa', profile, {1}, 'enUS')[0])
        self.assertIsNone(format_expected('Collect {standing}', profile, {1}, 'enUS')[0])
        self.assertIsNone(format_expected('Collect $other', profile, {1}, 'enUS')[0])
        self.assertIsNone(format_expected('Collect {unknown}', profile, {1}, 'enUS')[0])

    def test_verified_faction_reactions_change_by_profile_without_text_matching(self):
        entity = {'clientObjectiveTargets': [
            {'index': 3, 'kind': 'faction', 'id': 92, 'type': 'reputation'},
            {'kind': 'faction', 'id': 93, 'type': 'reputation'},
        ]}
        # An implicit list position is never a verified faction binding.
        entity['clientObjectiveTargets'][1]['index'] = 2
        self.assertEqual(matrix.verified_faction_targets(entity), {3: 92, 2: 93})
        del entity['clientObjectiveTargets'][1]['index']
        self.assertEqual(matrix.verified_faction_targets(entity), {3: 92})
        for profile_name, label in [('baseline', 'Neutre'), ('modified', 'Amical')]:
            self.harness.set_context('frFR', 987654, profile_name)
            self.harness.lua.globals().fixtureQuest = self.harness.to_lua({'title': 'Bonjour', 'objectiveLines': [
                {'index': 2, 'type': 'reputation', 'text': 'Faction: {standing}', 'factionID': 92}]})
            self.harness.set_objectives([{'type': 'item', 'text': NATIVE_TEXT},
                                         {'type': 'reputation', 'text': NATIVE_TEXT}])
            expected, reason = format_expected('Faction: {standing}', self.harness.profile, {2}, 'frFR', 92)
            actual, error, forbidden = self.harness.attempt(
                lambda: self.harness.addon.GetProgressLines(self.harness.addon, 987654)[2][b'translated'])
            self.assertEqual((expected, reason), ('Faction: ' + label, None))
            self.assertEqual(actual.decode(), expected)
            self.assertIsNone(error)
            self.assertFalse(forbidden)

    def test_unbound_or_unknown_faction_does_not_gain_a_standing_expectation(self):
        profile = {'sex': 2, 'current': 0, 'required': 5, 'factionReactions': {92: 4}}
        for faction in (None, 93):
            self.assertEqual(format_expected('{standing}', profile, {1}, 'frFR', faction),
                             (None, 'reputation standing unavailable from structured test context'))

    def test_captured_faction_api_contract_is_id_keyed(self):
        # Session 2, enUS build 70938: factions 92 and 93 each returned their own ID
        # with reaction 4; modified reaction 5 is a controlled test input.
        query = self.harness.lua.eval(b'function(id) return C_Reputation.GetFactionDataByID(id) end')
        for profile, reaction in [('baseline', 4), ('modified', 5)]:
            self.harness.set_context('enUS', 1, profile)
            for faction in (92, 93):
                actual = query(faction)
                self.assertEqual((actual[b'factionID'], actual[b'reaction']), (faction, reaction))
            self.assertIsNone(query(94))

    def test_verified_binding_configures_arbitrary_faction_without_global_allowlist(self):
        entity = {'clientObjectiveTargets': [{'index': 1, 'kind': 'faction', 'id': 123456,
                                              'type': 'reputation'}]}
        factions = matrix.verified_faction_targets(entity)
        query = self.harness.lua.eval(b'function(id) return C_Reputation.GetFactionDataByID(id) end')
        for profile, label in [('baseline', 'Neutre'), ('modified', 'Amical')]:
            self.harness.set_context('frFR', 987654, profile)
            self.harness.set_verified_factions(set(factions.values()), profile)
            self.assertEqual(query(123456)[b'factionID'], 123456)
            self.assertIsNone(query(92))
            self.assertEqual(format_expected('{standing}', self.harness.profile, {1}, 'frFR', 123456),
                             (label, None))
            self.assertIsNone(format_expected('{standing}', self.harness.profile, {1}, 'frFR', 92)[0])
            self.harness.lua.globals().fixtureQuest = self.harness.to_lua({'title': 'Bonjour', 'objectiveLines': [
                {'index': 1, 'type': 'reputation', 'text': '{standing}', 'factionID': 123456}]})
            self.harness.set_objectives([{'type': 'reputation', 'text': NATIVE_TEXT}])
            actual, error, forbidden = self.harness.attempt(
                lambda: self.harness.addon.GetProgressLines(self.harness.addon, 987654)[1][b'translated'])
            self.assertEqual(actual.decode(), label)
            self.assertIsNone(error)
            self.assertFalse(forbidden)

    def test_narrative_angle_brackets_are_literal_text(self):
        profile = {'sex': 2, 'current': 0, 'required': 5}
        expected, reason = format_expected('<snort> {A sound echoes.} Hello, <name>.', profile, set(), 'enUS')
        self.assertEqual(expected, '<snort> {A sound echoes.} Hello, TestName.')
        self.assertIsNone(reason)

    def test_unresolved_templates_have_specific_reasons(self):
        profile = {'sex': 2, 'current': 0, 'required': 5}
        for text, reason in [
            ('{standing}', 'reputation standing unavailable from structured test context'),
            ('<Honored/HonoredOne>', 'unsupported context-dependent slash selector'),
            ('$other', 'unrecognized dollar template token'),
            ('{unknown}', 'unrecognized symbolic brace token'),
        ]:
            with self.subTest(text=text):
                self.assertEqual(format_expected(text, profile, set(), 'enUS'), (None, reason))

    def test_multiple_objectives_use_verified_types_for_all_rows(self):
        localized = {'title': 'Bonjour', 'summary': 'Collecter', 'objectiveLines': [
            {'index': 1, 'type': 'item', 'text': 'Objets: {current}/{required}'},
            {'index': 2, 'type': 'monster', 'text': 'Ennemis: {current}/{required}'},
        ]}
        self.harness.lua.globals().fixtureQuest = self.harness.to_lua(localized)
        document = {'catalogs': {'quests': {'987654': {'locales': {'frFR': localized}}}}}

        def load_fixture(root, kind, ids=None):
            return document if kind == 'quests' else {'catalogs': {'items': {}}}

        with patch.object(matrix, 'load_catalog', side_effect=load_fixture), \
                patch.object(matrix, 'IdOnlyHarness', return_value=self.harness):
            report = matrix.run_matrix(locales=['frFR'], profiles=['baseline'])
        self.assertFalse([case for case in report['failures'] if case['field'] == 'objectiveLines'])

    def test_removed_english_alias_is_not_resolved(self):
        entity = {'locales': {'enUS': {'title': 'Title'}}}
        self.assertEqual(localized_record(entity, 'enUS')['title'], 'Title')
        self.assertEqual(localized_record(entity, 'enGB'), {})
        self.assertEqual(localized_record(entity, 'frFR'), {})

    def test_objective_target_kinds_do_not_invent_live_types(self):
        entity = {'locales': {'enUS': {'objectiveLines': [{'index': 2, 'type': 'monster', 'text': 'x'}]}},
                  'clientObjectiveTargets': [{'kind': 'npc', 'id': 1}, {'kind': 'npc', 'id': 2},
                                             {'kind': 'item', 'id': 3}]}
        types, missing = matrix.get_objective_types(entity)
        self.assertEqual(types, {1: set(), 2: {'monster'}, 3: {'item'}})
        self.assertEqual(missing, {1: 'npc'})

    def test_sparse_client_indices_and_invalid_mappings(self):
        from tools.build.runtime_catalog import project_objectives
        item = {'locales': {'frFR': {'name': 'Objet', 'translationMetadata': {
            'fields': {'name': {'origin': 'original'}}}}}}
        quest = {'locales': {'frFR': {}}, 'clientObjectiveTargets': [
            {'index': 2, 'kind': 'item', 'id': 1}]}
        lines, _ = project_objectives(quest, {}, 'frFR', {'1': item})
        self.assertEqual(lines, [{'index': 2, 'type': 'item', 'text': 'Objet: {current}/{required}'}])
        self.assertEqual(matrix.get_objective_types(quest)[0], {2: {'item'}})
        legacy = {'clientObjectiveTargets': [{'kind': 'item', 'id': 1}]}
        self.assertEqual(project_objectives(legacy, {}, 'frFR', {'1': item})[0][0]['index'], 1)
        explicit = {'objectiveLines': [{'index': 2, 'type': 'event', 'text': 'Texte'}]}
        self.assertEqual(project_objectives(quest, explicit, 'frFR', {'1': item})[0], explicit['objectiveLines'])
        for targets in ([{'index': 0, 'kind': 'item', 'id': 1}],
                        [{'index': -1, 'kind': 'item', 'id': 1}],
                        [{'index': None, 'kind': 'item', 'id': 1}],
                        [{'index': True, 'kind': 'item', 'id': 1}],
                        [{'index': 1.5, 'kind': 'item', 'id': 1}],
                        [{'index': 2, 'kind': 'item', 'id': 1}, {'index': 2, 'kind': 'item', 'id': 1}],
                        [{'index': 2, 'kind': 'item', 'id': 1}, {'kind': 'item', 'id': 1}]):
            invalid = {'locales': {'frFR': {}}, 'clientObjectiveTargets': targets}
            with self.subTest(targets=targets):
                with self.assertRaises(ValueError):
                    project_objectives(invalid, {}, 'frFR', {'1': item})
                with self.assertRaises(ValueError):
                    matrix.get_objective_types(invalid)

    def test_event_surface_prefers_indexed_event_text(self):
        localized = {'title': 'Bonjour', 'eventObjectiveLabel': 'Événement',
                     'objectiveLines': [{'index': 1, 'type': 'event', 'text': 'Texte indexé'}]}
        self.harness.lua.globals().fixtureQuest = self.harness.to_lua(localized)
        document = {'catalogs': {'quests': {'987654': {'locales': {'frFR': localized}}}}}

        def load_fixture(root, kind, ids=None):
            return document if kind == 'quests' else {'catalogs': {'items': {}}}

        with patch.object(matrix, 'load_catalog', side_effect=load_fixture), \
                patch.object(matrix, 'IdOnlyHarness', return_value=self.harness):
            report = matrix.run_matrix(locales=['frFR'], profiles=['baseline'])
        self.assertFalse([case for case in report['failures'] if case.get('surface') == 'event'])

    def test_unindexed_objective_evidence_is_a_failure(self):
        quest = {'locales': {'frFR': {'title': 'Bonjour'}},
                 'objectiveTargets': {'npc': [{'id': 123, 'sourceIndex': 1}]}}
        document = {'catalogs': {'quests': {'987654': quest}}}

        def load_fixture(root, kind, ids=None):
            return document if kind == 'quests' else {'catalogs': {'items': {}}}

        with patch.object(matrix, 'load_catalog', side_effect=load_fixture), \
                patch.object(matrix, 'IdOnlyHarness', return_value=self.harness):
            report = matrix.run_matrix(locales=['frFR'], profiles=['baseline'])
        failures = [case for case in report['failures'] if case['field'] == 'objectiveLines']
        self.assertEqual(len(failures), 1)
        self.assertEqual(failures[0]['reason'], 'missing verified client objective index')
        self.assertNotIn('index', failures[0])
        self.assertFalse([case for case in report['notApplicable'] if case['field'] == 'objectiveLines'])


if __name__ == '__main__':
    unittest.main()
